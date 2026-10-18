import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/services/transaction_note_preparation.dart';
import 'package:qesto_synthetic_sync/domain.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto_incremental_domain_experiment/effects.dart';
import '../lib/app_probe.dart';
import '../lib/oracle.dart';

const codec = UserFinancialDataCodec();
final time = DateTime.utc(2026, 10, 16);
CoreEffectsBinding binding(
  String id, {
  int revision = 0,
  int generation = 0,
  String policy = 'policy',
  String workspace = 'synthetic-4e',
  String lineage = 'lineage-4e',
  String target = 'container-tx-0',
  String kind = 'transaction.set_note',
}) => CoreEffectsBinding(
  commandId: id,
  workspace: workspace,
  lineage: lineage,
  target: target,
  kind: kind,
  baseRevision: revision,
  generation: generation,
  policyFingerprint: policy,
);
w.NoteCommand command(String id, String note) => w.NoteCommand.parse({
  'protocol_version': 1,
  'domain_version': 1,
  'workspace_id': 'synthetic-4e',
  'device_id': 'synthetic-4a-a',
  'workspace_epoch': 'lineage-4e',
  'change_id': id,
  'kind': 'transaction.set_note',
  'transaction_id': 'container-tx-0',
  'base_revision': '0',
  'note': note,
});

