import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:qesto_synthetic_sync/testing/server_process.dart';
import 'package:qesto_synthetic_sync/config.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto_windows_boundary_experiment/windows_note_boundary.dart';
import 'package:qesto_windows_boundary_experiment/note_sync_binding.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_note_driver.dart';
import 'package:qesto_encrypted_sync_experiment/transport.dart';
import 'qesto_coordinator_domain.dart';
import 'qesto_note_executor.dart';

const dart =
    r'C:\Users\ARM\development\flutter\bin\cache\dart-sdk\bin\dart.exe';

class _SnapshotFetch {
  const _SnapshotFetch(this.endpoint, this.principal);
  final Uri endpoint;
  final w.Principal principal;
  Future<Map<String, dynamic>> call() =>
      LoopbackTransport(endpoint, principal).request('GET', 'snapshot');
}

class UiSyncHarness {
  UiSyncHarness({
    this.root = '.',
    this.evidence = 'results',
    this.incremental = false,
    this.serverExecutable,
    this.probeExecutable,
    this.effectsDriver,
  });
  final String root, evidence;
  final bool incremental;
  final String? serverExecutable, probeExecutable;
  final SyntheticNoteDriverFactory? effectsDriver;
  late TestConfig admin, config;
  late File configFile;
  late Directory run;
  late String initial, epoch, policyDigest;
  final profiles = <SyntheticWindowsProfile>[];
  final servers = <ServerProcess>[];
  int port = 0;
  Future<void> start({int count = 3}) async {
    // Hard gate: runner must have proved both actual-controller and executor parity.
    for (final file in [
      'semantic-parity.json',
      'controller-semantic-gate.json',
    ]) {
      if (w.object(
            jsonDecode(File('$evidence/$file').readAsStringSync()),
          )['passed'] !=
          true) {
        throw StateError('STOP GATE: semantic parity not proven');
      }
    }
    initial = encodeSynthetic(
      count: count,
      fixturePath:
          '$root/../storage_feasibility/test/fixtures/container_profile_v7.json',
    );
    policyDigest = const QestoNoteExecutor().policyDigest(
      initial,
      syntheticUser,
    );
    admin = TestConfig.read(
      '$root/../synthetic_sync_backend/.runtime/cluster.json',
    );
    final suffix = DateTime.now().microsecondsSinceEpoch;
    epoch = 'synthetic-4a-epoch-$suffix';
    run = Directory('$root/.runtime/run-$suffix')..createSync(recursive: true);
    final map = w.object(jsonDecode(jsonEncode(admin.json)))
      ..remove('admin_password')
      ..remove('data');
    map['principals'] = (map['principals'] as List).take(2).toList();
    for (var i = 0; i < 2; i++) {
      final created = SyntheticWindowsProfile.create();
      final p = SyntheticWindowsProfile(
        created.directory,
        'synthetic-4a-workspace-$suffix',
        'synthetic-4a-device-$i-$suffix',
        epoch,
      );
      File(
        '${p.directory}/.qesto-windows-boundary',
      ).writeAsStringSync(p.marker, flush: true);
      profiles.add(p);
      map['principals'][i]['user'] = syntheticUser;
      map['principals'][i]['workspace'] = p.workspace;
      map['principals'][i]['device'] = p.device;
    }
    config = TestConfig(map);
    configFile = File('${run.path}/server-config.json')
      ..writeAsStringSync(jsonEncode(map), flush: true);
    for (var i = 0; i < 2; i++) {
      final p = config.principals[i];
      File('${profiles[i].directory}/client-config.json').writeAsStringSync(
        jsonEncode({
          'marker': 'qesto.encrypted-sync-client.v1',
          'index': i,
          'token': p.token,
          'user': p.user,
          'device': p.device,
          'workspace': p.workspace,
          'epoch': epoch,
        }),
        flush: true,
      );
      File('${profiles[i].directory}/sync-binding.json').writeAsStringSync(
        jsonEncode({
          'policy_digest': policyDigest,
          'devices': profiles.map((p) => p.device).toList(),
        }),
        flush: true,
      );
    }
    final db = await admin.connect(admin: true);
    try {
      final state = const QestoNoteExecutor().read(initial, syntheticUser);
      await db.execute(
        r'INSERT INTO workspace(workspace_id,owner_id,epoch,state,revisions) VALUES ($1,$2,$3,$4,$5::jsonb)',
        parameters: [
          profiles.first.workspace,
          syntheticUser,
          epoch,
          initial,
          jsonEncode({for (final t in state.transactions) t.id: '0'}),
        ],
      );
    } finally {
      await db.close();
    }
  }

  Future<ServerProcess> server() async {
    final control = File('${run.path}/fault-${servers.length}.json');
    final process = await Process.start(
      File(
        serverExecutable ?? '$root/build/server/bundle/bin/server.exe',
      ).absolute.path,
      [configFile.absolute.path, control.absolute.path, '$port'],
    );
    final errors = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(errors.write);
    final ready = w.object(
      jsonDecode(
        await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 10)),
      ),
    );
    if (ready['listening'] != '127.0.0.1')
      throw StateError('Loopback required');
    port = ready['port'] as int;
    final s = ServerProcess(
      process,
      Uri.parse('http://127.0.0.1:$port'),
      control,
      errors,
    );
    servers.add(s);
    return s;
  }

  QestoCoordinatorDomain domain(int i) => QestoCoordinatorDomain(
    syntheticUser,
    profiles[i].workspace,
    epoch,
    policyDigest,
    profiles.map((p) => p.device).toList(),
  );
  Future<WindowsNoteBoundary> open(
    ServerProcess server,
    int i, {
    bool create = false,
    BoundaryProbe probe = BoundaryProbe.none,
  }) async {
    final principal = config.principals[i];
    final response = create
        ? await Isolate.run(_SnapshotFetch(server.base, principal).call)
        : null;
    return WindowsNoteBoundary.open(
      profiles[i],
      initialSnapshot: create ? initial : null,
      probe: probe,
      incremental: incremental,
      effectsDriver: effectsDriver,
      synchronization: NoteSyncBinding(
        principal: principal,
        endpoint: server.base,
        domain: domain(i),
        bootstrapResponse: response,
      ),
    );
  }

  Future<Map<String, dynamic>> serverState() async {
    final db = await admin.connect(admin: true);
    try {
      final rows = await db.execute(
        r'SELECT head,state,revisions FROM workspace WHERE workspace_id=$1',
        parameters: [profiles.first.workspace],
      );
      return {
        'head': rows.single[0],
        'state': jsonDecode(rows.single[1] as String),
        'revisions': rows.single[2],
      };
    } finally {
      await db.close();
    }
  }

  Future<ProcessResult> child(
    ServerProcess server,
    int i,
    String action, {
    String? fault,
  }) => Process.run(
    File(
      probeExecutable ?? '$root/build/client_probe/bundle/bin/client_probe.exe',
    ).absolute.path,
    [
      File('${profiles[i].directory}/client-config.json').absolute.path,
      profiles[i].directory,
      server.base.toString(),
      action,
    ],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
    environment: {if (fault != null) 'QESTO_4A_PROCESS_FAULT': fault},
  );
  Future<void> close() async {
    for (final s in servers) {
      await s.close();
    }
  }
}
