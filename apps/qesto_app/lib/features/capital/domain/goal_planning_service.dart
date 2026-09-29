import 'dart:math' as math;

import '../../../data/models/qesto_models.dart';
import '../../profile/services/cbr_currency_service.dart';

class GoalPlan {
  const GoalPlan({
    required this.goal,
    required this.currentAmount,
    required this.remainingAmount,
    required this.progressPercent,
    required this.monthsRemaining,
    required this.requiredMonthlyContribution,
    required this.plannedMonthlyContribution,
    required this.actualContributionThisMonth,
    required this.monthlyPlanGap,
    required this.projectedCompletionDate,
    required this.allocations,
    required this.contributions,
    required this.isTargetDateExpired,
  });

  final SavingsGoal goal;
  final int currentAmount;
  final int remainingAmount;
  final double progressPercent;
  final int? monthsRemaining;
  final int? requiredMonthlyContribution;
  final int? plannedMonthlyContribution;
  final int actualContributionThisMonth;
  final int monthlyPlanGap;
  final DateTime? projectedCompletionDate;
  final List<GoalAllocation> allocations;
  final List<GoalContribution> contributions;
  final bool isTargetDateExpired;

  bool get isCompleted {
    if (goal.type == GoalType.reserve) {
      return goal.targetAmount > 0 && currentAmount >= goal.targetAmount;
    }
    return goal.status == GoalStatus.completed ||
        (goal.targetAmount > 0 && currentAmount >= goal.targetAmount);
  }

  bool get needsRestore =>
      goal.type == GoalType.reserve &&
      goal.targetAmount > 0 &&
      currentAmount < goal.targetAmount;

  GoalStatus get effectiveStatus {
    if (goal.status == GoalStatus.archived) return GoalStatus.archived;
    if (needsRestore) return GoalStatus.active;
    if (goal.status == GoalStatus.completed) return GoalStatus.completed;
    if (goal.status == GoalStatus.spending) return GoalStatus.spending;
    if (goal.targetAmount > 0 && currentAmount >= goal.targetAmount) {
      return GoalStatus.funded;
    }
    if (goal.status == GoalStatus.paused) return GoalStatus.paused;
    return GoalStatus.active;
  }
}

class GoalPortfolioPlan {
  const GoalPortfolioPlan({
    required this.baseCurrency,
    required this.activeCount,
    required this.targetAmount,
    required this.currentAmount,
    required this.monthlyPlan,
    required this.actualThisMonth,
    required this.monthlyPlanGap,
    required this.monthlyProgress,
    required this.goals,
    required this.hasUnconvertedCurrencies,
  });

  final String baseCurrency;
  final int activeCount;
  final int targetAmount;
  final int currentAmount;
  final int monthlyPlan;
  final int actualThisMonth;
  final int monthlyPlanGap;
  final double monthlyProgress;
  final List<GoalPlan> goals;
  final bool hasUnconvertedCurrencies;
}

class GoalAllocationAvailability {
  const GoalAllocationAvailability({
    required this.sourceBalance,
    required this.allocated,
  });

  final int sourceBalance;
  final int allocated;
  int get available => math.max(0, sourceBalance - allocated);
}

class GoalSimulation {
  const GoalSimulation({
    required this.monthlyContribution,
    required this.projectedDate,
    required this.monthDifference,
  });

  final int monthlyContribution;
  final DateTime? projectedDate;
  final int? monthDifference;
}

class GoalPlanningService {
  const GoalPlanningService();

  GoalPortfolioPlan calculate({
    required List<SavingsGoal> goals,
    required List<GoalAllocation> allocations,
    List<GoalContribution> contributions = const [],
    required DateTime asOf,
    required String baseCurrency,
  }) {
    var hasUnconvertedCurrencies = false;
    int? convert(int amount, String currency) {
      final value = convertAmount(amount, currency, baseCurrency);
      if (value == null) hasUnconvertedCurrencies = true;
      return value;
    }

    final plans =
        goals
            .where((goal) => goal.effectiveStatus != GoalStatus.archived)
            .map(
              (goal) => calculateGoal(
                goal: goal,
                allocations: allocations
                    .where((item) => item.goalId == goal.id)
                    .toList(growable: false),
                contributions: contributions
                    .where((item) => item.goalId == goal.id)
                    .toList(growable: false),
                asOf: asOf,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) {
            final priority = right.goal.priority.index.compareTo(
              left.goal.priority.index,
            );
            if (priority != 0) return priority;
            final leftDate = left.goal.targetDate;
            final rightDate = right.goal.targetDate;
            if (leftDate == null && rightDate == null) return 0;
            if (leftDate == null) return 1;
            if (rightDate == null) return -1;
            return leftDate.compareTo(rightDate);
          });

    final active = plans.where(
      (item) => item.effectiveStatus == GoalStatus.active && !item.isCompleted,
    );
    var target = 0;
    var current = 0;
    var monthly = 0;
    var actual = 0;
    for (final plan in active) {
      target += convert(plan.goal.targetAmount, plan.goal.currency) ?? 0;
      current += convert(plan.currentAmount, plan.goal.currency) ?? 0;
      monthly +=
          convert(plan.plannedMonthlyContribution ?? 0, plan.goal.currency) ??
          0;
      actual +=
          convert(plan.actualContributionThisMonth, plan.goal.currency) ?? 0;
    }
    final gap = math.max(0, monthly - actual);
    return GoalPortfolioPlan(
      baseCurrency: baseCurrency,
      activeCount: active.length,
      targetAmount: target,
      currentAmount: current,
      monthlyPlan: monthly,
      actualThisMonth: actual,
      monthlyPlanGap: gap,
      monthlyProgress: monthly <= 0 ? 0 : (actual / monthly).clamp(0, 1),
      goals: plans,
      hasUnconvertedCurrencies: hasUnconvertedCurrencies,
    );
  }

