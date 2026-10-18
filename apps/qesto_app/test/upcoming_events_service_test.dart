import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/services/upcoming_events_service.dart';
import 'package:qesto/synoball/core/models.dart';

void main() {
  const service = UpcomingEventsService();
  final today = DateTime(2026, 9, 30);

  UpcomingExpense manual({
    String id = 'manual',
    String title = 'Playerok',
    int amount = 3000,
    DateTime? date,
    String? rule,
    String userId = 'u',
    bool cancelled = false,
  }) => UpcomingExpense(
    id: id,
    userId: userId,
    budgetPeriodId: 'october',
    title: title,
    amount: amount,
    currency: 'RUB',
    plannedDate: date ?? DateTime(2026, 10, 15),
    isRecurring: rule != null,
    recurrenceRule: rule,
    source: UpcomingExpenseSource.manual,
    isCancelled: cancelled,
  );

  RecurringStream stream({
    String title = 'Яндекс Плюс',
    String merchantKey = 'яндекс плюс',
    DateTime? date,
    int amount = 39900,
    int observations = 4,
    String userId = 'u',
  }) => RecurringStream(
    id: 'rec-$title',
    entityId: 'ent-$userId',
    merchantKey: merchantKey,
    title: title,
    typicalAmount: Money(minorUnits: amount, currency: 'RUB'),
    frequency: RecurrenceFrequency.monthly,
    nextExpectedAt: date ?? DateTime(2026, 10, 3),
    confidence: observations >= 3 ? 0.9 : 0.7,
    transactionIds: [for (var i = 0; i < observations; i++) 'tx-$i'],
  );

  DebtAccount debt({
    DateTime? date,
    int? amount = 10000,
    DebtStatus status = DebtStatus.active,
    String userId = 'u',
    int balance = 30000,
  }) => DebtAccount(
    id: 'debt-1',
    userId: userId,
    name: 'Вернуть Андрею',
    type: DebtType.personalLoan,
    currency: 'RUB',
    currentBalance: balance,
    status: status,
    source: DebtSource.manual,
    dataQuality: DebtDataQuality.manual,
    confidence: 1,
    createdAt: today,
    updatedAt: today,
    monthlyPayment: amount,
    nextPaymentDate: date,
  );

  CanonicalTransaction observed(int index, int minorUnits) =>
      CanonicalTransaction(
        id: 'tx-$index',
        entityId: 'ent-u',
        accountId: 'account-u',
        status: CanonicalTransactionStatus.posted,
        amount: Money(minorUnits: minorUnits, currency: 'RUB'),
        direction: FinancialDirection.outflow,
        occurredAt: DateTime(2026, index + 1, 3),
        rawDescription: 'Яндекс Плюс',
        normalizedDescription: 'яндекс плюс',
        eventType: FinancialEventType.observed,
        createdAt: today,
        updatedAt: today,
        fieldTrust: SourceTrustLevel.bankStatement,
      );

  test('one timeline from manual, inferred and debt; only regular in KPI', () {
    final result = service.build(
      userId: 'u',
      asOf: today,
      streams: [stream()],
      manualExpenses: [
        manual(),
        manual(
          id: 'internet',
          title: 'Интернет',
          amount: 900,
          date: DateTime(2026, 10, 20),
          rule: 'monthly',
        ),
      ],
      debts: [debt(date: DateTime(2026, 10, 8))],
    );
    expect(result.upcoming.map((event) => event.origin), [
      UpcomingEventOrigin.inferredRecurring,
      UpcomingEventOrigin.debt,
      UpcomingEventOrigin.manualOneTime,
      UpcomingEventOrigin.manualRecurring,
    ]);
    expect(result.nextEvent!.title, 'Яндекс Плюс');
    expect(result.monthlyRegularByCurrency['RUB'], 1299);
    expect(result.detectedStreamCount, 1);
  });

  test(
    'fixed inferred payment is exact, varying amount is marked estimate',
    () {
      UpcomingEventsSnapshot project(List<int> minorUnits) => service.build(
        userId: 'u',
        asOf: today,
        streams: [stream(observations: minorUnits.length)],
        transactions: [
          for (var i = 0; i < minorUnits.length; i++)
            observed(i, minorUnits[i]),
        ],
        manualExpenses: const [],
        debts: const [],
      );
      expect(
        project([39900, 39900, 39900]).upcoming.single.isEstimate,
        isFalse,
      );
      expect(project([39900, 44900, 42900]).upcoming.single.isEstimate, isTrue);
    },
  );

  test('manual recurrence keeps its original calendar anchor', () {
    final result = service.build(
      userId: 'u',
      asOf: DateTime(2026, 3, 1),
      streams: const [],
      manualExpenses: [manual(date: DateTime(2026, 1, 31), rule: 'monthly')],
      debts: const [],
    );
    expect(result.upcoming.single.date, DateTime(2026, 3, 31));
    expect(result.overdue, isEmpty);
  });

  test('an old weekly plan advances without a fixed cycle limit', () {
    final result = service.build(
      userId: 'u',
      asOf: today,
      streams: const [],
      manualExpenses: [manual(date: DateTime(1975, 1, 1), rule: 'weekly')],
      debts: const [],
    );
    final next = result.upcoming.single.date;
    expect(next.isBefore(today), isFalse);
    expect(next.isBefore(today.add(const Duration(days: 7))), isTrue);
  });

  test('past one-time plan is overdue, never an observed transaction', () {
    final item = manual(date: DateTime(2026, 9, 20));
    final data = UserFinancialData(
      user: const QestoUser(id: 'u', name: 'User', defaultCurrency: 'RUB'),
      referenceDate: today,
      upcomingExpenses: [item],
      transactions: const [],
    );
    const codec = UserFinancialDataCodec();
    final restored = codec.decode(codec.encode(data));
    expect(restored.transactions, isEmpty);
    final result = service.build(
      userId: 'u',
      asOf: today,
      streams: const [],
      manualExpenses: restored.upcomingExpenses,
      debts: const [],
    );
    expect(result.upcoming, isEmpty);
    expect(result.overdue.single.isOverdue, isTrue);
    expect(restored.upcomingExpenses.single.id, item.id);
  });

  test('manual data suppresses an obvious inferred duplicate', () {
    final result = service.build(
      userId: 'u',
      asOf: today,
      streams: [stream()],
      manualExpenses: [
        manual(
          title: 'YANDEX*PLUS',
          amount: 450,
          date: DateTime(2026, 10, 4),
          rule: 'monthly',
        ),
      ],
      debts: const [],
    );
    expect(result.upcoming, hasLength(1));
    expect(result.upcoming.single.origin, UpcomingEventOrigin.manualRecurring);
    expect(result.monthlyRegularByCurrency['RUB'], 450);
    expect(result.detectedStreamCount, 1);
  });

  test('debt view changes with its source and disappears when closed', () {
    UpcomingEventsSnapshot query(DebtAccount value) => service.build(
      userId: 'u',
      asOf: today,
      streams: const [],
      manualExpenses: const [],
      debts: [value],
    );
    final original = debt(date: DateTime(2026, 10, 15));
    expect(query(original).upcoming.single.amount, 10000);
    final changed = original.copyWith(
      nextPaymentDate: DateTime(2026, 10, 20),
      monthlyPayment: 8000,
    );
    expect(query(changed).upcoming.single.date, DateTime(2026, 10, 20));
    expect(query(changed).upcoming.single.amount, 8000);
    expect(
      query(changed.copyWith(status: DebtStatus.closed)).upcoming,
      isEmpty,
    );
    expect(
      query(debt(amount: null, date: DateTime(2026, 10, 15))).upcoming,
      isEmpty,
    );
    expect(query(debt(date: null)).upcoming, isEmpty);
    expect(
      query(debt(date: DateTime(2026, 10, 15), balance: 0)).upcoming,
      isEmpty,
    );
  });

  test('ownership, cancellation and tentative streams are isolated', () {
    final result = service.build(
      userId: 'u',
      asOf: today,
      streams: [
        stream(observations: 2),
        stream(userId: 'other'),
      ],
      manualExpenses: [
        manual(userId: 'other'),
        manual(cancelled: true),
      ],
      debts: [debt(date: DateTime(2026, 10, 2), userId: 'other')],
    );
    expect(result.upcoming, isEmpty);
    expect(result.monthlyRegularByCurrency, isEmpty);
    expect(result.tentativeStreams, hasLength(1));
  });

  test('stale inferred stream is not advanced indefinitely', () {
    final result = service.build(
      userId: 'u',
      asOf: today,
      streams: [stream(date: DateTime(2026, 4, 3))],
      manualExpenses: const [],
      debts: const [],
    );
    expect(result.upcoming, isEmpty);
    expect(result.monthlyRegularByCurrency, isEmpty);
  });

  test(
    'legacy saved subscription remains visible without a Synoball stream',
    () {
      final legacy = UpcomingExpense(
        id: 'old-subscription',
        userId: 'u',
        budgetPeriodId: 'old-period',
        title: 'Spotify',
        amount: 299,
        currency: 'RUB',
        plannedDate: DateTime(2026, 7, 22),
        isRecurring: true,
        recurrenceRule: 'monthly',
        source: UpcomingExpenseSource.subscription,
      );
      final result = service.build(
        userId: 'u',
        asOf: today,
        streams: const [],
        manualExpenses: [legacy],
        debts: const [],
      );
      expect(result.upcoming.single.title, 'Spotify');
      expect(result.upcoming.single.date, DateTime(2026, 10, 22));
      expect(result.monthlyRegularByCurrency['RUB'], 299);
      expect(result.detectedStreamCount, 1);
    },
  );
}
