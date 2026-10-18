import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import '../lib/prepared_commit.dart';
import 'coverage_test.dart' show verify;

final time = DateTime.utc(2026, 10, 16);
void main() {
  late Directory dir;
  late String source;
  late SqliteContainer store;
  late DurableEffectsOwner owner;
  const partition = Partition('synthetic-4f', '4f-lineage');
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
    owner = await DurableEffectsOwner.load(store);
  });
  tearDown(() async => store.close());
  PreparedFinancialCommit prepare(String id, String note) => owner.prepare(
    commandId: id,
    target: 'container-tx-0',
    note: note,
    time: time,
  );

  test(
    'prepare/commit/verify/promote: no publication before COMMIT, exactly once',
    () async {
      final p = prepare('owner-one', 'one');
      final gate = Completer<void>(), arrived = Completer<void>();
      var published = 0;
      final result = owner
          .commit(
            p,
            beforeCommit: () {
              arrived.complete();
              return gate.future;
            },
          )
          .then((value) {
            published++;
            return value;
          });
      await arrived.future;
      expect(owner.revision, 0);
      expect((await store.readSnapshot()).value.json, source);
      expect(await store.readPendingCommands(), isEmpty);
      expect(published, 0);
      expect(
        () => prepare('competing', 'x'),
        throwsA(isA<EffectsOwnerFailure>()),
      );
      gate.complete();
      final delta = await result;
      expect(published, 1);
      expect(owner.revision, 1);
      expect(owner.generation, 1);
      expect(delta.revision, 1);
      expect(delta.toJson().containsKey('snapshot'), isFalse);
      await expectLater(owner.commit(p), throwsA(isA<EffectsOwnerFailure>()));
      expect(published, 1);
      verify(source, p, 'one');
      final second = prepare('owner-two', 'two');
      verify(p.snapshot.json, second, 'two');
      await owner.commit(second);
      expect(owner.revision, 2);
    },
  );
  test('audit-only command publishes revision and audit effects', () async {
    late CommittedEffectsDelta delta;
    for (var i = 0; i < 3; i++) {
      delta = await owner.commit(prepare('same-$i', 'same'));
    }
    expect(delta.appEffects.writes, isEmpty);
    expect(delta.coreWrites.any((w) => w.collection == 'auditEntries'), isTrue);
    expect(delta.revision, 3);
  });
  test('foreign candidate rejected before SQLite mutation', () async {
    final scope = NotePreparationScope.admit(
      source,
      workspace: 'synthetic-other',
      lineage: 'foreign',
      revision: 0,
      generation: 0,
    );
    final foreign = scope.prepare(
      commandId: 'foreign',
      target: 'container-tx-0',
      note: 'x',
      time: time,
    );
    prepare('ours', 'a');
    await expectLater(
      owner.commit(foreign),
      throwsA(isA<EffectsOwnerFailure>()),
    );
    expect((await store.readSnapshot()).revision, 0);
  });
  test(
    'policy invalidation before COMMIT rejects stale candidate without success',
    () async {
      final p = prepare('invalidated', 'a');
      await expectLater(
        owner.commit(
          p,
          beforeCommit: () async {
            owner.invalidate('policy');
          },
        ),
        throwsA(
          isA<EffectsOwnerFailure>().having(
            (e) => e.outcomeUnknown,
            'known abort',
            false,
          ),
        ),
      );
      expect((await store.readSnapshot()).revision, 0);
      expect(owner.status, EffectsOwnerStatus.invalidated);
      await owner.reloadAfterRemote();
      expect(owner.status, EffectsOwnerStatus.ready);
    },
  );
  test(
    'invalidation after COMMIT blocks publication; safe reopen restores durable state',
    () async {
      final p = prepare('after-commit', 'a');
      await expectLater(
        owner.commit(
          p,
          afterCommit: () async {
            owner.invalidate('remote');
          },
        ),
        throwsA(
          isA<EffectsOwnerFailure>().having(
            (e) => e.outcomeUnknown,
            'unknown',
            true,
          ),
        ),
      );
      expect(owner.status, EffectsOwnerStatus.outcomeUnknown);
      expect(
        () => prepare('unsafe-new-id', 'b'),
        throwsA(isA<EffectsOwnerFailure>()),
      );
      await expectLater(
        owner.reloadAfterRemote(),
        throwsA(isA<EffectsOwnerFailure>()),
      );
      await expectLater(
        owner.resolveAfterSafeReopen(store),
        throwsA(isA<EffectsOwnerFailure>()),
      );
      await store.close();
      store = await SqliteContainer.open(dir.path, partition);
      owner = await owner.resolveAfterSafeReopen(store);
      expect(owner.revision, 1);
      expect((await store.readSnapshot()).value.json, p.snapshot.json);
      expect(await store.readPendingCommands(), hasLength(1));
    },
  );
  for (final stage in ['local-before-commit', 'effects-after-commit']) {
    test(
      'unknown outcome at $stage reuses exact immutable command after reopen',
      () async {
        await store.close();
        store = await SqliteContainer.open(
          dir.path,
          partition,
          fault: (s) {
            if (s == stage) throw StateError('fault');
          },
        );
        owner = await DurableEffectsOwner.load(store);
        final p = prepare('uncertain', 'a');
        await expectLater(
          owner.commit(p),
          throwsA(
            isA<EffectsOwnerFailure>().having(
              (e) => e.outcomeUnknown,
              'unknown',
              true,
            ),
          ),
        );
        await store.close();
        store = await SqliteContainer.open(dir.path, partition);
        owner = await owner.resolveAfterSafeReopen(store);
        expect(owner.revision, 1);
        final pending = await store.readPendingCommands();
        expect(pending, hasLength(1));
        expect(
          jsonDecode(
            pending.single.immutableJson,
          )['intent']['_local_effects_v1']['binding']['preparedIdentity'],
          p.identity,
        );
        expect((await store.readSnapshot()).value.json, p.snapshot.json);
        expect(owner.generation, greaterThan(p.binding.generation));
      },
    );
  }
  test(
    'remote reload discards candidate; new candidate binds advanced generation',
    () async {
      final p = prepare('stale', 'a');
      owner.invalidate('remote-apply');
      await owner.reloadAfterRemote();
      final next = prepare('fresh', 'b');
      expect(next.binding.generation, greaterThan(p.binding.generation));
      await expectLater(owner.commit(p), throwsA(isA<EffectsOwnerFailure>()));
      await owner.commit(next);
    },
  );
}
