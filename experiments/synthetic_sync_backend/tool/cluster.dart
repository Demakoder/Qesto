// Own disposable PostgreSQL cluster only. No existing databases/services touched.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:postgres/postgres.dart';
import 'package:qesto_synthetic_sync/protocol.dart';

String randomSecret() => base64Url
    .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');
Future<void> command(String executable, List<String> args) async {
  final process = await Process.start(executable, args);
  final output = StringBuffer();
  final out = process.stdout.transform(utf8.decoder).listen(output.write);
  final err = process.stderr.transform(utf8.decoder).listen(output.write);
  final code = await process.exitCode.timeout(const Duration(seconds: 45));
  // pg_ctl's background children may inherit pipe handles on Windows. Waiting
  // for EOF via Process.run would hang despite successful pg_ctl termination.
  await out.cancel();
  await err.cancel();
  if (code != 0) throw StateError('$executable failed: $output');
}

Future<void> main(List<String> args) async {
  final runtime = Directory('.runtime').absolute;
  final bin = '${runtime.path}/postgres/pgsql/bin';
  final manifest = File('${runtime.path}/cluster.json');
  String ownedData(Map<String, dynamic> m) {
    final root = runtime
        .resolveSymbolicLinksSync()
        .replaceAll('\\', '/')
        .toLowerCase();
    final data = Directory(m['data'] as String).resolveSymbolicLinksSync();
    if (m['marker'] != experimentMarker ||
        !data
            .replaceAll('\\', '/')
            .toLowerCase()
            .startsWith('$root/cluster-') ||
        !File('$data/.qesto-synthetic-cluster').existsSync())
      throw StateError('Unowned cluster');
    return data;
  }

  if (args.single == 'resume') {
    final m = object(jsonDecode(manifest.readAsStringSync()));
    final data = ownedData(m);
    final status = await Process.run('$bin/pg_ctl.exe', ['-D', data, 'status']);
    if (status.exitCode == 0) {
      print('Isolated cluster already running');
      return;
    }
    await command('$bin/pg_ctl.exe', [
      '-D',
      data,
      '-l',
      '${Directory(data).parent.path}/postgres.log',
      '-o',
      '-h 127.0.0.1 -p ${m['pg_port']} -c fsync=on -c synchronous_commit=on -c max_connections=40',
      '-w',
      'start',
    ]);
    print('Resumed isolated cluster');
    return;
  }
  if (args.single == 'provision') {
    final m = object(jsonDecode(manifest.readAsStringSync()));
    ownedData(m);
    await provision(m);
    return;
  }
  if (args.single == 'stop') {
    final m = object(jsonDecode(manifest.readAsStringSync()));
    final data = ownedData(m);
    await command('$bin/pg_ctl.exe', ['-D', data, '-m', 'fast', '-w', 'stop']);
    print('Stopped isolated cluster; synthetic files retained.');
    return;
  }
  if (args.single != 'start' || manifest.existsSync())
    throw StateError(
      'Fresh runtime required; existing manifest is never overwritten',
    );
  final data = Directory(
    '${runtime.path}/cluster-${DateTime.now().microsecondsSinceEpoch}',
  )..createSync();
  final adminPassword = randomSecret();
  final dbPassword = randomSecret();
  final passwordFile = File('${data.path}/bootstrap-password')
    ..writeAsStringSync(adminPassword, flush: true);
  // initdb needs an empty directory; password file is alongside it.
  final pgdata = Directory('${data.path}/data');
  await command('$bin/initdb.exe', [
    '-D',
    pgdata.path,
    '-U',
    'qesto_admin',
    '--auth=scram-sha-256',
    '--encoding=UTF8',
    '--locale=C',
    '--pwfile=${passwordFile.path}',
  ]);
  passwordFile.deleteSync();
  File(
    '${pgdata.path}/.qesto-synthetic-cluster',
  ).writeAsStringSync(experimentMarker);
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  final m = {
    'marker': experimentMarker,
    'data': pgdata.absolute.path,
    'pg_port': port,
    'database': 'qesto_synthetic',
    'admin_password': adminPassword,
    'db_password': dbPassword,
    'cursor_key': base64Encode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    ),
    'principals': [
      for (final device in ['device-a', 'device-b', 'device-foreign'])
        {
          'device': device,
          'user': device == 'device-foreign'
              ? 'synthetic-other'
              : 'synthetic-owner',
          'workspace': device == 'device-foreign'
              ? 'workspace-other'
              : 'workspace-main',
          'token': randomSecret(),
        },
    ],
  };
  manifest.writeAsStringSync(jsonEncode(m), flush: true);
  await command('$bin/pg_ctl.exe', [
    '-D',
    pgdata.path,
    '-l',
    '${data.path}/postgres.log',
    '-o',
    '-h 127.0.0.1 -p $port -c fsync=on -c synchronous_commit=on -c max_connections=40',
    '-w',
    'start',
  ]);
  await provision(m);
  print(
    jsonEncode({
      'started': true,
      'host': '127.0.0.1',
      'port': port,
      'database': 'qesto_synthetic',
    }),
  );
}

Future<void> provision(Map<String, dynamic> m) async {
  final port = m['pg_port'] as int;
  final adminPassword = m['admin_password'] as String;
  final dbPassword = m['db_password'] as String;
  if (!RegExp(r'^[A-Za-z0-9_-]{40,50}$').hasMatch(dbPassword))
    throw StateError('Invalid generated password');
  final c = await Connection.open(
    Endpoint(
      host: '127.0.0.1',
      port: port,
      database: 'postgres',
      username: 'qesto_admin',
      password: adminPassword,
    ),
    settings: ConnectionSettings(sslMode: SslMode.disable),
  );
  try {
    await c.execute(
      "CREATE ROLE qesto_sync LOGIN PASSWORD '$dbPassword' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS",
    );
    await c.execute('CREATE DATABASE qesto_synthetic');
  } finally {
    await c.close();
  }
  final d = await Connection.open(
    Endpoint(
      host: '127.0.0.1',
      port: port,
      database: 'qesto_synthetic',
      username: 'qesto_admin',
      password: adminPassword,
    ),
    settings: ConnectionSettings(sslMode: SslMode.disable),
  );
  try {
    await d.execute(
      File('sql/schema.sql').readAsStringSync(),
      queryMode: QueryMode.simple,
    );
  } finally {
    await d.close();
  }
  print('Provisioned isolated schema and restricted application role');
}
