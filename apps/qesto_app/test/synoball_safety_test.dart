import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  final date = DateTime(2026, 9, 6, 12);
  TransactionSeed seed(
    String id,
    String account, {
    List<String> tags = const [],
  }) => TransactionSeed(
    accountId: account,
    amount: const Money(minorUnits: 10025, currency: 'RUB'),
    direction: FinancialDirection.outflow,
    occurredAt: date,
    description: 'Coffee',
    merchant: 'Coffee',
    providerTransactionId: id,
    confidence: 1,
    tags: tags,
  );
  SynoballCore core() => SynoballCore(
    initialState: SynoballState(
      accounts: [
        for (final id in ['A', 'B'])
          SynoballAccount(
            id: id,
            entityId: 'E',
            name: id,
            type: SynoballAccountType.checking,
            currency: 'RUB',
            balance: const Money(minorUnits: 0, currency: 'RUB'),
          ),
      ],
    ),
  );
  IngestionOutcome notification(SynoballCore core, String id, String account) =>
      core.ingest(
        AndroidNotificationAdapter(),
        AndroidNotificationInput(
          entityId: 'E',
          receivedAt: date,
          rawPayload: 'synthetic',
          packageName: 'test.bank',
          notificationKey: id,
          transaction: seed(id, account),
        ),
      );
  IngestionOutcome statement(
    SynoballCore core,
    String id,
    String account, {
    List<String> tags = const [],
    DateTime? receivedAt,
  }) => core.ingest(
    StatementAdapter(),
    StatementInput(
      entityId: 'E',
      receivedAt: receivedAt ?? date,
      rawPayload: 'synthetic',
      batchName: 'test',
      transactions: [seed(id, account, tags: tags)],
      account: core.state.accounts.firstWhere((item) => item.id == account),
    ),
  );

  test('different known accounts never fuzzy merge', () {
    final engine = core();
    notification(engine, 'n1', 'A');
    statement(engine, 'd1', 'B');
    expect(engine.transactions, hasLength(2));
  });
  test(
    'posted lifecycle survives stale pending/cancelled and evidence versions are retained',
    () {
      final engine = core();
      statement(engine, 'provider', 'A', tags: ['status-pending']);
      statement(
        engine,
        'provider',
        'A',
        tags: ['status-posted'],
        receivedAt: date.add(const Duration(days: 1)),
      );
      expect(engine.state.evidence, hasLength(2));
      statement(
        engine,
        'provider',
        'A',
        tags: ['status-posted'],
        receivedAt: date.add(const Duration(days: 2)),
      );
      expect(engine.state.evidence, hasLength(2));
      statement(
        engine,
        'provider',
        'A',
        tags: ['status-cancelled'],
        receivedAt: date.add(const Duration(hours: 30)),
      );
      expect(
        engine.transactions.single.status,
        CanonicalTransactionStatus.posted,
      );
      statement(
        engine,
        'provider',
        'A',
        tags: ['status-pending'],
        receivedAt: date.add(const Duration(days: 3)),
      );
      expect(
        engine.transactions.single.status,
        CanonicalTransactionStatus.posted,
      );
      expect(engine.transactions.single.tags, contains('status-posted'));
      expect(
        engine.transactions.single.tags,
        isNot(contains('status-pending')),
      );
    },
  );
  test(
    'same bank provider string in different connections remains distinct',
    () {
      final engine = core();
      for (final connection in ['C1', 'C2']) {
        engine.ingest(
          AndroidNotificationAdapter(),
          AndroidNotificationInput(
            entityId: 'E',
            receivedAt: date,
            rawPayload: 'synthetic',
            notificationKey: 'same',
            packageName: 'test.bank',
            connectionId: connection,
            transaction: seed('same', 'A'),
          ),
        );
      }
      expect(engine.transactions, hasLength(2));
    },
  );
  test('money rejects lossy extra decimal places', () {
    expect(
      () => Money.fromJson({'value': '100.255', 'currency': 'RUB'}),
      throwsFormatException,
    );
    expect(
      Money.fromJson({'value': '-0.25', 'currency': 'RUB'}).minorUnits,
      -25,
    );
  });
  test('provider identity is scoped by account', () {
    final engine = core();
    statement(engine, 'provider-1', 'A');
    statement(engine, 'provider-1', 'B');
    expect(engine.transactions, hasLength(2));
  });
  test('equal plausible matches remain pending, not first-match wins', () {
    final engine = core();
    notification(engine, 'n1', 'A');
    notification(engine, 'n2', 'A');
    final result = statement(engine, 'd1', 'A');
    expect(result.matchedTransactionIds, isEmpty);
    expect(result.pendingCandidateIds, hasLength(1));
    expect(engine.transactions, hasLength(2));
  });
}
