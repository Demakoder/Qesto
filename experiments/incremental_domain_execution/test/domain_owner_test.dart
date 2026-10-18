import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/services/transaction_note_preparation.dart';
import 'package:qesto_synthetic_sync/domain.dart' show CommandIds;
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto_incremental_domain_experiment/effects.dart';
import 'package:qesto_incremental_domain_experiment/prepared_owner.dart';

const codec = UserFinancialDataCodec();
final time = DateTime.utc(2026, 10, 14);
w.NoteCommand command(
  String id, {
  String target = 'container-tx-0',
  String note = 'Synthetic note',
  String workspace = 'synthetic-4d',
  String epoch = 'lineage-4d',
}) => w.NoteCommand.parse({
  'protocol_version': 1,
  'domain_version': 1,
  'workspace_id': workspace,
  'device_id': 'synthetic-4a-a',
  'workspace_epoch': epoch,
  'change_id': id,
  'kind': 'transaction.set_note',
  'transaction_id': target,
  'base_revision': '0',
  'note': note,
});
PreparedDomainOwner owner(UserFinancialData data) =>
    PreparedDomainOwner('synthetic-4d', 'lineage-4d', syntheticUser)
      ..loadVerified(data, 0);
PreparedDomainCommand prepare(
  PreparedDomainOwner o,
  w.NoteCommand c,
  int revision,
) => o.prepare(c, revision, time, w.digest(o.current.classification.toJson()));

