import 'dart:convert';
import 'dart:io';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_synthetic_sync/config.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto_encrypted_sync_experiment/coordinator.dart';
import 'package:qesto_encrypted_sync_experiment/transport.dart';
import '../../synthetic_sync_backend/test/harness.dart' show ServerProcess;

const dart =
    r'C:\Users\ARM\development\flutter\bin\cache\dart-sdk\bin\dart.exe';
const backend = '../synthetic_sync_backend';

FinancialSnapshot fixture({int count = 3}) {
  final root = w.object(
    jsonDecode(
      File(
        '../storage_feasibility/test/fixtures/container_profile_v7.json',
      ).readAsStringSync(),
    ),
  );
  final prior = SynoballState.fromJson(w.object(root['synoball']));
  final state = SynoballCore(
    initialState: SynoballState(
      rawPayloads: [
        RawPayload(
          id: 'synthetic-provenance',
          contentType: 'text/plain',
          body: 'Synthetic source retained locally',
          createdAt: DateTime.utc(2026, 10, 11),
        ),
      ],
      transactions: [
        for (var i = 0; i < count; i++)
          CanonicalTransaction.fromJson({
            ...prior.transactions[i % 3].toJson(),
            'id': 'container-tx-$i',
            'entityId': 'demo-user',
            'status': i == 2 ? 'deleted' : 'posted',
          }),
      ],
    ),
  ).state;
  root['synoball'] = state.toJson();
  // Exercise the dual persisted projection as well as canonical transactions.
  final legacy = w.object((root['transactions'] as List).first);
  root['transactions'] = [
    ...root['transactions'],
    {
      ...legacy,
      'id': 'container-tx-0',
      'comment': state.transactions.first.userNote,
    },
  ];
  return FinancialSnapshot(jsonEncode(root));
}

class Harness {
  late TestConfig config, admin;
  late Directory runtime;
  late File configFile, fixtureFile;
  late FinancialSnapshot initial;
  final clients = <Directory>[];
  final clientConfigs = <File>[];
  final servers = <ServerProcess>[];
  String get epoch => config.json['test_epoch'] as String;
  Partition get partition =>
      Partition(config.principals.first.workspace, epoch);
  Future<void> start({int count = 3}) async {
    initial = fixture(count: count);
    admin = TestConfig.read('$backend/.runtime/cluster.json');
    runtime = Directory('.runtime/run-${DateTime.now().microsecondsSinceEpoch}')
      ..createSync(recursive: true);
    final map = w.object(jsonDecode(jsonEncode(admin.json)))
      ..remove('admin_password')
      ..remove('data');
    final suffix = DateTime.now().microsecondsSinceEpoch;
    for (final p in map['principals'] as List) {
      p['workspace'] = 'enc3b-$suffix';
      p['user'] = 'demo-user';
    }
    map['test_epoch'] = 'epoch-$suffix';
    config = TestConfig(map);
    configFile = File('${runtime.path}/config.json')
      ..writeAsStringSync(jsonEncode(map), flush: true);
    for (var index = 0; index < 2; index++) {
      final p = config.principals[index];
      clientConfigs.add(
        File('${runtime.path}/client-$index.json')..writeAsStringSync(
          jsonEncode({
            'marker': 'qesto.encrypted-sync-client.v1',
            'index': index,
            'token': p.token,
            'user': p.user,
            'device': p.device,
            'workspace': p.workspace,
            'epoch': epoch,
          }),
          flush: true,
        ),
      );
    }
    fixtureFile = File('${runtime.path}/synthetic-fixture.json')
      ..writeAsStringSync(initial.json);
    final db = await admin.connect(admin: true);
    try {
      final state = SynoballState.fromJson(
        w.object(jsonDecode(initial.json)['synoball']),
      );
      await db.execute(
        r'INSERT INTO workspace(workspace_id,owner_id,epoch,state,revisions) VALUES ($1,$2,$3,$4,$5::jsonb)',
        parameters: [
          config.principals.first.workspace,
          'demo-user',
          epoch,
          jsonEncode(state.toJson()),
          jsonEncode({for (final t in state.transactions) t.id: '0'}),
        ],
      );
    } finally {
      await db.close();
    }
    clients.addAll([createSpikeDirectory(), createSpikeDirectory()]);
  }

  Future<ServerProcess> server() async {
    final control = File('${runtime.path}/fault-${servers.length}.json');
    final process = await Process.start(
      File('$backend/build/fault_server.exe').absolute.path,
      [configFile.absolute.path, control.absolute.path],
    );
    final errors = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(errors.write);
    final address = w.object(
      jsonDecode(
        await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 10)),
      ),
    );
    if (address['listening'] != '127.0.0.1') throw StateError('Not loopback');
    final result = ServerProcess(
      process,
      Uri.parse('http://127.0.0.1:${address['port']}'),
      control,
      errors,
    );
    servers.add(result);
    return result;
  }

  String get exe => File('build/client/bundle/bin/client.exe').absolute.path;
  Future<ProcessResult> run(
    ServerProcess server,
    int index,
    String action, [
    List<String> tail = const [],
    String? fault,
  ]) => Process.run(
    exe,
    [
      clientConfigs[index].absolute.path,
      '$index',
      server.base.toString(),
      clients[index].path,
      action,
      ...tail,
    ],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
    environment: {if (fault != null) 'QESTO_3B_FAULT': fault},
  );
  Future<Map<String, dynamic>> ok(
    ServerProcess s,
    int i,
    String action, [
    List<String> args = const [],
  ]) async {
    final r = await run(s, i, action, args);
    if (r.exitCode != 0)
      throw StateError('CLI $action failed: ${r.stdout} ${r.stderr}');
    return w.object(jsonDecode((r.stdout as String).trim()));
  }

  Future<void> bootstrapBoth(ServerProcess s) async {
    for (var i = 0; i < 2; i++) {
      await ok(s, i, 'bootstrap', [fixtureFile.absolute.path]);
    }
  }

  Future<SqliteContainer> open(int i, {void Function(String)? fault}) =>
      SqliteContainer.open(clients[i].path, partition, fault: fault);
  Coordinator coordinator(SqliteContainer store, ServerProcess s, int i) =>
      Coordinator(
        store,
        partition,
        config.principals[i],
        LoopbackTransport(s.base, config.principals[i]).request,
      );
  Future<Map<String, dynamic>> serverState() async {
    final db = await admin.connect(admin: true);
    try {
      final rows = await db.execute(
        r'SELECT head,state FROM workspace WHERE workspace_id=$1',
        parameters: [partition.workspace],
      );
      return {
        'head': rows.single[0],
        'state': jsonDecode(rows.single[1] as String),
      };
    } finally {
      await db.close();
    }
  }

  Future<void> close() async {
    for (final s in servers) {
      await s.close();
    }
  }
}
