import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/services/transaction_note_preparation.dart';
import 'package:qesto_synthetic_sync/domain.dart';
import 'package:qesto_core_effects_experiment/oracle.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import '../lib/prepared_commit.dart';

const codec = UserFinancialDataCodec();
final time = DateTime.utc(2026, 10, 16);
const target = 'container-tx-0';
NotePreparationScope scope(String before) => NotePreparationScope.admit(
  before,
  workspace: 'synthetic-4f',
  lineage: '4f-lineage',
  revision: 0,
  generation: 0,
);

void verify(String before, PreparedFinancialCommit p, String note) {
  final data = codec.decode(before);
  final old = prepareTransactionNote(
    data,
    p.binding.target,
    note,
    ids: CommandIds(p.binding.commandId),
    clock: () => time,
  );
  // Full original executor is independent of the incremental projection path.
  expect(jsonDecode(p.snapshot.json), jsonDecode(codec.encode(old.data)));
  verifyJournal(data.synoballState!, old.core.state, p.coreEffects);
  final replay = jsonDecode(before);
  replay['synoball'] = replayJournal(data.synoballState!, p.coreEffects);
  for (final effect in p.appEffects.writes) {
    expect(replay[effect.collection][effect.index], effect.before);
    replay[effect.collection][effect.index] = effect.after;
  }
  expect(replay, jsonDecode(p.snapshot.json));
  expect(p.complete, isTrue);
}

void main() {
  for (final note in [
    'new note',
    '',
    'Кофе ☕\n🙂 e\u0301',
    'между своими счетами',
  ]) {
    test('full codec / core / legacy parity: $note', () {
      final before = codec.encode(syntheticFixture(count: 60));
      final s = scope(before);
      final p = s.prepare(
        commandId: 'coverage',
        target: target,
        note: note,
        time: time,
      );
      verify(before, p, note);
    });
  }
  test('stale policy 21/60 plus stale unrelated legacy projection', () {
    final raw = jsonDecode(codec.encode(syntheticFixture(count: 60)));
    for (final t in raw['synoball']['transactions']) {
      t['synoballCategory'] = 'business';
      t['userCategoryOverride'] = null;
      t['tags'] = ['user-label:qa'];
    }
    raw['transactions'][4]['title'] = 'stale-only-legacy';
    raw['accounts'][0]['balance'] = 999;
    final before = jsonEncode(raw);
    final p = scope(before).prepare(
      commandId: 'stale-policy',
      target: target,
      note: 'test',
      time: time,
    );
    verify(before, p, 'test');
    expect(p.coreEffects.changedCanonicalIds.length, 21);
    expect(p.appEffects.writes.any((w) => w.collection == 'accounts'), isTrue);
    Directory('results').createSync(recursive: true);
    File('results/gate-a-stale.json').writeAsStringSync(
      jsonEncode({
        'canonical_count': 60,
        'changed_canonical': p.coreEffects.changedCanonicalIds.length,
        'app_writes': p.appEffects.writes.length,
        'full_codec_parity': true,
        'effects_digest': p.effectsDigest,
        'identity': p.identity,
      }),
    );
  });
  test(
    'repeated note / audit-only sequence and clearing remain exactly equivalent',
    () {
      var before = codec.encode(syntheticFixture(count: 60));
      var s = scope(before);
      for (var i = 0; i < 4; i++) {
        final note = i == 3 ? '' : 'same';
        final p = s.prepare(
          commandId: 'sequence-$i',
          target: target,
          note: note,
          time: time,
        );
        verify(before, p, note);
        if (i == 2) {
          expect(p.coreEffects.changedCanonicalIds, isEmpty);
          expect(p.coreEffects.changedCollections, contains('auditEntries'));
          expect(p.appEffects.writes, isEmpty);
        }
        before = p.snapshot.json;
        s = NotePreparationScope.oracleSequence(p);
      }
    },
  );
  test('immutable result cannot mutate state / effects / caller data', () {
    final data = syntheticFixture(count: 60),
        before = codec.encode(syntheticFixture(count: 60));
    final s = scope(codec.encode(data));
    final p = s.prepare(
      commandId: 'immutable',
      target: target,
      note: 'a',
      time: time,
    );
    final identity = p.identity;
    expect(() => p.appEffects.writes.clear(), throwsUnsupportedError);
    expect(
      () => p.appEffects.writes.first.after['comment'] = 'corrupt',
      throwsUnsupportedError,
    );
    expect(
      () => (p.appEffects.writes.first.after['tags'] as List).clear(),
      throwsUnsupportedError,
    );
    expect(() => p.bindingJson['user'] = 'foreign', throwsUnsupportedError);
    expect(() => p.timings.clear(), throwsUnsupportedError);
    data.transactions.first.tags.clear();
    verify(before, p, 'a');
    expect(p.identity, identity);
  });
  test('two candidates from a revision do not alias', () {
    final before = codec.encode(syntheticFixture(count: 60)),
        s = scope(codec.encode(syntheticFixture(count: 60)));
    final a = s.prepare(commandId: 'a', target: target, note: 'A', time: time);
    final b = s.prepare(commandId: 'b', target: target, note: 'B', time: time);
    verify(before, a, 'A');
    verify(before, b, 'B');
    expect(a.identity, isNot(b.identity));
  });
  test(
    'unsupported commands, projection membership/order, duplicates fail closed',
    () {
      final before = codec.encode(syntheticFixture(count: 60));
      expect(
        () => scope(before).prepare(
          commandId: 'x',
          target: target,
          note: 'x',
          time: time,
          kind: 'unsupported',
        ),
        throwsStateError,
      );
      expect(
        () => scope(before).prepare(
          commandId: 'x',
          target: 'container-tx-2',
          note: 'x',
          time: time,
        ),
        throwsStateError,
      );
      for (final mode in ['order', 'duplicate', 'membership']) {
        final raw = jsonDecode(before);
        if (mode == 'order')
          raw['transactions'] = (raw['transactions'] as List).reversed.toList();
        if (mode == 'duplicate')
          raw['transactions'][1]['id'] = raw['transactions'][0]['id'];
        if (mode == 'membership') (raw['transactions'] as List).removeLast();
        expect(() => scope(jsonEncode(raw)), throwsStateError);
      }
    },
  );
}