  GoalPlan calculateGoal({
    required SavingsGoal goal,
    List<GoalAllocation> allocations = const [],
    List<GoalContribution> contributions = const [],
    required DateTime asOf,
  }) {
    final allocated = allocations.fold<int>(
      0,
      (sum, item) =>
          sum +
          (convertAmount(item.allocatedAmount, item.currency, goal.currency) ??
              0),
    );
    // Once physical sources are linked, their allocations become the current
    // amount. This prevents a legacy/manual balance from being counted twice.
    final current = math.max(
      0,
      allocations.isEmpty ? goal.savedAmount : allocated,
    );
    final remaining = math.max(0, goal.targetAmount - current);
    final expired =
        goal.targetDate != null &&
        _day(goal.targetDate!).isBefore(_day(asOf)) &&
        remaining > 0;
    final months = goal.targetDate == null
        ? null
        : math.max(0, _monthsBetween(asOf, goal.targetDate!));
    final required = months == null || months == 0 || remaining == 0
        ? null
        : (remaining / months).ceil();
    final planned = goal.desiredMonthlyContribution ?? required;
    final actual = contributions
        .where(
          (item) =>
              item.date.year == asOf.year && item.date.month == asOf.month,
        )
        .fold<int>(0, (sum, item) {
          final converted =
              convertAmount(item.amount, item.currency, goal.currency) ?? 0;
          return item.type == GoalContributionType.contribution
              ? sum + converted
              : sum - converted;
        });
    final projected = remaining == 0
        ? asOf
        : planned == null || planned <= 0 || goal.targetAmount <= 0
        ? null
        : _addMonths(asOf, (remaining / planned).ceil());
    return GoalPlan(
      goal: goal,
      currentAmount: current,
      remainingAmount: remaining,
      progressPercent: goal.targetAmount <= 0
          ? 0
          : (current / goal.targetAmount).clamp(0, 1),
      monthsRemaining: months,
      requiredMonthlyContribution: required,
      plannedMonthlyContribution: planned,
      actualContributionThisMonth: math.max(0, actual),
      monthlyPlanGap: math.max(0, (planned ?? 0) - math.max(0, actual)),
      projectedCompletionDate: projected,
      allocations: allocations,
      contributions: List.of(contributions)
        ..sort((left, right) => right.date.compareTo(left.date)),
      isTargetDateExpired: expired,
    );
  }

  GoalSimulation simulateMonthlyContribution({
    required GoalPlan plan,
    required int monthlyContribution,
    required DateTime asOf,
  }) {
    if (monthlyContribution <= 0 || plan.remainingAmount <= 0) {
      return GoalSimulation(
        monthlyContribution: monthlyContribution,
        projectedDate: plan.remainingAmount <= 0 ? asOf : null,
        monthDifference: null,
      );
    }
    final projected = _addMonths(
      asOf,
      (plan.remainingAmount / monthlyContribution).ceil(),
    );
    final current = plan.projectedCompletionDate;
    return GoalSimulation(
      monthlyContribution: monthlyContribution,
      projectedDate: projected,
      monthDifference: current == null
          ? null
          : _monthsBetween(projected, current),
    );
  }

  GoalAllocationAvailability allocationAvailability({
    required int sourceBalance,
    required String sourceId,
    required GoalAllocationSourceType sourceType,
    required List<GoalAllocation> allocations,
    String? excludingAllocationId,
  }) {
    final allocated = allocations
        .where(
          (item) =>
              item.sourceId == sourceId &&
              item.sourceType == sourceType &&
              item.id != excludingAllocationId,
        )
        .fold<int>(0, (sum, item) => sum + item.allocatedAmount);
    return GoalAllocationAvailability(
      sourceBalance: math.max(0, sourceBalance),
      allocated: allocated,
    );
  }

  int? convertAmount(int amount, String from, String to) {
    if (from == to) return amount;
    final rates = CbrCurrencyService.embeddedSnapshot.rates;
    final fromRate = rates[from]?.rublesPerUnit;
    final toRate = rates[to]?.rublesPerUnit;
    if (fromRate == null || toRate == null) return null;
    return (amount * fromRate / toRate).round();
  }

  int _monthsBetween(DateTime from, DateTime to) => math.max(
    0,
    (to.year - from.year) * 12 +
        to.month -
        from.month +
        (to.day > from.day ? 1 : 0),
  );

  DateTime _addMonths(DateTime value, int months) {
    final first = DateTime(value.year, value.month + months);
    final last = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month, value.day.clamp(1, last));
  }

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
}
