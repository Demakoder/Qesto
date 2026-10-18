import 'dart:convert';
import 'package:test/test.dart';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto_synthetic_sync/domain.dart';
import '../lib/oracle.dart';
import 'journal_test.dart' show binding, time;

const account = SynoballAccount(
  id: 'synthetic-account',
  entityId: 'synthetic-entity',
  name: 'synthetic savings',
  type: SynoballAccountType.savings,
  currency: 'EUR',
  balance: Money(minorUnits: 1740025, currency: 'EUR'),
);
StatementInput input({
  String provider = 'stable',
  int minor = 1301,
  List<String> tags = const [],
  bool pending = false,
}) => StatementInput(
  entityId: account.entityId,
  receivedAt: time,
  rawPayload: 'synthetic only',
  batchName: 'synthetic',
  account: account,
  transactions: [
    TransactionSeed(
      accountId: account.id,
      amount: Money(minorUnits: minor, currency: 'EUR'),
      direction: FinancialDirection.outflow,
      occurredAt: time,
      description: 'Synthetic shop',
      providerTransactionId: provider,
      confidence: 1,
      tags: tags,
      requiresConfirmation: pending,
    ),
  ],
);

void compare(
  String name,
  SynoballState before,
  Object? Function(SynoballCore) run, {
  CategoryPolicy policy = const CategoryPolicy(),
}) {
  final original = jsonEncode(before.toJson());
  final p = CoreJournalPreparation.fromState(
    initialState: before,
    policy: policy,
    binding: binding(name, kind: 'core.lifecycle-probe'),
    ids: CommandIds(name),
    clock: () => time,
    execute: run,
  );
  final full = SynoballCore(
    initialState: before,
    categoryPolicy: policy,
    ids: CommandIds(name),
    clock: () => time,
  );
  run(full);
  expect(p.state.toJson(), full.state.toJson());
  verifyJournal(before, full.state, p.journal);
  expect(jsonEncode(before.toJson()), original);
}

