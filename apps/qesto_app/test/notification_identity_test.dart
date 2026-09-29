import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  final date = DateTime.utc(2026, 9, 6, 12);
  AndroidNotificationInput input({
    String key = 'slot',
    String package = 'bank.one',
    String account = 'A',
    int amount = 10025,
    DateTime? at,
    String raw = 'synthetic purchase balance 900',
    String category = 'food',
  }) => AndroidNotificationInput(
    entityId: 'E',
    receivedAt: date,
    rawPayload: raw,
    notificationKey: key,
    packageName: package,
    transaction: TransactionSeed(
      accountId: account,
      amount: Money(minorUnits: amount, currency: 'RUB'),
      direction: FinancialDirection.outflow,
      occurredAt: at ?? date,
      description: raw,
      merchant: 'Coffee',
      category: category,
      confidence: 1,
      providerTransactionId: key,
    ),
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
  IngestionOutcome ingest(
    SynoballCore engine,
    AndroidNotificationInput value,
  ) => engine.ingest(AndroidNotificationAdapter(history: engine.state), value);

  test('balance/category revision preserves identity and exact cents', () {
    final engine = core();
    final first = ingest(engine, input());
    final replay = ingest(
      engine,
      input(raw: 'updated balance 500', category: 'cafe'),
    );
    expect(replay.matchedTransactionIds, first.createdTransactionIds);
    expect(engine.transactions, hasLength(1));
    expect(engine.transactions.single.amount.minorUnits, 10025);
  });

  test('reused OS key cannot overwrite purchase; review is retryable', () {
    final engine = core();
    ingest(engine, input());
    final value = input(amount: 20050, at: date.add(const Duration(hours: 1)));
    final second = ingest(engine, value);
    expect(second.pendingCandidateIds, hasLength(1));
    expect(engine.transactions.single.amount.minorUnits, 10025);
    final retry = ingest(engine, value);
    expect(retry.pendingCandidateIds, second.pendingCandidateIds);
    expect(engine.state.candidates, hasLength(2));
    final target = engine.confirmCandidate(
      second.pendingCandidateIds.single,
      actorId: 'user',
    );
    expect(engine.transactions, hasLength(2));
    expect(engine.transactionById(target)!.amount.minorUnits, 20050);
    expect(ingest(engine, value).matchedTransactionIds, [target]);
    expect(engine.transactions, hasLength(2));
  });

  test('unchanged content with a changed posting time needs review', () {
    final engine = core();
    ingest(engine, input());
    final result = ingest(
      engine,
      input(at: date.add(const Duration(seconds: 1))),
    );
    expect(result.pendingCandidateIds, hasLength(1));
    expect(engine.transactions, hasLength(1));
  });

  test('identical purchases with distinct native keys remain distinct', () {
    final engine = core();
    ingest(engine, input(key: 'one'));
    ingest(engine, input(key: 'two'));
    expect(engine.transactions, hasLength(2));
  });

  test('package and account scope separate identical native keys', () {
    final engine = core();
    ingest(engine, input());
    expect(
      ingest(engine, input(package: 'bank.two')).createdTransactionIds,
      hasLength(1),
    );
    expect(
      ingest(engine, input(account: 'B')).createdTransactionIds,
      hasLength(1),
    );
    expect(engine.transactions, hasLength(3));
  });

  for (final deleted in [false, true]) {
    test(
      'legacy evidence aliases the original canonical ID (deleted=$deleted)',
      () {
        final engine = core();
        final original = engine.ingest(_LegacyNotificationAdapter(), input());
        final id = original.createdTransactionIds.single;
        if (deleted) engine.deleteTransaction(id, actorId: 'user');
        final replay = ingest(engine, input(raw: 'updated balance'));
        expect(replay.resolvedTransactionIds, [id]);
        expect(replay.createdTransactionIds, isEmpty);
        expect(engine.state.transactions, hasLength(1));
        expect(
          engine.state.evidence.map((e) => e.providerTransactionId),
          containsAll(['slot', startsWith('notification-v2-')]),
        );
        if (deleted) expect(replay.suppressedTransactionIds, [id]);
      },
    );
  }

  test(
    'legacy key reused for a different amount requires review, not alias',
    () {
      final engine = core();
      engine.ingest(_LegacyNotificationAdapter(), input());
      final outcome = ingest(engine, input(amount: 75000));
      expect(outcome.pendingCandidateIds, hasLength(1));
      expect(engine.transactions.single.amount.minorUnits, 10025);
    },
  );

  test('SMS adapter also separates transport key from economic identity', () {
    final engine = core();
    IngestionOutcome sms(int amount) => engine.ingest(
      SmsNotificationAdapter(history: engine.state),
      SmsNotificationInput(
        entityId: 'E',
        receivedAt: date,
        rawPayload: 'synthetic sms',
        notificationKey: 'sms-slot',
        packageName: 'sms.app',
        sender: '900',
        transaction: input(amount: amount).transaction,
      ),
    );
    expect(sms(10025).createdTransactionIds, hasLength(1));
    expect(sms(10025).matchedTransactionIds, hasLength(1));
    expect(sms(20000).pendingCandidateIds, hasLength(1));
    expect(engine.transactions.single.amount.minorUnits, 10025);
  });
}

/// Reproduce the persisted v1 adapter, without keeping it in production code.
class _LegacyNotificationAdapter extends AndroidNotificationAdapter {
  @override
  String get version => '1.0.0';
  @override
  List<TransactionSeed> seeds(AndroidNotificationInput input) => [
    input.transaction,
  ];
}
