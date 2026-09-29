import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/desktop/overview/desktop_overview_data.dart';
import 'package:qesto/features/budget/services/cash_flow_calculation_service.dart';
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

    expect(overview.income, controller.cashFlowFor(period).externalInflows);
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

  test(
    'overview distinguishes a real Other category from grouped expenses',
    () {
      final period = BudgetPeriod(
        id: 'budget-2026-09',
        userId: 'user',
        startDate: DateTime(2026, 9),
        endDate: DateTime(2026, 9, 30),
        type: BudgetPeriodType.calendarMonth,
        totalPlan: 0,
        currency: 'RUB',
      );
      final categories = <BudgetCategory>[
        for (var index = 0; index < 5; index++)
          BudgetCategory(
            id: index == 0 ? 'other' : 'category-$index',
            name: index == 0 ? 'Другое' : 'Категория $index',
            iconKey: 'other',
            colorValue: 0xFF8A8F9C,
          ),
        const BudgetCategory(
          id: 'sport',
          name: 'Спорт',
          iconKey: 'sport',
          colorValue: 0xFF3478F6,
        ),
      ];
      final controller = BudgetController(
        configuration: BudgetConfiguration(categories: categories),
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'user',
            name: 'Тест',
            defaultCurrency: 'RUB',
          ),
          referenceDate: DateTime(2026, 9, 28),
          accounts: const [
            QestoAccount(
              id: 'card',
              userId: 'user',
              title: 'Карта',
              balance: 100000,
              currency: 'RUB',
              type: AccountType.bankCard,
            ),
          ],
          budgetPeriods: [period],
          transactions: [
            BudgetTransaction(
              id: 'income',
              userId: 'user',
              accountId: 'card',
              date: DateTime(2026, 9, 1),
              amount: 100000,
              currency: 'RUB',
              type: TransactionType.income,
              title: 'Доход',
            ),
            for (var index = 0; index < 6; index++)
              BudgetTransaction(
                id: 'expense-$index',
                userId: 'user',
                accountId: 'card',
                date: DateTime(2026, 9, 2 + index),
                amount: index == 5 ? 3100 : 12000 - index * 1000,
                currency: 'RUB',
                type: TransactionType.expense,
                categoryId: index == 5
                    ? 'sport'
                    : index == 0
                    ? 'other'
                    : 'category-$index',
                title: index == 5 ? 'DDX' : 'Покупка $index',
              ),
          ],
        ),
      );

      final compact = DesktopOverviewData.build(controller, period).flow!;
      expect(compact.branches.map((item) => item.label), contains('Другое'));
      final grouped = compact.branches.singleWhere(
        (item) => item.id == '__other_expenses_aggregate',
      );
      expect(grouped.label, 'Другие расходы');
      expect(grouped.amount, 3100 + 8000);

      final full = DesktopOverviewData.build(
        controller,
        period,
        flowCategoryLimit: null,
      ).flow!;
      expect(
        full.branches.where((item) => item.id == 'sport').single.amount,
        3100,
      );
      expect(
        full.branches.any((item) => item.id == '__other_expenses_aggregate'),
        isFalse,
      );
    },
  );

  test(
    'external person transfers are expenses and remaining income is not a category',
    () {
      final period = BudgetPeriod(
        id: 'budget-2026-08',
        userId: 'user',
        startDate: DateTime(2026, 8),
        endDate: DateTime(2026, 8, 31),
        type: BudgetPeriodType.calendarMonth,
        totalPlan: 0,
        currency: 'RUB',
      );
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'user',
            name: 'Пользователь',
            defaultCurrency: 'RUB',
          ),
          referenceDate: DateTime(2026, 8, 31),
          accounts: const [
            QestoAccount(
              id: 'card',
              userId: 'user',
              title: 'Карта',
              balance: 6000,
              currency: 'RUB',
              type: AccountType.bankCard,
            ),
          ],
          budgetPeriods: [period],
          transactions: [
            BudgetTransaction(
              id: 'income',
              userId: 'user',
              accountId: 'card',
              date: DateTime(2026, 8, 5),
              amount: 10000,
              currency: 'RUB',
              type: TransactionType.income,
              categoryId: 'business',
              title: 'Перевод от Софьи',
            ),
            BudgetTransaction(
              id: 'external-transfer',
              userId: 'user',
              accountId: 'card',
              date: DateTime(2026, 8, 6),
              amount: 4000,
              currency: 'RUB',
              type: TransactionType.transfer,
              categoryId: 'other',
              title: 'Перевод Дмитрию',
              transferDirection: TransferDirection.outgoing,
              tags: const [qestoExternalTransferTag],
            ),
            BudgetTransaction(
              id: 'own-transfer',
              userId: 'user',
              accountId: 'card',
              date: DateTime(2026, 8, 7),
              amount: 2000,
              currency: 'RUB',
              type: TransactionType.transfer,
              categoryId: 'other',
              title: 'Между своими счетами',
              transferDirection: TransferDirection.outgoing,
              tags: const [qestoInternalTransferTag],
            ),
          ],
        ),
      );

      final overview = DesktopOverviewData.build(controller, period);

      expect(overview.income, 10000);
      expect(overview.expenses, 4000);
      expect(overview.cashFlow, 6000);
      expect(
        overview.topExpenses.map((item) => item.id),
        contains('external-transfer'),
      );
      expect(
        overview.topExpenses.map((item) => item.id),
        isNot(contains('own-transfer')),
      );
      expect(
        overview.flow!.branches.map((item) => item.label),
        isNot(contains('Положительный cash-flow')),
      );
      expect(
        overview.flow!.branches
            .firstWhere((item) => item.id == 'remaining-income')
            .amount,
        6000,
      );
    },
  );

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
