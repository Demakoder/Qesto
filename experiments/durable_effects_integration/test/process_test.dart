import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import '../lib/prepared_commit.dart';
import '../lib/storage_request.dart';

void main() {
  final evidence = <Map<String, Object?>>[];
  for (final stage in [
    'before-prepare',
    'after-prepare',
    'chunk-after-row',
    'local-after-snapshot',
    'local-before-commit',
    'effects-after-commit',
    'before-owner-promotion',
  ]) {
    test(
      'native process exit: $stage; safe reopen same immutable ID',
      () async {
        final dir = createSpikeDirectory();
        final source = const UserFinancialDataCodec().encode(
          syntheticFixture(count: 60),
        );
        File('${dir.path}/source.json').writeAsStringSync(source, flush: true);
        final snapshot = FinancialSnapshot(source),
            partition = Partition('synthetic-4f', '4f-lineage');
        var store = await SqliteContainer.migrate(
          dir.path,
          MigrationManifest('bootstrap-4f', partition, snapshot.hash),
          snapshot,
          incremental: true,
        );
        await store.close();
        final result = await Process.run(
          File(
            'build/receipt_probe/bundle/bin/receipt_probe.exe',
          ).absolute.path,
          [dir.path, stage],
        );
        expect(result.exitCode, 86, reason: '${result.stderr}');
        store = await SqliteContainer.open(dir.path, partition);
        try {
          final committed = [
            'effects-after-commit',
            'before-owner-promotion',
          ].contains(stage);
          expect((await store.readSnapshot()).revision, committed ? 1 : 0);
          expect(
            await store.readPendingCommands(),
            hasLength(committed ? 1 : 0),
          );
          store.verify();
          final p =
              NotePreparationScope.admit(
                source,
                workspace: partition.workspace,
                lineage: partition.lineage,
                revision: 0,
                generation: 0,
              ).prepare(
                commandId: 'process-one',
                target: 'container-tx-0',
                note: 'crash-note',
                time: DateTime.utc(2026, 10, 16),
              );
          final req = storageRequest(p, store.generation);
          final receipt = committed
              ? await store.resolveEffects(req)
              : await store.commitEffects(req);
          await store.verifyEffectsReceipt(receipt, req);
          expect((await store.readSnapshot()).value.json, p.snapshot.json);
          expect(await store.readPendingCommands(), hasLength(1));
          evidence.add({
            'stage': stage,
            'exit': result.exitCode,
            'committed_before_restart': committed,
            'recovered_same_id': true,
            'durable_outbox': true,
            'kind': 'process-crash-not-power-loss',
          });
        } finally {
          await store.close();
        }
      },
    );
  }
  tearDownAll(
    () => File(
      'results/process-crashes.json',
    ).writeAsStringSync(jsonEncode(evidence)),
  );
}
