import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/container/synthetic_scenario.dart';
import 'package:qesto_storage_spike/storage_spike.dart';

void main() {
  final evidence = <Object>[];
  for (final stage in [
    'chunk-after-row',
    'local-after-snapshot',
    'local-before-commit',
  ]) {
    test(
      'bounded resource pressure + simulated OOM at $stage rolls back state/outbox',
      () async {
        final directory = createSpikeDirectory(), before = syntheticV7(10);
        var armed = false;
        final retained = <Uint8List>[];
        final store = await SqliteContainer.migrate(
          directory.path,
          MigrationManifest('pressure', syntheticPartition, before.hash),
          before,
          incremental: true,
          fault: (at) {
            if (!armed || at != stage) return;
            for (var i = 0; i < 64; i++) {
              retained.add(
                Uint8List(1024 * 1024)..fillRange(0, 1024 * 1024, 7),
              );
            }
            throw OutOfMemoryError(); // explicit fault simulation, not VM/OS OOM
          },
        );
        armed = true;
        await expectLater(
          store.commitMutation(syntheticMutation(before)),
          throwsA(isA<OutOfMemoryError>()),
        );
        expect(retained.length, 64);
        retained.clear();
        await store.close();
        final again = await SqliteContainer.open(
          directory.path,
          syntheticPartition,
        );
        try {
          again.verify();
          final snapshot = await again.readSnapshot();
          expect(snapshot.revision, 0);
          expect(snapshot.value.json, before.json);
          expect(await again.readPendingCommands(), isEmpty);
        } finally {
          await again.close();
        }
        evidence.add({
          'stage': stage,
          'allocated_touched_bytes': 64 * 1024 * 1024,
          'fault': 'explicit OutOfMemoryError simulation',
          'actual_vm_oom': false,
          'state_and_outbox_rolled_back': true,
          'reopen_verified': true,
        });
      },
    );
  }
  tearDownAll(
    () => File(
      'results/resource-pressure.json',
    ).writeAsStringSync(jsonEncode(evidence)),
  );
}
