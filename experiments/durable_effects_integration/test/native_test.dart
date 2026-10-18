import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import '../lib/prepared_commit.dart';
import '../lib/storage_request.dart';

void main() {
  final evidence = <Object>[];
  for (final fault in [
    'full',
    'write',
    'fsync',
    'partial',
    'checkpoint',
    'checkpoint-kill',
  ]) {
    test(
      'native encrypted effects $fault: no false receipt; same-ID recovery',
      () async {
        final directory = createSpikeDirectory(),
            source = encodeSynthetic(count: 60);
        File(
          '${directory.path}/source.json',
        ).writeAsStringSync(source, flush: true);
        final snapshot = FinancialSnapshot(source);
        const partition = Partition('synthetic-4f', '4f-lineage');
        final store = await SqliteContainer.migrate(
          directory.path,
          MigrationManifest('native-4f', partition, snapshot.hash),
          snapshot,
          incremental: true,
        );
        await store.close();
        final result = await Process.run(
          File(
            'build/native_effects_probe/bundle/bin/native_effects_probe.exe',
          ).absolute.path,
          [directory.path, fault],
        );
        expect(
          result.exitCode,
          fault == 'checkpoint-kill' ? 86 : 0,
          reason: '${result.stdout} ${result.stderr}',
        );
        if (fault != 'checkpoint-kill')
          evidence.add(jsonDecode(result.stdout as String));
        final again = await SqliteContainer.open(directory.path, partition);
        try {
          again.verify();
          expect((await again.readSnapshot()).revision, 1);
          expect(await again.readPendingCommands(), hasLength(1));
          final p =
              NotePreparationScope.admit(
                source,
                workspace: partition.workspace,
                lineage: partition.lineage,
                revision: 0,
                generation: 0,
              ).prepare(
                commandId: 'native-effects',
                target: 'container-tx-0',
                note: 'native durability',
                time: DateTime.utc(2026, 10, 17),
              );
          final request = storageRequest(p, again.generation),
              receipt = await again.resolveEffects(
                storageRequest(p, again.generation),
              );
          await again.verifyEffectsReceipt(receipt, request);
          expect((await again.readSnapshot()).value.json, p.snapshot.json);
        } finally {
          await again.close();
        }
      },
    );
  }
  tearDownAll(
    () => File(
      'results/native-effects.json',
    ).writeAsStringSync(jsonEncode(evidence)),
  );
}