void main() {
  test(
    'full codec + canonical + audit/events parity through repeated committed edits',
    () {
      var data = syntheticFixture(count: 60);
      final o = owner(data);
      for (var i = 0; i < 12; i++) {
        final c = command(
          'cmd-$i',
          target: 'container-tx-${i % 2}',
          note: i.isEven ? 'Между своими • 13,01 ₽' : '',
        );
        final old = codec.encode(data);
        final p = prepare(o, c, i);
        final oracle = prepareTransactionNote(
          data,
          c.target,
          c.note,
          ids: CommandIds(c.changeId),
          clock: () => time,
        );
        expect(codec.encode(p.after), codec.encode(oracle.data));
        expect(p.core.state.toJson(), oracle.core.state.toJson());
        expect(
          codec.encode(o.current),
          old,
          reason: 'no speculative publication',
        );
        final effects = DomainEffectsV1.between(
          data,
          p.after,
          c,
          baseRevision: i,
        );
        expect(codec.encode(effects.reconstruct(data)), codec.encode(p.after));
        expect(
          effects.coreCollections.keys,
          containsAll(['events', 'auditEntries']),
        );
        if (i == 0)
          expect(effects.coreCollections.keys, contains('transactions'));
        o.acceptDurable(
          p,
          revision: i + 1,
          durableJson: codec.encode(p.after),
          commandId: c.changeId,
        );
        data = p.after;
      }
      expect(o.fullLoads, 1);
      expect(o.forks, 12);
      expect(data.synoballState!.transactions.first.amount.minorUnits, 486122);
      expect(data.synoballState!.transactions[1].amount.currency, 'USD');
      expect(data.synoballState!.transactions[2].status.name, 'deleted');
    },
  );
  test(
    'stale configured policy changes multiple canonical entities, captured completely',
    () {
      final initial = syntheticFixture(count: 60);
      final raw = jsonDecode(codec.encode(initial)) as Map<String, dynamic>;
      for (final t in raw['synoball']['transactions'] as List) {
        t['synoballCategory'] = 'business';
        t['userCategoryOverride'] = null;
        t['tags'] = ['user-label:qa'];
      }
      final data = codec.decode(jsonEncode(raw)), c = command('policy');
      final p = prepare(owner(data), c, 0);
      final oracle = prepareTransactionNote(
        data,
        c.target,
        c.note,
        ids: CommandIds(c.changeId),
        clock: () => time,
      );
      expect(codec.encode(p.after), codec.encode(oracle.data));
      final e = DomainEffectsV1.between(data, p.after, c, baseRevision: 0);
      expect(e.canonicalFields.length, greaterThan(1));
      expect(codec.encode(e.reconstruct(data)), codec.encode(p.after));
      expect(() => e.reconstruct(p.after), throwsStateError);
      Directory('results').createSync(recursive: true);
      File('results/effects-gate.json').writeAsStringSync(
        jsonEncode({
          'passed': true,
          'synthetic_only': true,
          'effects': e.toJson(),
        }),
      );
    },
  );
  test(
    'changed policy and remote replacement require reload; same revision generation rejects old result',
    () {
      final data = syntheticFixture(), o = owner(data), c = command('stale');
      final p = prepare(o, c, 0);
      expect(() => o.prepare(c, 0, time, 'changed-policy'), throwsStateError);
      expect(() => prepare(o, c, 1), throwsStateError);
      expect(
        () => prepare(o, command('wrong', workspace: 'other'), 0),
        throwsStateError,
      );
      expect(
        () => prepare(o, command('wrong', epoch: 'other'), 0),
        throwsStateError,
      );
      final changed = data.copyWith(
        classification: const ClassificationSettings(),
      );
      o.loadVerified(changed, 0);
      expect(
        () => o.acceptDurable(
          p,
          revision: 1,
          durableJson: codec.encode(p.after),
          commandId: c.changeId,
        ),
        throwsStateError,
      );
      expect(() => o.current, throwsStateError);
      o.loadVerified(changed, 0);
      final next = prepare(o, c, 0);
      final oracle = prepareTransactionNote(
        changed,
        c.target,
        c.note,
        ids: CommandIds(c.changeId),
        clock: () => time,
      );
      expect(codec.encode(next.after), codec.encode(oracle.data));
    },
  );
  test(
    'failed/unknown commit discards RAM; durable bytes/receipt cannot be substituted',
    () {
      final data = syntheticFixture(), o = owner(data), c = command('failure');
      final p = prepare(o, c, 0);
      expect(codec.encode(o.current), codec.encode(data));
      o.invalidate(); // coordinator must invalidate on failed commit, crash/reload or unknown outcome
      expect(() => o.current, throwsStateError);
      o.loadVerified(data, 0);
      final p2 = prepare(o, c, 0);
      expect(codec.encode(p2.after), codec.encode(p.after));
      expect(
        () => o.acceptDurable(
          p2,
          revision: 1,
          durableJson: codec.encode(data),
          commandId: c.changeId,
        ),
        throwsStateError,
      );
      o.loadVerified(data, 0);
      expect(
        () => o.acceptDurable(
          prepare(o, c, 0),
          revision: 1,
          durableJson: codec.encode(p.after),
          commandId: 'wrong',
        ),
        throwsStateError,
      );
    },
  );
  test('trash/unknown command/foreign owner fail closed', () {
    final data = syntheticFixture(), o = owner(data);
    expect(
      () => prepare(o, command('trash', target: 'container-tx-2'), 0),
      throwsStateError,
    );
    expect(
      () => w.NoteCommand.parse({
        ...command('x').body,
        'kind': 'transaction.import',
      }),
      throwsA(isA<w.ApiError>()),
    );
    expect(
      () => PreparedDomainOwner('w', 'e', 'real-user').loadVerified(data, 0),
      throwsStateError,
    );
    final raw = jsonDecode(codec.encode(data));
    raw['synoball']['transactions'][0]['entityId'] = 'other';
    expect(
      () => o.loadVerified(codec.decode(jsonEncode(raw)), 0),
      throwsStateError,
    );
    expect(() => o.current, throwsStateError);
  });
  test(
    'fork ingestion indexes/evidence stay independent; repeated observation and trash match full initialization',
    () {
      final ids = SyntheticIds('seed'),
          core = SynoballCore(ids: SyntheticIds('seed'), clock: () => time);
      const account = SynoballAccount(
        id: 'synthetic-account',
        entityId: 'synthetic-entity',
        name: 'Synthetic',
        type: SynoballAccountType.checking,
        currency: 'EUR',
        balance: Money(minorUnits: 99999, currency: 'EUR'),
      );
      final input = StatementInput(
        entityId: 'synthetic-entity',
        receivedAt: time,
        rawPayload: 'synthetic',
        batchName: 'synthetic',
        account: account,
        transactions: [
          TransactionSeed(
            accountId: account.id,
            amount: const Money(minorUnits: 1301, currency: 'EUR'),
            direction: FinancialDirection.outflow,
            occurredAt: time,
            description: 'Synthetic shop',
            providerTransactionId: 'provider-stable',
            confidence: 1,
          ),
        ],
      );
      core.ingest(StatementAdapter(ids: ids), input);
      core.deleteTransaction(core.transactions.single.id, actorId: 'test');
      final before = jsonEncode(core.state.toJson());
      final fork = core.forkForCommand(
        ids: CommandIds('observation'),
        clock: () => time,
      );
      final full = SynoballCore(
        initialState: core.state,
        ids: CommandIds('observation'),
        clock: () => time,
      );
      fork.ingest(StatementAdapter(ids: SyntheticIds('again')), input);
      full.ingest(StatementAdapter(ids: SyntheticIds('again')), input);
      expect(fork.state.toJson(), full.state.toJson());
      expect(jsonEncode(core.state.toJson()), before);
      fork.restoreDeletedTransaction(
        fork.state.transactions.single.id,
        actorId: 'test',
      );
      full.restoreDeletedTransaction(
        full.state.transactions.single.id,
        actorId: 'test',
      );
      expect(fork.state.toJson(), full.state.toJson());
      expect(jsonEncode(core.state.toJson()), before);
    },
  );
}
