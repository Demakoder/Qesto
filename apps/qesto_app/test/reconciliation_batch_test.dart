import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  final day = DateTime(2026, 9, 8, 12);
  const account = SynoballAccount(
    id: 'a',
    entityId: 'e',
    name: 'Bank',
    type: SynoballAccountType.checking,
    currency: 'RUB',
    balance: Money(minorUnits: 0, currency: 'RUB'),
  );
  TransactionSeed seed(String id, {int minor = 10025}) => TransactionSeed(
    accountId: 'a',
    amount: Money(minorUnits: minor, currency: 'RUB'),
    direction: FinancialDirection.outflow,
    occurredAt: day,
    description: 'Coffee',
    merchant: 'Coffee',
    providerTransactionId: id,
    confidence: 1,
  );
  SynoballCore engine() =>
      SynoballCore(initialState: const SynoballState(accounts: [account]));
  void notify(SynoballCore core) => core.ingest(
    AndroidNotificationAdapter(),
    AndroidNotificationInput(
      entityId: 'e',
      receivedAt: day,
      rawPayload: 'synthetic',
      packageName: 'test.bank',
      notificationKey: 'n',
      transaction: seed('n'),
    ),
  );
  IngestionOutcome statement(SynoballCore core, List<TransactionSeed> rows) =>
      core.ingest(
        StatementAdapter(),
        StatementInput(
          entityId: 'e',
          receivedAt: day.add(const Duration(hours: 1)),
          rawPayload: 'synthetic',
          batchName: 'Test',
          account: account,
          transactions: rows,
        ),
      );

  for (final reverse in [false, true]) {
    test('batch claims are not first-row-wins (reverse=$reverse)', () {
      final core = engine();
      notify(core);
      final rows = [seed('bank-a'), seed('bank-b')];
      final result = statement(core, reverse ? rows.reversed.toList() : rows);
      expect(result.pendingCandidateIds, hasLength(2));
      expect(result.matchedTransactionIds, isEmpty);
      expect(core.transactions, hasLength(1));
      expect(
        core.state.candidates
            .where((c) => c.requiresConfirmation)
            .every(
              (c) => c.tags.contains('review-ambiguous_batch_cross_source'),
            ),
        isTrue,
      );
    });
  }
  test('repeated delivery with one stable id is not a batch conflict', () {
    final core = engine();
    notify(core);
    final result = statement(core, [seed('bank-a'), seed('bank-a')]);
    expect(result.pendingCandidateIds, isEmpty);
    expect(core.transactions, hasLength(1));
  });
  test(
    'source facts reconcile despite user amount and merchant corrections',
    () {
      final core = engine();
      notify(core);
      final original = core.transactions.single;
      core.updateTransaction(
        original.copyWith(
          amount: const Money(minorUnits: 50000, currency: 'RUB'),
          merchantName: 'My edited name',
          normalizedDescription: 'My description',
          tags: [
            'user-field:amount',
            'user-field:merchant',
            'user-field:description',
          ],
        ),
        actorId: 'user',
      );
      final result = statement(core, [seed('bank-a')]);
      expect(result.matchedTransactionIds, [original.id]);
      expect(core.transactions, hasLength(1));
      expect(core.transactions.single.amount.minorUnits, 50000);
      expect(core.transactions.single.merchantName, 'My edited name');
    },
  );
  test('one kopeck difference is not the same financial observation', () {
    final core = engine();
    notify(core);
    statement(core, [seed('bank-a', minor: 10026)]);
    expect(core.transactions, hasLength(2));
  });
  test('category monthly total is not added on top of detailed purchases', () {
    final core = engine();
    core.ingest(
      StatementAdapter(),
      StatementInput(
        entityId: 'e',
        receivedAt: day,
        rawPayload: 'synthetic total',
        batchName: 'Monthly budget',
        account: account,
        transactions: [
          TransactionSeed(
            accountId: 'a',
            amount: const Money(minorUnits: 2000000, currency: 'RUB'),
            direction: FinancialDirection.outflow,
            occurredAt: day,
            description: 'Food monthly total',
            category: 'food',
            confidence: 1,
            providerTransactionId: 'aggregate',
            tags: ['excel-period-aggregate'],
          ),
        ],
      ),
    );
    final result = core.ingest(
      BankWebAdapter(),
      StatementInput(
        entityId: 'e',
        receivedAt: day,
        rawPayload: 'synthetic purchase',
        batchName: 'Bank',
        account: account,
        transactions: [
          TransactionSeed(
            accountId: 'a',
            amount: const Money(minorUnits: 10025, currency: 'RUB'),
            direction: FinancialDirection.outflow,
            occurredAt: day,
            description: 'Shop',
            category: 'food',
            confidence: 1,
            providerTransactionId: 'purchase',
          ),
        ],
      ),
    );
    expect(result.pendingCandidateIds, hasLength(1));
    expect(core.transactions, hasLength(1));
  });
  test('a fuzzy source replay cannot revive a deleted edited operation', () {
    final core = engine();
    notify(core);
    final original = core.transactions.single;
    core.updateTransaction(
      original.copyWith(merchantName: 'Personal name'),
      actorId: 'user',
    );
    core.deleteTransaction(original.id, actorId: 'user');
    final result = statement(core, [seed('bank-a')]);
    expect(result.pendingCandidateIds, hasLength(1));
    expect(
      core.state.transactions.single.status,
      CanonicalTransactionStatus.deleted,
    );
  });
}
