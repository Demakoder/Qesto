import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/capital/domain/debt_analytics_service.dart';

void main() {
  const service = DebtAnalyticsService();
  final asOf = DateTime(2026, 9, 2);

  DebtAccount debt({
    required String id,
    required DebtType type,
    required int balance,
    int? monthlyPayment,
    double? rate,
    DateTime? nextPaymentDate,
    CreditCardDebtDetails? card,
    DebtStatus status = DebtStatus.active,
  }) => DebtAccount(
    id: id,
    userId: 'user-1',
    name: id,
    type: type,
    currency: 'RUB',
    currentBalance: balance,
    monthlyPayment: monthlyPayment,
    interestRate: rate,
    nextPaymentDate: nextPaymentDate,
    creditCardDetails: card,
    status: status,
    source: DebtSource.manual,
    dataQuality: DebtDataQuality.manual,
    confidence: 1,
    createdAt: DateTime(2026),
    updatedAt: asOf,
  );

  DebtBalanceSnapshot snapshot(String debtId, DateTime date, int balance) =>
      DebtBalanceSnapshot(
        id: '$debtId-${date.toIso8601String()}',
        debtId: debtId,
        date: date,
        totalBalance: balance,
        source: DebtSource.manual,
        confidence: 1,
      );

  test('aggregates active debts, real trend, structure and next payments', () {
    final mortgage = debt(
      id: 'mortgage',
      type: DebtType.mortgage,
      balance: 800000,
      monthlyPayment: 25000,
      rate: 12,
      nextPaymentDate: DateTime(2026, 9, 10),
    );
    final card = debt(
      id: 'card',
      type: DebtType.creditCard,
      balance: 100000,
      card: CreditCardDebtDetails(
        creditLimit: 200000,
        minimumPayment: 5000,
        graceDeadline: DateTime(2026, 9, 20),
        interestRateAfterGrace: 29.9,
      ),
    );
    final closed = debt(
      id: 'closed',
      type: DebtType.other,
      balance: 40000,
      status: DebtStatus.closed,
    );

    final result = service.calculate(
      debts: [mortgage, card, closed],
      balanceSnapshots: [
        snapshot('mortgage', DateTime(2026, 7), 850000),
        snapshot('card', DateTime(2026, 7), 120000),
        snapshot('mortgage', DateTime(2026, 8), 820000),
        snapshot('card', DateTime(2026, 8), 110000),
      ],
      debtPayments: const [],
      transactions: const [],
      asOf: asOf,
      period: DebtAnalyticsPeriod.threeMonths,
      baseCurrency: 'RUB',
    );

    expect(result.totalDebt, 900000);
    expect(result.change, -70000);
    expect(result.securedDebt, 800000);
    expect(result.creditCardDebt, 100000);
    expect(result.monthlyDebtPayments, 30000);
    expect(result.debtPaymentToIncomeRatio, isNull);
    expect(result.nextPayments.map((item) => item.debtId), [
      'mortgage',
      'card',
    ]);
    expect(result.debts.last.utilization, 0.5);
    expect(result.structure, hasLength(2));
  });

  test('does not invent a trend or interest for missing source data', () {
    final unknown = debt(
      id: 'manual',
      type: DebtType.personalLoan,
      balance: 50000,
      monthlyPayment: 5000,
    );
    final result = service.calculate(
      debts: [unknown],
      balanceSnapshots: const [],
      debtPayments: const [],
      transactions: const [],
      asOf: asOf,
      period: DebtAnalyticsPeriod.oneYear,
      baseCurrency: 'RUB',
    );

    expect(result.trend, hasLength(1));
    expect(result.change, isNull);
    expect(result.monthlyInterestCost, isNull);
    expect(result.weightedAverageInterestRate, isNull);
  });

  test('extra and one-time prepayments shorten a modelled loan', () {
    final loan = debt(
      id: 'loan',
      type: DebtType.personalLoan,
      balance: 240000,
      monthlyPayment: 22000,
      rate: 18,
    );
    final baseline = service.projectedPayoffDate(loan, asOf: asOf)!;
    final extra = service.simulateExtraMonthlyPayment(
      loan,
      asOf: asOf,
      extraMonthlyPayment: 10000,
    )!;
    final oneTime = service.simulateOneTimePrepayment(
      loan,
      asOf: asOf,
      amount: 100000,
    )!;

    expect(extra.months, lessThan(baseline.months));
    expect(extra.interestSaved, greaterThan(0));
    expect(oneTime.reduceTerm.months, lessThan(baseline.months));
    expect(oneTime.reducePayment.monthlyPayment, lessThan(22000));
  });
}
