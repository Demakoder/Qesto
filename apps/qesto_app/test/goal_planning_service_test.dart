import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/capital/domain/goal_planning_service.dart';

void main() {
  const service = GoalPlanningService();
  final asOf = DateTime(2026, 9, 2);

  SavingsGoal goal({
    required String id,
    required int target,
    int saved = 0,
    DateTime? targetDate,
    int? monthly,
    GoalPriority priority = GoalPriority.medium,
    GoalStatus status = GoalStatus.active,
  }) => SavingsGoal(
    id: id,
    userId: 'user-1',
    title: id,
    targetAmount: target,
    savedAmount: saved,
    currency: 'RUB',
    streakWeeks: 0,
    isActive: status == GoalStatus.active,
    history: const [],
    targetDate: targetDate,
    desiredMonthlyContribution: monthly,
    priority: priority,
    status: status,
  );

  test('calculates required monthly amount and projected completion', () {
    final result = service.calculate(
      goals: [
        goal(
          id: 'car',
          target: 1000000,
          saved: 300000,
          targetDate: DateTime(2027, 11, 2),
          monthly: 50000,
        ),
      ],
      allocations: const [],
      asOf: asOf,
      baseCurrency: 'RUB',
    );

    expect(result.activeCount, 1);
    expect(result.currentAmount, 300000);
    expect(result.goals.single.remainingAmount, 700000);
    expect(result.goals.single.requiredMonthlyContribution, 50000);
    expect(result.goals.single.projectedCompletionDate, DateTime(2027, 11, 2));
  });

  test(
    'allocations replace manual current amount without coupling the goal',
    () {
      final result = service.calculate(
        goals: [goal(id: 'trip', target: 200000, saved: 10000)],
        allocations: [
          GoalAllocation(
            id: 'allocation-1',
            goalId: 'trip',
            sourceType: GoalAllocationSourceType.account,
            sourceId: 'account-1',
            allocatedAmount: 60000,
            currency: 'RUB',
            updatedAt: asOf,
          ),
        ],
        asOf: asOf,
        baseCurrency: 'RUB',
      );

      expect(result.goals.single.currentAmount, 60000);
      expect(result.goals.single.allocations.single.sourceId, 'account-1');
    },
  );

  test('archived goals stay in storage but not in the active plan', () {
    final result = service.calculate(
      goals: [
        goal(id: 'active', target: 100000, priority: GoalPriority.high),
        goal(id: 'archived', target: 200000, status: GoalStatus.archived),
      ],
      allocations: const [],
      asOf: asOf,
      baseCurrency: 'RUB',
    );

    expect(result.activeCount, 1);
    expect(result.goals.single.goal.id, 'active');
  });

  test(
    'monthly plan uses actual contribution events and supports simulation',
    () {
      final value = goal(
        id: 'car',
        target: 1000000,
        saved: 200000,
        monthly: 50000,
      );
      final result = service.calculate(
        goals: [value],
        allocations: const [],
        contributions: [
          GoalContribution(
            id: 'c1',
            goalId: value.id,
            date: DateTime(2026, 9, 1),
            amount: 20000,
            currency: 'RUB',
            type: GoalContributionType.contribution,
            source: GoalContributionSource.manual,
            createdAt: DateTime(2026, 9, 1),
          ),
        ],
        asOf: asOf,
        baseCurrency: 'RUB',
      );

      expect(result.monthlyPlan, 50000);
      expect(result.actualThisMonth, 20000);
      expect(result.monthlyPlanGap, 30000);
      final simulation = service.simulateMonthlyContribution(
        plan: result.goals.single,
        monthlyContribution: 100000,
        asOf: asOf,
      );
      expect(simulation.projectedDate, DateTime(2027, 5, 2));
    },
  );

  test('reserve goal becomes active again when its amount drops', () {
    final reserve = SavingsGoal(
      id: 'reserve',
      userId: 'user-1',
      title: 'Подушка',
      targetAmount: 600000,
      savedAmount: 520000,
      currency: 'RUB',
      streakWeeks: 0,
      isActive: true,
      history: const [],
      type: GoalType.reserve,
      status: GoalStatus.completed,
    );
    final plan = service.calculateGoal(goal: reserve, asOf: asOf);

    expect(plan.needsRestore, isTrue);
    expect(plan.remainingAmount, 80000);
    expect(plan.isCompleted, isFalse);
    expect(plan.effectiveStatus, GoalStatus.active);
  });
}
