import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/budget/services/cash_flow_calculation_service.dart';
import '../desktop_financial_helpers.dart';

enum OverviewPrimaryMetric { expenses, income }

enum OverviewCapitalMetric { capital, investments, savings }

enum OverviewTrendGranularity { days, weeks }

enum OverviewTransactionSort {
  dateDescending,
  dateAscending,
  amountDescending,
  amountAscending,
}

class DesktopOverviewData {
  const DesktopOverviewData({
    required this.period,
    required this.currency,
    required this.expenses,
    required this.income,
    required this.cashFlow,
    required this.capital,
    required this.investments,
    required this.savings,
    required this.freeToSpend,
    required this.hasBudget,
    required this.trend,
    required this.flow,
    required this.topExpenses,
    required this.categoryBudgets,
    required this.plannedExpenses,
    required this.periodTransactions,
  });

  final BudgetPeriod period;
  final String currency;
  final int expenses;
  final int income;
  final int cashFlow;
  final int capital;
  final int investments;
  final int savings;
  final int? freeToSpend;
  final bool hasBudget;
  final List<OverviewTrendPoint> trend;
  final OverviewFlowData? flow;
  final List<BudgetTransaction> topExpenses;
  final List<OverviewCategoryBudgetRow> categoryBudgets;
  final List<UpcomingExpense> plannedExpenses;
  final List<BudgetTransaction> periodTransactions;

  factory DesktopOverviewData.build(
    BudgetController controller,
    BudgetPeriod period, {
    int? flowCategoryLimit = 4,
  }) {
    final transactions = controller.transactionsFor(period);
    final summary = controller.summaryFor(period);
    final expenses = math.max(0, summary.currentExpense);
    final cashFlow = controller.cashFlowFor(period);
    final income = cashFlow.externalInflows;
    final state = controller.financialState;
    final capital =
        (state.assets.minorUnits - state.debts.minorUnits).round() ~/ 100;
    final investments = state.investments.minorUnits.round() ~/ 100;
    final savings = controller.accounts
        .where(
          (account) =>
              account.type == AccountType.savings ||
              account.type == AccountType.deposit,
        )
        .fold<int>(0, (sum, account) => sum + account.balance);
    final categorySpending = _categorySpending(controller, transactions);
    final topExpenses =
        transactions
            .where(
              (item) =>
                  controller.calculationService.isConsumerTransaction(item) &&
                  controller.calculationService.signedExpense(item) > 0,
            )
            .toList(growable: false)
          ..sort((left, right) => right.amount.compareTo(left.amount));
    final recent = transactions.toList(growable: false)
      ..sort((left, right) {
        final byDate = right.date.compareTo(left.date);
        return byDate != 0 ? byDate : right.id.compareTo(left.id);
      });
    final planningAnchor = controller.activeDateFor(period);
    final planned =
        controller.upcomingExpenses
            .where(
              (item) =>
                  !item.isCancelled &&
                  !item.plannedDate.isBefore(planningAnchor),
            )
            .toList(growable: false)
          ..sort(
            (left, right) => left.plannedDate.compareTo(right.plannedDate),
          );

    return DesktopOverviewData(
      period: period,
      currency: period.currency,
      expenses: expenses,
      income: income,
      cashFlow: cashFlow.netCashFlow,
      capital: capital,
      investments: investments,
      savings: savings,
      freeToSpend: period.hasAssignedBudget
          ? period.totalPlan - summary.currentExpense
          : null,
      hasBudget: period.hasAssignedBudget,
      trend: _expenseTrend(controller, period, transactions),
      flow: _flowData(
        controller: controller,
        transactions: transactions,
        income: income,
        expenses: expenses,
        currency: period.currency,
        categorySpending: categorySpending,
        categoryLimit: flowCategoryLimit,
      ),
      topExpenses: topExpenses.take(5).toList(growable: false),
      categoryBudgets: _categoryBudgets(controller, period, categorySpending),
      plannedExpenses: planned.take(5).toList(growable: false),
      periodTransactions: recent,
    );
  }

