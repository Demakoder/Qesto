import '../../../data/models/qesto_models.dart';
import 'budget_calculation_service.dart';

class CategoryPlanStatus {
  const CategoryPlanStatus({
    required this.category,
    required this.spentAmount,
    required this.plannedAmount,
  });

  final BudgetCategory category;
  final int spentAmount;
  final int plannedAmount;

  double get progress => plannedAmount <= 0 ? 0 : spentAmount / plannedAmount;
  int get remaining => plannedAmount - spentAmount;
  bool get hasAssignedBudget => plannedAmount > 0;
  bool get isExceeded => plannedAmount > 0 && spentAmount > plannedAmount;
}

class CategoryBudgetCalculationService {
  const CategoryBudgetCalculationService({
    this.budgetCalculationService = const BudgetCalculationService(),
  });

  final BudgetCalculationService budgetCalculationService;

  List<CategoryPlanStatus> calculate({
    required BudgetPeriod period,
    required Iterable<BudgetCategory> categories,
    required Iterable<CategoryBudget> budgets,
    required Iterable<BudgetTransaction> transactions,
  }) {
    final plans = {
      for (final plan in budgets.where(
        (plan) => plan.budgetPeriodId == period.id,
      ))
        plan.categoryId: plan.plannedAmount,
    };
    final results = <CategoryPlanStatus>[];
    for (final category in categories) {
      final spent = budgetCalculationService.categoryExpense(
        period,
        category.id,
        transactions,
      );
      final planned = plans[category.id] ?? 0;
      if (spent == 0 && planned == 0) continue;
      results.add(
        CategoryPlanStatus(
          category: category,
          spentAmount: spent,
          plannedAmount: planned,
        ),
      );
    }
    results.sort((a, b) => b.spentAmount.compareTo(a.spentAmount));
    return results;
  }
}