void main() {
  test(
    'real repeated import, user overrides/locks, distinct purchase, delete/reimport/restore',
    () {
      final seed = SynoballCore(ids: CommandIds('seed'), clock: () => time);
      seed.ingest(StatementAdapter(ids: CommandIds('seed-adapter')), input());
      final tx = seed.transactions.single.id;
      compare('lifecycle', seed.state, (core) {
        core.updateTransaction(
          core
              .transactionById(tx)!
              .copyWith(
                amount: const Money(minorUnits: 50123, currency: 'EUR'),
                userCategoryOverride: 'sport',
                userNote: 'manual',
                tags: [
                  'user-field:amount',
                  'user-field:note',
                  'user-field:category',
                  'user-label:qa',
                ],
              ),
          actorId: 'qa',
        );
        core.ingest(StatementAdapter(ids: CommandIds('repeat')), input());
        expect(core.transactionById(tx)!.amount.minorUnits, 50123);
        expect(core.transactionById(tx)!.userNote, 'manual');
        core.ingest(
          StatementAdapter(ids: CommandIds('distinct')),
          input(provider: 'different'),
        );
        expect(core.transactions.length, 2);
        core.deleteTransaction(tx, actorId: 'qa');
        final result = core.ingest(
          StatementAdapter(ids: CommandIds('trash-repeat')),
          input(),
        );
        expect(result.suppressedTransactionIds, [tx]);
        core.removeAccountIfUnused(
          account.id,
        ); // second purchase keeps it present
        core.restoreDeletedTransaction(tx, actorId: 'qa');
        expect(core.transactionById(tx)!.amount.minorUnits, 50123);
        return null;
      });
      compare('missing-account-restore', seed.state, (core) {
        core.deleteTransaction(tx, actorId: 'qa');
        core.removeAccountIfUnused(account.id);
        expect(core.state.accounts, isEmpty);
        core.restoreDeletedTransaction(tx, actorId: 'qa');
        expect(core.state.accounts.single.isVirtual, isTrue);
        return null;
      });
    },
  );

  test(
    'pending confirmation, receipt provenance and nested receipt ownership',
    () {
      compare('pending', const SynoballState(accounts: [account]), (core) {
        final result = core.ingest(
          AndroidNotificationAdapter(
            ids: CommandIds('notif'),
            history: core.state,
          ),
          AndroidNotificationInput(
            entityId: account.entityId,
            receivedAt: time,
            rawPayload: 'synthetic',
            packageName: 'synthetic.bank',
            notificationKey: 'slot',
            transaction: input(pending: true).transactions.single,
          ),
        );
        expect(result.pendingCandidateIds, isNotEmpty);
        core.confirmCandidate(result.pendingCandidateIds.single, actorId: 'qa');
        core.ingest(
          ReceiptAdapter(ids: CommandIds('receipt')),
          ReceiptInput(
            entityId: account.entityId,
            receivedAt: time,
            rawPayload: 'synthetic receipt',
            transaction: input().transactions.single,
            fiscalFingerprint: 'synthetic-fiscal',
            rawText: 'synthetic',
            items: [
              const ReceiptItem(
                name: 'synthetic',
                total: Money(minorUnits: 1301, currency: 'EUR'),
              ),
            ],
          ),
        );
        return null;
      });
    },
  );

  test(
    'recurrence rebuild and policy change record neighbours and exact fields',
    () {
      final transactions = [
        for (var i = 0; i < 3; i++)
          CanonicalTransaction(
            id: 'rec-$i',
            entityId: account.entityId,
            accountId: account.id,
            status: CanonicalTransactionStatus.posted,
            amount: const Money(minorUnits: 99900, currency: 'EUR'),
            direction: FinancialDirection.outflow,
            occurredAt: DateTime.utc(2026, 7 + i, 5),
            rawDescription: 'NETFLIX',
            normalizedDescription: 'NETFLIX',
            merchantName: 'NETFLIX',
            synoballCategory: 'subscriptions',
            eventType: FinancialEventType.observed,
            createdAt: time,
            updatedAt: time,
            fieldTrust: SourceTrustLevel.bankStatement,
          ),
      ];
      final initial = SynoballState(
        accounts: [account],
        transactions: transactions,
      );
      compare('recurring', initial, (core) {
        expect(core.state.recurringStreams, isNotEmpty);
        core.updateTransaction(
          core
              .transactionById('rec-2')!
              .copyWith(merchantName: 'Unrelated shop', userNote: 'changed'),
          actorId: 'qa',
        );
        core.setCategoryPolicy(
          const CategoryPolicy(redirects: {'subscriptions': 'media'}),
        );
        core.removeUserTag('unused', actorId: 'qa');
        return null;
      });
    },
  );

  test(
    'policy input cannot mutate an owned prepared state after completion',
    () {
      final rules = <MerchantCategoryRule>[],
          redirects = <String, String>{'sport': 'fitness'},
          valid = <String>{'qa'};
      final p = CoreJournalPreparation.fromState(
        initialState: const SynoballState(),
        policy: CategoryPolicy(
          rules: rules,
          redirects: redirects,
          validTagIds: valid,
        ),
        binding: binding('policy'),
        ids: CommandIds('policy'),
        clock: () => time,
        execute: (_) => null,
      );
      redirects['sport'] = 'corrupted';
      valid.clear();
      expect(p.journal.configuredPolicy['redirects'], {'sport': 'fitness'});
      expect(p.journal.configuredPolicy['validTagIds'], ['qa']);
      expect(
        () => (p.journal.configuredPolicy['redirects'] as Map).clear(),
        throwsUnsupportedError,
      );
      final changed = p.prepareNext(
        binding: binding('changed', revision: 1, generation: 1),
        ids: CommandIds('changed'),
        clock: () => time,
        execute: (core) {
          core.setCategoryPolicy(
            const CategoryPolicy(redirects: {'sport': 'fitness-v2'}),
          );
          return null;
        },
      );
      expect(changed.journal.policyChangedDuringExecution, isTrue);
      expect(changed.journal.writes, isEmpty);
      expect(changed.journal.toJson()['invalidations'], isNotEmpty);
      expect(
        () => changed.prepareNext(
          binding: binding('stale-after-policy', revision: 2, generation: 2),
          ids: CommandIds('stale'),
          clock: () => time,
          execute: (_) => null,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'restart rejects unknown schema and permits exact replay from verified original',
    () {
      expect(
        () => CoreJournalPreparation.fromState(
          initialState: const SynoballState(modelVersion: 'future'),
          policy: const CategoryPolicy(),
          binding: binding('future'),
          ids: CommandIds('future'),
          clock: () => time,
          execute: (_) => null,
        ),
        throwsStateError,
      );
      final seed = SynoballCore(ids: CommandIds('seed'), clock: () => time);
      seed.ingest(StatementAdapter(ids: CommandIds('seed-adapter')), input());
      final restored = SynoballState.fromJson(
        jsonDecode(jsonEncode(seed.state.toJson())),
      );
      compare('restart', restored, (core) {
        core.updateTransaction(
          core.transactions.single.copyWith(userNote: 'restart'),
          actorId: 'qa',
        );
        return null;
      });
    },
  );
}
