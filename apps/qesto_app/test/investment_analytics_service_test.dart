import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/capital/domain/investment_analytics_service.dart';

void main() {
  const service = InvestmentAnalyticsService();
  final asOf = DateTime(2026, 9, 2);

  InvestmentAccount account({
    required String id,
    required int balance,
    String currency = 'RUB',
    InvestmentPlan? plan,
    DateTime? updatedAt,
  }) => InvestmentAccount(
    id: id,
    userId: 'user-1',
    linkedAccountId: 'linked-$id',
    name: id,
    type: InvestmentAccountType.brokerage,
    currency: currency,
    currentBalance: balance,
    status: InvestmentAccountStatus.active,
    source: InvestmentDataSource.manual,
    createdAt: DateTime(2026, 6, 1),
    updatedAt: updatedAt ?? asOf,
    lastBalanceUpdateAt: updatedAt ?? asOf,
    plan: plan,
  );

  test('separates value change from contributions and calculates plan', () {
    final investment = account(
      id: 'broker',
      balance: 155000,
      plan: const InvestmentPlan(amount: 20000),
    );
    final result = service.calculate(
      accounts: [investment],
      balanceSnapshots: [
        InvestmentBalanceSnapshot(
          id: 's1',
          investmentAccountId: investment.id,
          date: DateTime(2026, 7, 1),
          balance: 100000,
          currency: 'RUB',
          source: InvestmentDataSource.manual,
          createdAt: DateTime(2026, 7, 1),
        ),
        InvestmentBalanceSnapshot(
          id: 's2',
          investmentAccountId: investment.id,
          date: asOf,
          balance: 155000,
          currency: 'RUB',
          source: InvestmentDataSource.manual,
          createdAt: asOf,
        ),
      ],
      contributions: [
        InvestmentContribution(
          id: 'c1',
          investmentAccountId: investment.id,
          date: DateTime(2026, 9, 1),
          amount: 20000,
          currency: 'RUB',
          type: InvestmentContributionType.contribution,
          source: InvestmentDataSource.manual,
          createdAt: DateTime(2026, 9, 1),
        ),
      ],
      asOf: asOf,
      period: InvestmentPeriod.threeMonths,
      baseCurrency: 'RUB',
    );

    expect(result.totalBalance, 155000);
    expect(result.change, 55000);
    expect(result.investedThisMonth, 20000);
    expect(result.monthlyPlanProgress, 1);
    expect(result.accounts.single.differenceFromRecordedFlows, 35000);
  });

  test('marks old manual balances as stale', () {
    final stale = account(
      id: 'old',
      balance: 10000,
      updatedAt: DateTime(2026, 7, 1),
    );
    expect(service.freshness(stale, asOf), InvestmentFreshness.stale);
  });
}
