import '../../../data/models/qesto_models.dart';
import 'budget_calculation_service.dart';

class BudgetForecastService {
  const BudgetForecastService({
    this.calculationService = const BudgetCalculationService(),
  });

  final BudgetCalculationService calculationService;

  BudgetForecast buildForecast({
    required BudgetPeriod period,
    required Iterable<BudgetTransaction> transactions,
    required DateTime asOfDate,
  }) {
    final actual = calculationService.cumulativePoints(
      period,
      transactions,
      asOfDate,
    );
    final current = actual.isEmpty ? 0.0 : actual.last.amount;
    if (!period.hasAssignedBudget) {
      return BudgetForecast(
        state: BudgetForecastState.noForecast,
        actualPoints: actual,
        projectedPoints: const [],
        targetPoints: const [],
        totalPlan: period.totalPlan,
      );
    }
    if (current > period.totalPlan) {
      return BudgetForecast(
        state: BudgetForecastState.exceeded,
        actualPoints: actual,
        projectedPoints: const [],
        targetPoints: const [],
        totalPlan: period.totalPlan,
      );
    }
    if (actual.isEmpty || current == 0 || !asOfDate.isBefore(period.endDate)) {
      return BudgetForecast(
        state: BudgetForecastState.noForecast,
        actualPoints: actual,
        projectedPoints: const [],
        targetPoints: const [],
        totalPlan: period.totalPlan,
      );
    }

    final window = actual.length < 7 ? actual.length : 7;
    final startIndex = actual.length - window;
    final beforeWindow = startIndex == 0 ? 0.0 : actual[startIndex - 1].amount;
    final recentRate = (current - beforeWindow) / window;
    final projected = <DailyBudgetPoint>[
      DailyBudgetPoint(date: asOfDate, amount: current),
    ];
    DateTime? crossingDate;
    var dayIndex = 0;
    for (
      var day = asOfDate.add(const Duration(days: 1));
      !day.isAfter(period.endDate);
      day = day.add(const Duration(days: 1))
    ) {
      dayIndex++;
      final amount = current + recentRate * dayIndex;
      projected.add(DailyBudgetPoint(date: day, amount: amount));
      if (crossingDate == null && amount >= period.totalPlan) {
        crossingDate = day;
      }
    }

    final remainingDays = period.endDate.difference(asOfDate).inDays;
    final target = <DailyBudgetPoint>[];
    for (var index = 0; index <= remainingDays; index++) {
      final amount =
          current +
          (period.totalPlan - current) *
              (remainingDays == 0 ? 1 : index / remainingDays);
      target.add(
        DailyBudgetPoint(
          date: asOfDate.add(Duration(days: index)),
          amount: amount,
        ),
      );
    }

    return BudgetForecast(
      state: crossingDate == null
          ? BudgetForecastState.underPlan
          : BudgetForecastState.projectedOverLimit,
      actualPoints: actual,
      projectedPoints: projected,
      targetPoints: target,
      totalPlan: period.totalPlan,
      crossingDate: crossingDate,
    );
  }
}
