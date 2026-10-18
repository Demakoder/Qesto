import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto_durable_effects_experiment/prepared_commit.dart';

void main() {
  late Directory dir;
  late SqliteContainer store;
  late String initial;
  const partition = Partition('synthetic-4g-cache', 'generation-a');
  setUp(() async {
    dir = createSpikeDirectory();
    initial = encodeSynthetic(count: 60);
    final snapshot = FinancialSnapshot(initial);
    store = await SqliteContainer.migrate(dir.path,
      MigrationManifest('synthetic-cache', partition, snapshot.hash), snapshot,
      incremental: true);
  });
  tearDown(() async { await store.close(); });

  test('byte budget retains exact verified source or safely rejects oversized entry', () async {
    for (final budget in [0, 1024, initial.length * 2 + 1024, 64 * 1024 * 1024]) {
      store.setReadCacheBudgetForExperiment(budget);
      for (var i = 0; i < 3; i++) {
        expect((await store.readSnapshot()).value.json, initial);
        expect(store.retainedCachePayloadBytes, lessThanOrEqualTo(budget));
        store.verify();
      }
    }
  });

  test('50 commits release staged buffers and superseded JSON without losing durable outbox', () async {
    const budget = 1024 * 1024;
    store.setReadCacheBudgetForExperiment(budget);
    final owner = await DurableEffectsOwner.load(store);
    for (var i = 0; i < 50; i++) {
      final p = owner.prepare(commandId: 'cache-$i', target: 'container-tx-0',
        note: 'synthetic generation $i', time: DateTime.utc(2026, 10, 18, 0, i));
      await owner.commit(p);
      expect(owner.status, EffectsOwnerStatus.ready);
      expect(owner.revision, i + 1);
      expect(store.cacheDiagnostics['stagedEntries'], 0);
      expect(store.retainedCachePayloadBytes, lessThanOrEqualTo(budget));
      expect((await store.readSnapshot()).value.json, p.snapshot.json);
    }
    expect(await store.readPendingCommands(), hasLength(50));
    store.verify();
  });

  test('warmed caches never hide native chunk corruption', () async {
    store.setReadCacheBudgetForExperiment(64 * 1024 * 1024);
    await store.readSnapshot();
    store.raw.execute("UPDATE json_chunks SET body='corrupt' WHERE scope='state' AND slot=0");
    await expectLater(store.readSnapshot(), throwsA(isA<ContractViolation>()));
  });

  test('warmed caches never hide changed manifest', () async {
    store.setReadCacheBudgetForExperiment(64 * 1024 * 1024);
    await store.readSnapshot();
    store.raw.execute("UPDATE state SET snapshot='{}' WHERE id=1");
    await expectLater(store.readSnapshot(), throwsA(isA<ContractViolation>()));
  });

  test('rotation drops old database generation caches and preserves pending commands', () async {
    store.setReadCacheBudgetForExperiment(64 * 1024 * 1024);
    final owner = await DurableEffectsOwner.load(store);
    final p = owner.prepare(commandId: 'pending-rotation', target: 'container-tx-0',
      note: 'rotation', time: DateTime.utc(2026, 10, 18));
    await owner.commit(p);
    final generation = store.generation;
    owner.invalidate('key-rotation');
    await store.rotateKey();
    expect(store.generation, generation + 1);
    expect(store.retainedCachePayloadBytes, 0);
    expect((await store.readSnapshot()).value.json, p.snapshot.json);
    expect((await store.readPendingCommands()).single.receipt.id, 'pending-rotation');
    await owner.reloadAfterRemote();
    expect(owner.status, EffectsOwnerStatus.ready);
    store.verify();
  });
}