void main() {
  test(
    'competing preparations on same target stay separate; stale journal cannot replay',
    () {
      final data = syntheticFixture(count: 60),
          policy = w.digest(
            syntheticFixture(count: 60).classification.toJson(),
          );
      final a = prepareNote(
        data,
        'container-tx-0',
        'left',
        binding('left', policy: policy),
        time,
      );
      final b = prepareNote(
        data,
        'container-tx-0',
        'right',
        binding('right', policy: policy),
        time,
      );
      expect(a.state.transactions.first.userNote, 'left');
      expect(b.state.transactions.first.userNote, 'right');
      expect(() => replayJournal(a.state, b.journal), throwsStateError);
      expect(
        () => CoreJournalPreparation.fromState(
          initialState: data.synoballState!,
          policy: data.classification.policy,
          binding: binding('async'),
          ids: CommandIds('async'),
          clock: () => time,
          execute: (_) => Future.value(),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'note, identical note/audit-only, clear: exact core, app and old oracle parity',
    () {
      var data = syntheticFixture(count: 60);
      CoreJournalPreparation? prior;
      var revision = 0;
      for (final note in [
        'Synthetic note',
        'Synthetic note',
        'Synthetic note',
        '',
        'Я • 13,01',
      ]) {
        final id = 'note-$revision', c = command('note-$revision', note);
        final beforeJson = codec.encode(data);
        final p = prepareNote(
          data,
          c.target,
          note,
          binding(
            id,
            revision: revision,
            generation: revision,
            policy: w.digest(data.classification.toJson()),
          ),
          time,
          prior: prior,
        );
        final full = prepareTransactionNote(
          data,
          c.target,
          note,
          ids: CommandIds(id),
          clock: () => time,
        );
        expect(p.state.toJson(), full.core.state.toJson());
        verifyJournal(data.synoballState!, full.core.state, p.journal);
        final after = project(data, p.state);
        expect(codec.encode(after), codec.encode(full.data));
        final oracle = DomainEffectsV1.between(
          data,
          after,
          c,
          baseRevision: revision,
        );
        expect(codec.encode(oracle.reconstruct(data)), codec.encode(after));
        if (revision == 2) {
          expect(
            p.journal.changedCanonicalIds,
            isEmpty,
            reason: jsonEncode(
              p.journal.writes
                  .where((e) => e.collection == 'transactions')
                  .map((e) => e.toJson())
                  .toList(),
            ),
          );
          expect(
            p.journal.changedCollections,
            containsAll(['auditEntries', 'events']),
          );
        }
        expect(
          codec.encode(data),
          beforeJson,
          reason: 'speculative state stays isolated',
        );
        // Test sequencing only: not a durable promotion or a storage receipt.
        prior = p;
        data = after;
        revision++;
      }
    },
  );

  test('constructor normalization: stale policy changes exactly 21 of 60', () {
    final raw = jsonDecode(codec.encode(syntheticFixture(count: 60)));
    for (final t in raw['synoball']['transactions']) {
      t['synoballCategory'] = 'business';
      t['userCategoryOverride'] = null;
      t['tags'] = ['user-label:qa'];
    }
    final data = codec.decode(jsonEncode(raw));
    final p = prepareNote(
      data,
      'container-tx-0',
      'test',
      binding('stale-policy', policy: w.digest(data.classification.toJson())),
      time,
    );
    final full = prepareTransactionNote(
      data,
      'container-tx-0',
      'test',
      ids: CommandIds('stale-policy'),
      clock: () => time,
    );
    verifyJournal(data.synoballState!, full.core.state, p.journal);
    expect(p.state.toJson(), full.core.state.toJson());
    expect(p.journal.changedCanonicalIds.length, 21);
    final oracle = DomainEffectsV1.between(
      data,
      full.data,
      command('stale-policy', 'test'),
      baseRevision: 0,
    );
    expect(p.journal.changedCanonicalIds, oracle.canonicalFields.keys.toSet());
    Directory('results').createSync(recursive: true);
    File('results/stale-policy-gate.json').writeAsStringSync(
      jsonEncode({
        'count': 60,
        'changed': p.journal.changedCanonicalIds.length,
        'full_parity': true,
        'journal': p.journal.toJson(),
        'synthetic_only': true,
      }),
    );
  });

  test(
    'dropped write and unregistered state mutation are detected by independent oracle',
    () {
      final data = syntheticFixture(count: 60);
      final p = prepareNote(
        data,
        'container-tx-0',
        'test',
        binding('negative', policy: w.digest(data.classification.toJson())),
        time,
      );
      expect(
        () => verifyJournal(
          data.synoballState!,
          p.state,
          p.journal,
          dropLastForNegativeTest: true,
        ),
        throwsStateError,
      );
      final tampered = jsonDecode(jsonEncode(p.state.toJson()));
      tampered['transactions'][3]['userNote'] = 'unregistered change';
      expect(
        () => verifyJournal(
          data.synoballState!,
          SynoballState.fromJson(tampered),
          p.journal,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'journal and owned state are deeply immutable; admission detaches source and policy',
    () {
      final raw = jsonDecode(codec.encode(syntheticFixture(count: 60)));
      raw['synoball']['transactions'][0]['tags'] = ['user-field:note'];
      raw['synoball']['events'] = [
        {
          'id': 'synthetic-evt',
          'type': 'probe',
          'entityId': 'synthetic',
          'occurredAt': time.toIso8601String(),
          'subjectId': null,
          'payload': {
            'nested': {
              'values': ['original'],
            },
          },
        },
      ];
      final data = codec.decode(jsonEncode(raw));
      final p = prepareNote(
        data,
        'container-tx-0',
        'test',
        binding('ownership', policy: w.digest(data.classification.toJson())),
        time,
      );
      final before = jsonEncode(p.state.toJson()),
          journal = jsonEncode(p.journal.toJson());
      data.synoballState!.transactions[0].tags.add('outside');
      (data.synoballState!.events[0].payload['nested']['values'] as List).add(
        'outside',
      );
      expect(jsonEncode(p.state.toJson()), before);
      expect(
        () => p.state.transactions[0].tags.add('leak'),
        throwsUnsupportedError,
      );
      expect(
        () =>
            (p.state.events[0].payload['nested']['values'] as List).add('leak'),
        throwsUnsupportedError,
      );
      expect(() => p.journal.writes.clear(), throwsUnsupportedError);
      expect(
        () => p.journal.writes.first.after!['tags'] = [],
        throwsUnsupportedError,
      );
      final q = p.prepareNext(
        binding: binding(
          'next',
          revision: 1,
          generation: 1,
          policy: p.journal.binding.policyFingerprint,
        ),
        ids: CommandIds('next'),
        clock: () => time,
        execute: (core) {
          core.updateTransaction(
            core
                .transactionById('container-tx-0')!
                .copyWith(tags: ['user-field:note'], userNote: 'next'),
            actorId: 'test',
          );
          return null;
        },
      );
      expect(jsonEncode(p.state.toJson()), before);
      expect(jsonEncode(p.journal.toJson()), journal);
      verifyJournal(p.state, q.state, q.journal);
    },
  );

  test(
    'abort seals escaped core; retry uses original input and stable IDs',
    () {
      final data = syntheticFixture(count: 60),
          before = codec.encode(syntheticFixture(count: 60));
      late SynoballCore escaped;
      expect(
        () => CoreJournalPreparation.fromState(
          initialState: data.synoballState!,
          policy: data.classification.policy,
          binding: binding('abort'),
          ids: CommandIds('abort'),
          clock: () => time,
          execute: (core) {
            escaped = core;
            core.deleteTransaction('container-tx-0', actorId: 'qa');
            throw StateError('injected');
          },
        ),
        throwsStateError,
      );
      expect(
        () => escaped.updateTransaction(
          escaped.transactionById('container-tx-1')!,
          actorId: 'qa',
        ),
        throwsStateError,
      );
      expect(codec.encode(data), before);
      final b = binding(
        'retry',
        policy: w.digest(data.classification.toJson()),
      );
      final first = prepareNote(data, 'container-tx-0', 'retry', b, time);
      final retry = prepareNote(
        codec.decode(codec.encode(data)),
        'container-tx-0',
        'retry',
        b,
        time,
      );
      expect(first.state.toJson(), retry.state.toJson());
      expect(first.journal.toJson(), retry.journal.toJson());
    },
  );

  test(
    'stale/foreign/replayed binding and unsupported app command fail closed',
    () {
      final data = syntheticFixture(count: 60),
          policy = w.digest(
            syntheticFixture(count: 60).classification.toJson(),
          );
      final p = prepareNote(
        data,
        'container-tx-0',
        'a',
        binding('a', policy: policy),
        time,
      );
      for (final b in [
        binding('b', policy: policy),
        binding('b', revision: 1, generation: 2, policy: policy),
        binding('b', revision: 1, generation: 1, policy: 'changed'),
        binding(
          'b',
          revision: 1,
          generation: 1,
          policy: policy,
          workspace: 'foreign',
        ),
        binding(
          'b',
          revision: 1,
          generation: 1,
          policy: policy,
          lineage: 'other',
        ),
        binding('a', revision: 1, generation: 1, policy: policy),
      ]) {
        expect(
          () => p.prepareNext(
            binding: b,
            ids: CommandIds('b'),
            clock: () => time,
            execute: (_) => null,
          ),
          throwsStateError,
        );
      }
      expect(
        () => prepareNote(
          data,
          'container-tx-0',
          'a',
          binding('a', policy: policy, kind: 'unknown'),
          time,
        ),
        throwsStateError,
      );
      late SynoballCore escaped;
      final sealed = CoreJournalPreparation.fromState(
        initialState: data.synoballState!,
        policy: data.classification.policy,
        binding: binding('sealed'),
        ids: CommandIds('sealed'),
        clock: () => time,
        execute: (core) {
          escaped = core;
          return null;
        },
      );
      expect(
        () => escaped.setCategoryPolicy(const CategoryPolicy()),
        throwsStateError,
      );
      expect(
        () => escaped.upsertAccount(data.synoballState!.accounts.first),
        throwsStateError,
      );
      expect(
        () => escaped.restoreTransaction(
          CanonicalTransaction.fromJson({
            ...data.synoballState!.transactions.first.toJson(),
            'id': 'late-new-id',
          }),
        ),
        throwsStateError,
      );
      final following = sealed.prepareNext(
        binding: binding('after-seal', revision: 1, generation: 1),
        ids: CommandIds('after-seal'),
        clock: () => time,
        execute: (core) {
          expect(core.transactionById('late-new-id'), isNull);
          return null;
        },
      );
      expect(following.state.toJson(), sealed.state.toJson());
    },
  );
}
