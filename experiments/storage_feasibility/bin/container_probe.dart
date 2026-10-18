import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/container/synthetic_scenario.dart';
import 'package:qesto_storage_spike/native_faults.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/wal_policy.dart';

Future<void> main(List<String> args) async {
  final mode = args[0];
  if (mode == 'bench') {
    await benchmark(int.parse(args[1]));
    return;
  }
  final directory = args[1], stage = args.length > 2 ? args[2] : '';
  if (mode == 'lock') {
    try {
      final c = await SqliteContainer.open(directory, syntheticPartition);
      await c.close();
      exitCode = 2;
    } on ContractViolation catch (e) {
      if (e.code != 'profile-already-owned') rethrow;
      print('{"excluded":true}');
    }
    return;
  }
  NativeFaults? native;
  if (mode == 'native')
    native = NativeFaults('build/hardening/qesto_fault_shim.dll');
  void fault(String point) {
    if (mode == 'native' && point == 'local-before-commit') {
      native!.arm(
        scope: stage.startsWith('checkpoint') ? 1 : 2,
        op: stage == 'fsync' ? 2 : 1,
        code: stage == 'full'
            ? 13
            : stage == 'fsync'
            ? 1034
            : 778,
        mode: stage == 'partial'
            ? 1
            : stage == 'checkpoint-kill'
            ? 2
            : 0,
      );
    } else if (point == stage) {
      exit(86);
    }
  }

  if (mode == 'migration') {
    final source = FinancialSnapshot(
      File('test/fixtures/container_profile_v7.json').readAsStringSync().trim(),
    );
    final c = await SqliteContainer.migrate(
      directory,
      MigrationManifest('migration-one', syntheticPartition, source.hash),
      source,
      fault: fault,
    );
    await c.close();
    return;
  }
  var store = await SqliteContainer.open(
    directory,
    syntheticPartition,
    fault: fault,
  );
  final source = (await store.readSnapshot()).value;
  if (mode == 'local' || mode == 'native') {
    if (native != null) native.attach(store.raw);
    Object? error;
    var acknowledged = false;
    try {
      await store.commitMutation(syntheticMutation(source));
      acknowledged = true;
    } catch (e) {
      error = e;
    }
    final faultHits = native?.metric(0);
    final reopenRequired = store.requiresReopen;
    native?.disarm();
    if (mode == 'local' && stage == 'local-after-commit') exit(86);
    await store.close();
    if (mode == 'native') {
      store = await SqliteContainer.open(directory, syntheticPartition);
      store.verify();
      final r = (await store.readSnapshot()).revision;
      final checkpointFailure = stage == 'checkpoint';
      final expectedCode = stage == 'full'
          ? 13
          : stage == 'fsync'
          ? 1034
          : 778;
      final actualCode = error is sql.SqliteException
          ? error.extendedResultCode
          : null;
      if ((checkpointFailure
              ? error != null || !acknowledged || !reopenRequired
              : error == null || acknowledged) ||
          faultHits != 1 ||
          r != (checkpointFailure ? 1 : 0) ||
          (await store.readPendingCommands()).length != r) {
        throw StateError(
          'native fault invariant failed: error=${error.runtimeType} ack=$acknowledged hits=$faultHits revision=$r',
        );
      }
      if (!checkpointFailure && actualCode != expectedCode) {
        throw StateError(
          'Unexpected native error code: $actualCode instead of $expectedCode',
        );
      }
      // SAME command after recovery, not a freshly generated command ID.
      await store.commitMutation(syntheticMutation(source));
      store.verify();
      print(
        jsonEncode({
          'fault': stage,
          'nativeIo': true,
          'error': '${error.runtimeType}',
          'sqliteExtendedCode': actualCode,
          'acknowledgedBeforeRecovery': acknowledged,
          'reopenRequired': reopenRequired,
          'recoveredRevision': r,
          'retriedRevision': (await store.readSnapshot()).revision,
        }),
      );
      await store.close();
    }
    return;
  }
  if (mode == 'remote') {
    await store.applyRemoteBundle(
      RemoteBundle(
        id: 'page-crash',
        partition: syntheticPartition,
        fromCursor: 0,
        toCursor: 5,
        expectedRevision: (await store.readSnapshot()).revision,
        shadow: editSyntheticNote(source, 'remote'),
      ),
    );
    if (stage == 'remote-after-commit') exit(86);
  } else if (mode == 'ack') {
    final r = (await store.lookupCommandReceipt('command-1'))!;
    await store.markCommandAcknowledged(
      SyntheticReceipt(
        'ack-crash',
        r.id,
        syntheticPartition,
        r.contentDigest,
        DeliveryState.accepted,
        '{}',
      ),
    );
    if (stage == 'ack-after-commit') exit(86);
  } else if (mode == 'rotation') {
    await store.rotateKey();
  } else {
    throw ArgumentError(mode);
  }
  await store.close();
}

Future<void> benchmark(int count) async {
  final metrics = NativeFaults(
    'build/hardening/qesto_fault_shim.dll',
    install: false,
  );
  final directory = createSpikeDirectory(), samples = <Map<String, Object?>>[];
  final cpu0 = metrics.cpuMs, whole = Stopwatch()..start();
  final source = syntheticV7(count);
  final serialize = whole.elapsedMicroseconds / 1000;
  var store = await SqliteContainer.migrate(
    directory.path,
    MigrationManifest('benchmark', syntheticPartition, source.hash),
    source,
  );
  samples.add({
    'kind': 'migration',
    'serializeMs': serialize,
    'totalMs': whole.elapsedMicroseconds / 1000,
    'cpuMs': metrics.cpuMs - cpu0,
    'rssBytes': ProcessInfo.currentRss,
    'peakRssBytes': ProcessInfo.maxRss,
  });
  var current = source;
  for (var i = 0; i < 3; i++) {
    final cpu = metrics.cpuMs, timer = Stopwatch()..start();
    final mutation = syntheticMutation(
      current,
      id: 'edit-$i',
      expected: i,
      note: 'small note $i',
    );
    final serialized = timer.elapsedMicroseconds / 1000;
    await store.commitMutation(mutation);
    current = mutation.snapshot;
    samples.add({
      'kind': 'edit',
      'serializeMs': serialized,
      'totalMs': timer.elapsedMicroseconds / 1000,
      'cpuMs': metrics.cpuMs - cpu,
      'rssBytes': ProcessInfo.currentRss,
      'peakRssBytes': ProcessInfo.maxRss,
      'files': sizes(store.path),
    });
  }
  store.verify();
  final path = store.path;
  await store.close();
  store = await SqliteContainer.open(directory.path, syntheticPartition);
  if ((await store.readSnapshot()).value.hash != current.hash ||
      (await store.readPendingCommands()).length != 3)
    throw StateError('benchmark verification');
  await store.close();
  print(
    jsonEncode({
      'count': count,
      'samples': samples,
      'afterClose': sizes(path),
      'passed': true,
    }),
  );
}
