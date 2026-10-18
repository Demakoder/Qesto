import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/container/synthetic_scenario.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/wal_policy.dart';

void main() {
  final evidence = <Object>[];
  Future<Directory> create() async {
    final dir = createSpikeDirectory(),
        source = FinancialSnapshot(
          File(
            '../storage_feasibility/test/fixtures/container_profile_v7.json',
          ).readAsStringSync().trim(),
        );
    final store = await SqliteContainer.migrate(
      dir.path,
      MigrationManifest('chunk-native', syntheticPartition, source.hash),
      source,
      incremental: true,
    );
    await store.close();
    return dir;
  }

  for (final fault in [
    'full',
    'write',
    'fsync',
    'partial',
    'checkpoint',
    'checkpoint-kill',
  ]) {
    test('format2 native VFS $fault and same-ID recovery', () async {
      final dir = await create();
      final r = await Process.run(
        File(
          '../storage_feasibility/build/container_probe/bundle/bin/container_probe.exe',
        ).absolute.path,
        ['native', dir.path, fault],
        workingDirectory: '../storage_feasibility',
      );
      expect(
        r.exitCode,
        fault == 'checkpoint-kill' ? 86 : 0,
        reason: '${r.stderr} ${r.stdout}',
      );
      if (fault != 'checkpoint-kill')
        evidence.add(jsonDecode(r.stdout as String));
      final store = await SqliteContainer.open(dir.path, syntheticPartition);
      try {
        store.verify();
        expect((await store.readSnapshot()).revision, 1);
        expect(await store.readPendingCommands(), hasLength(1));
      } finally {
        await store.close();
      }
      File(
        'results/native-chunk-faults.json',
      ).writeAsStringSync(jsonEncode({'format': 2, 'evidence': evidence}));
    });
  }
  test(
    'format2 pinned reader retains old profile and WAL backpressure, no WAL deletion',
    () async {
      final dir = await create();
      var store = await SqliteContainer.open(
        dir.path,
        syntheticPartition,
        softBytes: 128 * 1024,
        hardBytes: 3 * mib,
      );
      final before = (await store.readSnapshot()).value,
          reader = await store.leaseReader(
            duration: const Duration(seconds: 10),
          );
      var revision = 0, peak = 0;
      var blocked = false;
      try {
        for (var i = 0; i < 80; i++) {
          try {
            await store.commitMutation(
              syntheticMutation(
                before,
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
          final current = fileBytes('${store.path}-wal');
          if (current > peak) peak = current;
        }
        expect(blocked, isTrue);
        expect(peak, lessThan(3 * mib));
        expect(revision, greaterThan(0));
        expect(reader.read().value.json, before.json);
        reader.close();
        await store.maintain();
        await store.commitMutation(
          syntheticMutation(before, id: 'released', expected: revision),
        );
        store.verify();
        File('results/chunk-wal-pressure.json').writeAsStringSync(
          jsonEncode({
            'peak_wal': peak,
            'commits': revision,
            'bounded': true,
            'after_release': sizes(store.path),
          }),
        );
      } finally {
        reader.close();
        await store.close();
      }
    },
  );
}
