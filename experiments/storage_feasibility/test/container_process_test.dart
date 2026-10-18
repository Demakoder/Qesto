import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/container/synthetic_scenario.dart';
import 'package:qesto_storage_spike/container/writer.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/wal_policy.dart';

final exe = File(
  'build/container_probe/bundle/bin/container_probe.exe',
).absolute.path;
Future<ProcessResult> child(
  String mode,
  String directory, [
  String stage = '',
]) => Process.run(exe, [mode, directory, stage]);
void main() {
  final nativeEvidence = <Map>[];
  late Directory dir;
  late FinancialSnapshot source;
  setUp(() async {
    dir = createSpikeDirectory();
    source = FinancialSnapshot(
      File('test/fixtures/container_profile_v7.json').readAsStringSync().trim(),
    );
    final c = await SqliteContainer.migrate(
      dir.path,
      MigrationManifest('migration-one', syntheticPartition, source.hash),
      source,
    );
    await c.close();
  });
  for (final stage in [
    'local-after-snapshot',
    'local-before-commit',
    'local-after-commit',
  ]) {
    test('process exit $stage has atomic snapshot/command', () async {
      final r = await child('local', dir.path, stage);
      expect(r.exitCode, 86, reason: '${r.stderr}');
      final c = await SqliteContainer.open(dir.path, syntheticPartition);
      try {
        c.verify();
        final expected = stage == 'local-after-commit' ? 1 : 0;
        expect((await c.readSnapshot()).revision, expected);
        expect(await c.readPendingCommands(), hasLength(expected));
        await c.commitMutation(syntheticMutation(source));
        expect((await c.readSnapshot()).revision, 1);
      } finally {
        await c.close();
      }
    });
  }
  for (final stage in [
    'remote-before-checkpoint',
    'remote-before-commit',
    'remote-after-commit',
  ]) {
    test(
      'process exit $stage keeps cursor and pending projection atomic',
      () async {
        var c = await SqliteContainer.open(dir.path, syntheticPartition);
        final m = syntheticMutation(source);
        await c.commitMutation(m);
        await c.close();
        final r = await child('remote', dir.path, stage);
        expect(r.exitCode, 86, reason: '${r.stderr}');
        c = await SqliteContainer.open(dir.path, syntheticPartition);
        try {
          c.verify();
          expect(
            await c.readCheckpoint(),
            stage == 'remote-after-commit' ? 5 : 0,
          );
          expect((await c.readSnapshot()).value.json, m.snapshot.json);
          expect(await c.readPendingCommands(), hasLength(1));
        } finally {
          await c.close();
        }
      },
    );
  }
  for (final stage in ['ack-after-receipt', 'ack-after-commit']) {
    test('lost response $stage cannot discard unresolved command', () async {
      var c = await SqliteContainer.open(dir.path, syntheticPartition);
      await c.commitMutation(syntheticMutation(source));
      await c.close();
      expect((await child('ack', dir.path, stage)).exitCode, 86);
      c = await SqliteContainer.open(dir.path, syntheticPartition);
      try {
        expect(
          (await c.lookupCommandReceipt('command-1'))!.state,
          stage == 'ack-after-commit'
              ? DeliveryState.accepted
              : DeliveryState.queued,
        );
        expect(await c.readPendingCommands(), hasLength(1));
        c.verify();
      } finally {
        await c.close();
      }
    });
  }
  for (final stage in [
    'migration-after-snapshot',
    'migration-before-commit',
    'migration-after-commit',
  ]) {
    test('process killed in $stage resumes exact codec source', () async {
      final fresh = createSpikeDirectory();
      expect((await child('migration', fresh.path, stage)).exitCode, 86);
      final c = await SqliteContainer.migrate(
        fresh.path,
        MigrationManifest('migration-one', syntheticPartition, source.hash),
        source,
      );
      try {
        expect((await c.readSnapshot()).value.json, source.json);
        expect(await c.readPendingCommands(), isEmpty);
        c.verify();
      } finally {
        await c.close();
      }
    });
  }
  for (final stage in [
    'rotation-after-keys',
    'rotation-during-copy',
    'rotation-after-copy',
    'rotation-after-promotion',
  ]) {
    test(
      'process killed in $stage opens verified generation with outbox',
      () async {
        var c = await SqliteContainer.open(dir.path, syntheticPartition);
        await c.commitMutation(syntheticMutation(source));
        await c.close();
        final result = await child('rotation', dir.path, stage);
        expect(result.exitCode, 86, reason: '${result.stderr}');
        c = await SqliteContainer.open(dir.path, syntheticPartition);
        try {
          c.verify();
          expect(c.generation, stage == 'rotation-after-promotion' ? 2 : 1);
          expect((await c.readSnapshot()).revision, 1);
          expect(await c.readPendingCommands(), hasLength(1));
        } finally {
          await c.close();
        }
      },
    );
  }
  for (final fault in ['full', 'write', 'fsync', 'partial', 'checkpoint']) {
    test(
      'real native VFS injected $fault error never ACKs orphan snapshot',
      () async {
        final r = await child('native', dir.path, fault);
        expect(r.exitCode, 0, reason: '${r.stderr}\n${r.stdout}');
        final result = jsonDecode((r.stdout as String).trim()) as Map;
        nativeEvidence.add(result);
        File(
          'results/container_native_faults.json',
        ).writeAsStringSync(jsonEncode(nativeEvidence));
        expect(result['nativeIo'], isTrue);
        expect(result['recoveredRevision'], fault == 'checkpoint' ? 1 : 0);
        expect(result['retriedRevision'], 1);
      },
    );
  }
  test(
    'native process interruption during checkpoint preserves committed command',
    () async {
      expect((await child('native', dir.path, 'checkpoint-kill')).exitCode, 86);
      final c = await SqliteContainer.open(dir.path, syntheticPartition);
      try {
        c.verify();
        expect((await c.readSnapshot()).revision, 1);
        expect(await c.readPendingCommands(), hasLength(1));
      } finally {
        await c.close();
      }
    },
  );
  test('second writer process is excluded while profile is owned', () async {
    final c = await SqliteContainer.open(dir.path, syntheticPartition);
    try {
      final r = await child('lock', dir.path);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(jsonDecode(r.stdout as String)['excluded'], isTrue);
    } finally {
      await c.close();
    }
  });
  test('worker isolate exit is supervised; reopening remains valid', () async {
    final owner = await ContainerWriter.open(dir.path, syntheticPartition);
    await owner.commitMutation(syntheticMutation(source));
    owner.simulateWorkerCrash();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await expectLater(owner.readSnapshot(), throwsA(isA<ContractViolation>()));
    await owner.close();
    var reopened = false;
    try {
      final c = await SqliteContainer.open(dir.path, syntheticPartition);
      try {
        c.verify();
        expect((await c.readSnapshot()).revision, 1);
        reopened = true;
      } finally {
        await c.close();
      }
    } on ContractViolation catch (e) {
      expect(e.code, 'profile-already-owned');
    }
    File('results/container_owner_restart.json').writeAsStringSync(
      jsonEncode({
        'supervisorReportedFailure': true,
        'inProcessReopen': reopened,
        'requiresProcessRestart': !reopened,
      }),
    );
  });
  test(
    'long small-edit sequence bounds WAL and preserves pending tail with pinned readers',
    () async {
      var c = await SqliteContainer.open(
        dir.path,
        syntheticPartition,
        softBytes: 128 * 1024,
        hardBytes: 3 * mib,
      );
      final a = await c.leaseReader(duration: const Duration(seconds: 10));
      final b = await c.leaseReader(duration: const Duration(seconds: 10));
      var revision = 0, peak = 0;
      var blocked = false;
      try {
        for (var i = 0; i < 80; i++) {
          try {
            await c.commitMutation(
              syntheticMutation(
                source,
                id: 'small-$i',
                expected: revision,
                note: 'change-$i',
              ),
            );
            revision++;
          } on StoragePressure {
            blocked = true;
            break;
          }
          final wal = fileBytes('${c.path}-wal');
          if (wal > peak) peak = wal;
        }
        expect(blocked, isTrue);
        expect(peak, lessThan(3 * mib));
        expect(revision, greaterThan(0));
        expect(await c.readPendingCommands(), hasLength(revision));
        a.close();
        b.close();
        expect((await c.maintain()).busy, 0);
        await c.commitMutation(
          syntheticMutation(source, id: 'after-reader', expected: revision),
        );
        c.verify();
        File('results/container_wal.json').writeAsStringSync(
          jsonEncode({
            'passed': true,
            'commitsBeforePressure': revision,
            'peakWalBytes': peak,
            'hardBudget': 3 * mib,
            'afterRelease': sizes(c.path),
          }),
        );
      } finally {
        a.close();
        b.close();
        await c.close();
      }
    },
  );
}
