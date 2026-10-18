import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:qesto_synthetic_sync/client.dart';
import 'package:qesto_synthetic_sync/config.dart';
import 'package:qesto_synthetic_sync/domain.dart';
import 'package:qesto_synthetic_sync/protocol.dart';

import 'package:qesto_synthetic_sync/testing/server_process.dart';
export 'package:qesto_synthetic_sync/testing/server_process.dart';

class Harness {
  late final TestConfig admin;
  late final TestConfig config;
  late final Directory directory;
  late final File configFile;
  final servers = <ServerProcess>[];
  Future<void> start() async {
    admin = TestConfig.read('.runtime/cluster.json');
    directory = Directory(
      '.runtime/test-${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    final map = object(jsonDecode(jsonEncode(admin.json)))
      ..remove('admin_password')
      ..remove('data');
    final suffix = DateTime.now().microsecondsSinceEpoch;
    for (final p in map['principals'] as List) {
      p['workspace'] = '${p['workspace']}-$suffix';
    }
    config = TestConfig(map);
    configFile = File('${directory.path}/config.json')
      ..writeAsStringSync(jsonEncode(map));
    final c = await admin.connect(admin: true);
    try {
      for (final p in [config.principals.first, config.principals.last]) {
        final state = syntheticState(p.user);
        await c.execute(
          r'INSERT INTO workspace(workspace_id,owner_id,epoch,state,revisions) VALUES ($1,$2,$3,$4,$5::jsonb)',
          parameters: [
            p.workspace,
            p.user,
            'epoch-$suffix',
            jsonEncode(state.toJson()),
            jsonEncode({for (final t in state.transactions) t.id: '0'}),
          ],
        );
      }
    } finally {
      await c.close();
    }
  }

  Future<ServerProcess> server({bool faults = true}) async {
    final fault = File('${directory.path}/fault-${servers.length}.json');
    final p = await Process.start(
      File(
        faults ? 'build/fault_server.exe' : 'build/server.exe',
      ).absolute.path,
      [configFile.absolute.path, if (faults) fault.absolute.path],
    );
    final errors = StringBuffer();
    p.stderr.transform(utf8.decoder).listen(errors.write);
    final first = await p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 10));
    final address = object(jsonDecode(first));
    if (address['listening'] != '127.0.0.1')
      throw StateError('Non-loopback server');
    final port = address['port'] as int;
    final s = ServerProcess(
      p,
      Uri.parse('http://127.0.0.1:$port'),
      fault,
      errors,
    );
    servers.add(s);
    return s;
  }

  SyntheticClient client(ServerProcess server, int index) => SyntheticClient(
    server.base,
    config.principals[index],
    File('${directory.path}/client-$index.json'),
  );
  Future<ProcessResult> worker(
    ServerProcess server,
    int index,
    List<String> action,
  ) => Process.run(File('build/client_worker.exe').absolute.path, [
    configFile.absolute.path,
    '$index',
    '${server.base}',
    File('${directory.path}/client-$index.json').absolute.path,
    ...action,
  ]);
  Future<void> work(
    ServerProcess server,
    int index,
    List<String> action,
  ) async {
    final result = await worker(server, index, action);
    if (result.exitCode != 0)
      throw StateError('Client failed: ${result.exitCode} ${result.stderr}');
  }

  Future<Map<String, dynamic>> inspect({int index = 0}) async {
    final c = await admin.connect(admin: true);
    try {
      final w = config.principals[index].workspace;
      final result = (await c.execute(
        r'SELECT head,state,revisions FROM workspace WHERE workspace_id=$1',
        parameters: [w],
      )).single.toColumnMap();
      result['state'] = jsonDecode(result['state'] as String);
      result['receipts'] = (await c.execute(
        r'SELECT count(*) FROM command_receipt WHERE workspace_id=$1',
        parameters: [w],
      )).single.single;
      result['bundles'] = (await c.execute(
        r'SELECT count(*) FROM change_bundle WHERE workspace_id=$1',
        parameters: [w],
      )).single.single;
      return result;
    } finally {
      await c.close();
    }
  }

  Future<void> waitForBlockedWriter() async {
    final c = await admin.connect(admin: true);
    try {
      for (var i = 0; i < 100; i++) {
        final rows = await c.execute(
          "SELECT count(*) FROM pg_stat_activity WHERE usename='qesto_sync' AND wait_event_type='Lock'",
        );
        if ((rows.single.single as int) > 0) return;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      throw StateError('No real PostgreSQL lock wait observed');
    } finally {
      await c.close();
    }
  }

  Future<void> close() async {
    for (final s in servers) await s.close();
  }
}
