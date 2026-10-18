import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import '../lib/prepared_commit.dart';
import '../lib/storage_request.dart';

const partition = Partition('synthetic-4f', '4f-lineage');
final time = DateTime.utc(2026, 10, 16);
void main() {
  late Directory dir;
  late String source;
  late PreparedFinancialCommit p;
  late SqliteContainer store;
  setUp(() async {
    dir = createSpikeDirectory();
    source = const UserFinancialDataCodec().encode(syntheticFixture(count: 60));
    final snapshot = FinancialSnapshot(source);
    store = await SqliteContainer.migrate(
      dir.path,
      MigrationManifest('bootstrap-4f', partition, snapshot.hash),
      snapshot,
      incremental: true,
    );
    p =
        NotePreparationScope.admit(
          source,
          workspace: partition.workspace,
          lineage: partition.lineage,
          revision: 0,
          generation: 0,
        ).prepare(
          commandId: 'receipt-one',
          target: 'container-tx-0',
          note: 'durable-note',
          time: time,
        );
  });
  tearDown(() async => store.close());
  Future<void> reopen({void Function(String)? fault}) async {
    await store.close();
    store = await SqliteContainer.open(dir.path, partition, fault: fault);
  }

  test(
    'container-issued receipt binds actual commit, immutable effects and outbox',
    () async {
      final request = storageRequest(p, store.generation);
      final r = await store.commitEffects(request);
      await store.verifyEffectsReceipt(r, request);
      expect(r.revision, 1);
      expect(r.bindingJson, request.bindingJson);
      expect((await store.readSnapshot()).value.json, p.snapshot.json);
      final pending = await store.readPendingCommands();
      expect(pending, hasLength(1));
      expect(pending.single.receipt.remotelyAccepted, isFalse);
      expect(pending.single.immutableJson, contains(p.effectsDigest));
      store.verify();
      final repeated = await store.commitEffects(request);
      expect(repeated.commandDigest, r.commandDigest);
      expect(await store.readPendingCommands(), hasLength(1));
    },
  );
  test(
    'a fabricated binding is not evidence; invalid envelope fails before commit',
    () async {
      expect(
        () => EffectsCommitRequest(
          mutation: Mutation(
            id: 'receipt-one',
            partition: partition,
            expectedRevision: 0,
            snapshot: p.snapshot,
            intentJson: '{}',
          ),
          effectsJson: p.effectsJson,
          binding: {...p.bindingJson, 'user': 'forged'},
          storageGeneration: store.generation,
        ),
        throwsA(isA<ContractViolation>()),
      );
      await expectLater(
        store.resolveEffects(storageRequest(p, store.generation)),
        throwsA(isA<ContractViolation>()),
      );
      expect((await store.readSnapshot()).revision, 0);
    },
  );
  test(
    'same ID different body and competing same-base candidate cannot commit',
    () async {
      await store.commitEffects(storageRequest(p, store.generation));
      final scope = NotePreparationScope.admit(
        source,
        workspace: partition.workspace,
        lineage: partition.lineage,
        revision: 0,
        generation: 0,
      );
      for (final id in ['receipt-one', 'receipt-two']) {
        final other = scope.prepare(
          commandId: id,
          target: 'container-tx-0',
          note: 'other',
          time: time,
        );
        await expectLater(
          store.commitEffects(storageRequest(other, store.generation)),
          throwsA(
            id == 'receipt-one'
                ? isA<CommandCollision>()
                : isA<StaleRevision>(),
          ),
        );
      }
      expect((await store.readSnapshot()).value.json, p.snapshot.json);
      expect(await store.readPendingCommands(), hasLength(1));
    },
  );
  test(
    'old authority dies at close/reopen; same ID resolves without new write',
    () async {
      final request = storageRequest(p, store.generation);
      final old = await store.commitEffects(request);
      await reopen();
      await expectLater(
        store.verifyEffectsReceipt(old, request),
        throwsA(isA<ContractViolation>()),
      );
      final resolved = await store.resolveEffects(request);
      await store.verifyEffectsReceipt(resolved, request);
      expect(await store.readPendingCommands(), hasLength(1));
    },
  );
  test(
    'receipt cannot cross containers even with identical bytes/partition',
    () async {
      final req = storageRequest(p, store.generation);
      final r = await store.commitEffects(req);
      final dir2 = createSpikeDirectory(), snapshot = FinancialSnapshot(source);
      final other = await SqliteContainer.migrate(
        dir2.path,
        MigrationManifest('bootstrap-4f', partition, snapshot.hash),
        snapshot,
        incremental: true,
      );
      try {
        await other.commitEffects(req);
        await expectLater(
          other.verifyEffectsReceipt(r, req),
          throwsA(isA<ContractViolation>()),
        );
      } finally {
        await other.close();
      }
    },
  );
  for (final stage in [
    'chunk-after-row',
    'local-after-snapshot',
    'local-before-commit',
    'effects-after-commit',
  ]) {
    test(
      'injected error at $stage requires reopen, atomic state + durable outbox',
      () async {
        await reopen(
          fault: (s) {
            if (s == stage) throw StateError('injected-$stage');
          },
        );
        final req = storageRequest(p, store.generation);
        await expectLater(store.commitEffects(req), throwsStateError);
        expect(store.requiresReopen, isTrue);
        await expectLater(
          store.commitEffects(req),
          throwsA(isA<ContractViolation>()),
        );
        await reopen();
        final committed = stage == 'effects-after-commit';
        expect((await store.readSnapshot()).revision, committed ? 1 : 0);
        expect(await store.readPendingCommands(), hasLength(committed ? 1 : 0));
        final r = committed
            ? await store.resolveEffects(req)
            : await store.commitEffects(req);
        await store.verifyEffectsReceipt(r, req);
        expect((await store.readSnapshot()).value.json, p.snapshot.json);
        store.verify();
      },
    );
  }
  test('warm chunk cache cannot bless corrupted data with a receipt', () async {
    final req = storageRequest(p, store.generation),
        r = await store.commitEffects(storageRequest(p, store.generation));
    await store.readSnapshot();
    store.raw.execute(
      "UPDATE json_chunks SET body='corrupt' WHERE scope='state' AND slot=0",
    );
    await expectLater(store.verifyEffectsReceipt(r, req), throwsA(anything));
  });
}
