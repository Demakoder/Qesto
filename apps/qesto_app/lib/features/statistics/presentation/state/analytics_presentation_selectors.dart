import '../../../../data/models/qesto_models.dart';
import '../../../budget/state/budget_controller.dart';
import '../../../budget/services/cash_flow_calculation_service.dart';
import '../../../../desktop/desktop_financial_helpers.dart';
import 'statistics_controller.dart';

/// Shared, read-only presentation grouping formerly embedded in desktop UI.
/// Monetary treatment/calculation stays in the existing services.
Map<String, int> cashFlowDisplayGroups(
  BudgetController budget,
  Iterable<BudgetTransaction> transactions,
  CashFlowTreatment treatment,
) {
  final result = <String, int>{};
  for (final t in transactions.where(
    (t) => budget.cashFlowTreatment(t) == treatment,
  )) {
    final title = treatment == CashFlowTreatment.externalInflow
        ? desktopTransactionTitle(t)
        : desktopCategoryName(budget, t);
    result.update(title, (v) => v + t.amount, ifAbsent: () => t.amount);
  }
  return result;
}

/// Retains exact canonical membership alongside the existing display grouping.
Map<String, List<BudgetTransaction>> cashFlowDisplayMembers(
  BudgetController budget,
  Iterable<BudgetTransaction> transactions,
  CashFlowTreatment treatment,
) {
  final result = <String, List<BudgetTransaction>>{};
  for (final t in transactions.where(
    (t) => budget.cashFlowTreatment(t) == treatment,
  )) {
    final label = treatment == CashFlowTreatment.externalInflow
        ? desktopTransactionTitle(t)
        : desktopCategoryName(budget, t);
    result.putIfAbsent(label, () => []).add(t);
  }
  return result;
}

Map<int, int> rhythmWeekAmounts(StatisticsController statistics) {
  final result = <int, int>{};
  for (final point in statistics.snapshot.daily) {
    final week =
        point.date.difference(statistics.query.period.start).inDays ~/ 7 + 1;
    result.update(week, (v) => v + point.amount, ifAbsent: () => point.amount);
  }
  return result;
}

({DateTime day, int expenses, double share})? rhythmSalaryCycle(
  StatisticsController statistics,
) {
  final income = statistics.snapshot.transactions.where(
    (t) => t.type == TransactionType.income,
  );
  if (income.isEmpty) return null;
  final day = income.first.date;
  final expenses = statistics.snapshot.transactions
      .where(statistics.calculationService.isConsumerExpense)
      .where((t) => !t.date.isBefore(day) && t.date.difference(day).inDays < 5)
      .fold<int>(
        0,
        (sum, t) => sum + statistics.calculationService.signedExpense(t),
      );
  return (
    day: day,
    expenses: expenses,
    share:
        expenses /
        (statistics.snapshot.summary.expenses < 1
            ? 1
            : statistics.snapshot.summary.expenses),
  );
}