  static List<OverviewTrendPoint> _expenseTrend(
    BudgetController controller,
    BudgetPeriod period,
    List<BudgetTransaction> transactions,
  ) {
    final daily = <DateTime, int>{};
    for (final transaction in transactions) {
      if (!controller.calculationService.isConsumerTransaction(transaction)) {
        continue;
      }
      final amount = controller.calculationService.signedExpense(transaction);
      if (amount == 0) continue;
      final date = DateTime(
        transaction.date.year,
        transaction.date.month,
        transaction.date.day,
      );
      daily.update(date, (value) => value + amount, ifAbsent: () => amount);
    }
    final end = controller.activeDateFor(period);
    var cumulative = 0;
    final result = <OverviewTrendPoint>[];
    for (
      var day = period.startDate;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      cumulative = math.max(0, cumulative + (daily[day] ?? 0));
      result.add(OverviewTrendPoint(date: day, amount: cumulative));
    }
    return result;
  }

  static List<OverviewCategorySpend> _categorySpending(
    BudgetController controller,
    List<BudgetTransaction> transactions,
  ) {
    final amounts = <String, int>{};
    for (final transaction in transactions) {
      if (!controller.calculationService.isConsumerTransaction(transaction)) {
        continue;
      }
      final amount = controller.calculationService.signedExpense(transaction);
      if (amount == 0) continue;
      final id = transaction.categoryId ?? 'uncategorized';
      amounts.update(id, (value) => value + amount, ifAbsent: () => amount);
    }
    final categories = <OverviewCategorySpend>[];
    for (final entry in amounts.entries.where((item) => item.value > 0)) {
      final category = controller.categories
          .where((item) => item.id == entry.key)
          .firstOrNull;
      categories.add(
        OverviewCategorySpend(
          id: entry.key,
          name:
              category?.shortName ??
              category?.name ??
              _fallbackCategory(entry.key),
          amount: entry.value,
          iconKey: category?.iconKey ?? 'category',
          color: category == null
              ? QestoColors.secondaryText
              : Color(category.colorValue),
          transactions: transactions
              .where(
                (item) =>
                    (item.categoryId ?? 'uncategorized') == entry.key &&
                    controller.calculationService.isConsumerTransaction(item) &&
                    controller.calculationService.signedExpense(item) > 0,
              )
              .toList(growable: false),
        ),
      );
    }
    categories.sort((left, right) => right.amount.compareTo(left.amount));
    return categories;
  }

  static List<OverviewCategoryBudgetRow> _categoryBudgets(
    BudgetController controller,
    BudgetPeriod period,
    List<OverviewCategorySpend> spending,
  ) {
    final plans = controller.categoryPlansFor(period);
    final hasPlans = plans.any((item) => item.hasAssignedBudget);
    if (hasPlans) {
      final rows =
          plans
              .where((item) => item.hasAssignedBudget)
              .map(
                (item) => OverviewCategoryBudgetRow(
                  id: item.category.id,
                  name: item.category.shortName ?? item.category.name,
                  iconKey: item.category.iconKey,
                  color: Color(item.category.colorValue),
                  spent: item.spentAmount,
                  progress: item.progress,
                  isRelative: false,
                ),
              )
              .toList(growable: false)
            ..sort((left, right) {
              final bySpent = right.spent.compareTo(left.spent);
              return bySpent != 0
                  ? bySpent
                  : right.progress.compareTo(left.progress);
            });
      return rows.take(5).toList(growable: false);
    }
    final largest = spending.firstOrNull?.amount ?? 0;
    return spending
        .take(5)
        .map(
          (item) => OverviewCategoryBudgetRow(
            id: item.id,
            name: item.name,
            iconKey: item.iconKey,
            color: item.color,
            spent: item.amount,
            progress: largest == 0 ? 0 : item.amount / largest,
            isRelative: true,
          ),
        )
        .toList(growable: false);
  }

