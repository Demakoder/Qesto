import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/desktop/overview/desktop_overview_data.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

import 'fixtures/sample_user_financial_data.dart';

void main() {
  test('overview builds a conserved cash-flow map from canonical data', () {
    final controller = BudgetController(
      configuration: budgetConfiguration,
      financialData: sampleUserFinancialData,
    );
    final period = controller.periods.firstWhere(
      (item) => item.id == 'budget-2026-07',
    );

    final overview = DesktopOverviewData.build(controller, period);
    final flow = overview.flow!;

    expect(
      overview.income,
      controller
          .transactionsFor(period)
          .where((item) => item.type == TransactionType.income)
          .fold<int>(0, (sum, item) => sum + item.amount),
    );
    expect(
      overview.periodTransactions.where(
        (item) => item.type == TransactionType.transfer,
      ),
      isNotEmpty,
    );
    expect(
      overview.topExpenses.any((item) => item.type == TransactionType.transfer),
      isFalse,
    );
    expect(
      flow.sources.fold<int>(0, (sum, item) => sum + item.amount),
      flow.total,
    );
    expect(
      flow.branches.fold<int>(0, (sum, item) => sum + item.amount),
      flow.total,
    );
    for (final branch in flow.branches) {
      expect(
        branch.destinations.fold<int>(0, (sum, item) => sum + item.amount),
        branch.amount,
        reason: 'destinations must conserve ${branch.label}',
      );
    }
    expect(
      flow.branches.firstWhere((item) => item.id == 'savings').amount,
      15000,
    );
  });

  test('category card falls back to relative spending without budgets', () {
    final dataWithoutBudgets = sampleUserFinancialData.copyWith(
      categoryBudgets: const [],
      budgetPeriods: [
        for (final period in sampleUserFinancialData.budgetPeriods)
          BudgetPeriod(
            id: period.id,
            userId: period.userId,
            startDate: period.startDate,
            endDate: period.endDate,
            type: period.type,
            totalPlan: 0,
            currency: period.currency,
          ),
      ],
    );
    final controller = BudgetController(
      configuration: budgetConfiguration,
      financialData: dataWithoutBudgets,
    );
    final period = controller.periods.firstWhere(
      (item) => item.id == 'budget-2026-07',
    );

    final overview = DesktopOverviewData.build(controller, period);

    expect(overview.freeToSpend, isNull);
    expect(overview.categoryBudgets, isNotEmpty);
    expect(overview.categoryBudgets.every((item) => item.isRelative), isTrue);
    expect(overview.categoryBudgets.first.progress, 1);
  });

  test('overview has calm empty states instead of synthetic amounts', () {
    final emptyData = UserFinancialData(
      user: const QestoUser(
        id: 'empty',
        name: 'Пользователь',
        defaultCurrency: 'RUB',
      ),
      referenceDate: DateTime(2026, 8, 15),
    );
    final controller = BudgetController(
      configuration: budgetConfiguration,
      financialData: emptyData,
    );

    final overview = DesktopOverviewData.build(
      controller,
      controller.periods.single,
    );

    expect(overview.expenses, 0);
    expect(overview.income, 0);
    expect(overview.flow, isNull);
    expect(overview.topExpenses, isEmpty);
    expect(overview.categoryBudgets, isEmpty);
    expect(overview.plannedExpenses, isEmpty);
  });
}