  static OverviewFlowData? _flowData({
    required BudgetController controller,
    required List<BudgetTransaction> transactions,
    required int income,
    required int expenses,
    required String currency,
    required List<OverviewCategorySpend> categorySpending,
    required int? categoryLimit,
  }) {
    if (income <= 0) return null;

    final incomeGroups = <String, int>{};
    for (final transaction in transactions.where(
      (item) =>
          controller.cashFlowTreatment(item) ==
          CashFlowTreatment.externalInflow,
    )) {
      final label = desktopTransactionTitle(transaction);
      incomeGroups.update(
        label,
        (value) => value + transaction.amount,
        ifAbsent: () => transaction.amount,
      );
    }
    final sortedSources = incomeGroups.entries.toList(growable: false)
      ..sort((left, right) => right.value.compareTo(left.value));
    final incomeTransactions = transactions
        .where(
          (item) =>
              controller.cashFlowTreatment(item) ==
              CashFlowTreatment.externalInflow,
        )
        .toList(growable: false);
    final sources = <OverviewFlowNode>[];
    for (final entry in sortedSources.take(3)) {
      final members = incomeTransactions
          .where((item) => desktopTransactionTitle(item) == entry.key)
          .toList(growable: false);
      sources.add(
        OverviewFlowNode(
          id: 'source-${entry.key}',
          label: entry.key,
          amount: entry.value,
          color: QestoColors.primary,
          transactionCount: members.length,
          transactionIds: members
              .map((item) => item.id)
              .toList(growable: false),
        ),
      );
    }
    if (sortedSources.length > 3) {
      final otherTitles = sortedSources.skip(3).map((item) => item.key).toSet();
      final members = incomeTransactions
          .where((item) => otherTitles.contains(desktopTransactionTitle(item)))
          .toList(growable: false);
      sources.add(
        OverviewFlowNode(
          id: 'source-other',
          label: 'Другие доходы',
          amount: sortedSources
              .skip(3)
              .fold<int>(0, (sum, item) => sum + item.value),
          color: QestoColors.purple,
          transactionCount: members.length,
          transactionIds: members
              .map((item) => item.id)
              .toList(growable: false),
        ),
      );
    }

    final allocations = transactions
        .where(
          (item) =>
              item.type == TransactionType.savingsTransfer ||
              item.type == TransactionType.investment,
        )
        .fold<int>(0, (sum, item) => sum + item.amount);
    final outflow = expenses + allocations;
    final total = math.max(income, outflow);
    if (outflow > income) {
      sources.add(
        OverviewFlowNode(
          id: 'source-reserve',
          label: 'Покрыто начальным остатком',
          amount: outflow - income,
          color: QestoColors.orange,
          transactionCount: 0,
        ),
      );
    }

    final categories = <OverviewFlowBranch>[];
    final visibleSpending = categoryLimit == null
        ? categorySpending
        : categorySpending.take(categoryLimit).toList(growable: false);
    for (final category in visibleSpending) {
      categories.add(
        OverviewFlowBranch(
          id: category.id,
          label: category.name,
          amount: category.amount,
          color: category.color,
          iconKey: category.iconKey,
          transactionIds: category.transactions
              .map((item) => item.id)
              .toList(growable: false),
          destinations: _destinations(category.transactions, category.amount),
        ),
      );
    }
    if (categoryLimit != null && categorySpending.length > categoryLimit) {
      final hidden = categorySpending
          .skip(categoryLimit)
          .toList(growable: false);
      final hiddenTransactions = hidden
          .expand((item) => item.transactions)
          .toList(growable: false);
      final hiddenAmount = hidden.fold<int>(
        0,
        (sum, item) => sum + item.amount,
      );
      categories.add(
        OverviewFlowBranch(
          id: '__other_expenses_aggregate',
          label: 'Другие расходы',
          amount: hiddenAmount,
          color: const Color(0xFF59C3B5),
          iconKey: 'category',
          transactionIds: hiddenTransactions
              .map((item) => item.id)
              .toList(growable: false),
          destinations: _destinations(hiddenTransactions, hiddenAmount),
        ),
      );
    }
    if (allocations > 0) {
      final allocationTransactions = transactions
          .where(
            (item) =>
                item.type == TransactionType.savingsTransfer ||
                item.type == TransactionType.investment,
          )
          .toList(growable: false);
      categories.add(
        OverviewFlowBranch(
          id: 'savings',
          label: 'Накопления и инвестиции',
          amount: allocations,
          color: QestoColors.positive,
          iconKey: 'savings',
          transactionIds: allocationTransactions
              .map((item) => item.id)
              .toList(growable: false),
          destinations: _destinations(allocationTransactions, allocations),
        ),
      );
    }
    if (income > outflow) {
      categories.add(
        OverviewFlowBranch(
          id: 'remaining-income',
          label: 'Доходы сверх расходов',
          amount: income - outflow,
          color: const Color(0xFF68B96B),
          iconKey: 'savings',
          destinations: [
            OverviewFlowNode(
              id: 'remaining-on-accounts',
              label: 'Разница за период',
              amount: income - outflow,
              color: const Color(0xFF68B96B),
              transactionCount: 0,
            ),
          ],
        ),
      );
    }

    return OverviewFlowData(
      currency: currency,
      total: total,
      income: income,
      expenses: expenses,
      sources: sources,
      branches: categories.where((item) => item.amount > 0).toList(),
    );
  }

  static List<OverviewFlowNode> _destinations(
    List<BudgetTransaction> transactions,
    int branchAmount,
  ) {
    if (transactions.isEmpty) {
      return [
        OverviewFlowNode(
          id: 'destination-other',
          label: 'Другие операции',
          amount: branchAmount,
          color: QestoColors.secondaryText,
          transactionCount: 0,
        ),
      ];
    }
    final sorted = transactions.toList(growable: false)
      ..sort((left, right) => right.amount.compareTo(left.amount));
    final result = <OverviewFlowNode>[];
    var shown = 0;
    for (final transaction in sorted.take(3)) {
      final visibleAmount = math.min(transaction.amount, branchAmount - shown);
      if (visibleAmount <= 0) break;
      result.add(
        OverviewFlowNode(
          id: 'destination-${transaction.id}',
          label: desktopTransactionTitle(transaction),
          amount: visibleAmount,
          color: QestoColors.secondaryText,
          transactionCount: 1,
          transactionIds: [transaction.id],
        ),
      );
      shown += visibleAmount;
    }
    final remainder = math.max(0, branchAmount - shown);
    if (remainder > 0) {
      result.add(
        OverviewFlowNode(
          id: 'destination-rest-${transactions.first.id}',
          label: 'Остальные операции',
          amount: remainder,
          color: QestoColors.secondaryText,
          transactionCount: math.max(0, transactions.length - 3),
          transactionIds: sorted
              .skip(3)
              .map((item) => item.id)
              .toList(growable: false),
        ),
      );
    }
    return result;
  }

  static String _fallbackCategory(String id) => switch (id) {
    'uncategorized' => 'Без категории',
    'income' => 'Доходы',
    _ => id,
  };
}

class OverviewTrendPoint {
  const OverviewTrendPoint({required this.date, required this.amount});

  final DateTime date;
  final int amount;
}

class OverviewCategorySpend {
  const OverviewCategorySpend({
    required this.id,
    required this.name,
    required this.amount,
    required this.iconKey,
    required this.color,
    required this.transactions,
  });

  final String id;
  final String name;
  final int amount;
  final String iconKey;
  final Color color;
  final List<BudgetTransaction> transactions;
}

class OverviewCategoryBudgetRow {
  const OverviewCategoryBudgetRow({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.color,
    required this.spent,
    required this.progress,
    required this.isRelative,
  });

  final String id;
  final String name;
  final String iconKey;
  final Color color;
  final int spent;
  final double progress;
  final bool isRelative;
}

class OverviewFlowData {
  const OverviewFlowData({
    required this.currency,
    required this.total,
    required this.income,
    required this.expenses,
    required this.sources,
    required this.branches,
  });

  final String currency;
  final int total;
  final int income;
  final int expenses;
  final List<OverviewFlowNode> sources;
  final List<OverviewFlowBranch> branches;
}

class OverviewFlowNode {
  const OverviewFlowNode({
    required this.id,
    required this.label,
    required this.amount,
    required this.color,
    required this.transactionCount,
    this.transactionIds = const [],
  });

  final String id;
  final String label;
  final int amount;
  final Color color;
  final int transactionCount;
  final List<String> transactionIds;
}

class OverviewFlowBranch {
  const OverviewFlowBranch({
    required this.id,
    required this.label,
    required this.amount,
    required this.color,
    required this.iconKey,
    required this.destinations,
    this.transactionIds = const [],
  });

  final String id;
  final String label;
  final int amount;
  final Color color;
  final String iconKey;
  final List<OverviewFlowNode> destinations;
  final List<String> transactionIds;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
