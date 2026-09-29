import '../../../../data/models/budget_models.dart';
import '../models/statistics_models.dart';

/// Shared calendar semantics, extracted unchanged from StatisticsController.
/// Three/six/twelve months include the current partial calendar month.
StatisticsDateRange? statisticsPeriodRange({
  required StatisticsPeriodPreset preset,
  required DateTime reference,
  Iterable<DateTime> transactionDates = const [],
  List<BudgetPeriod> budgetPeriods = const [],
}) {
  switch (preset) {
    case StatisticsPeriodPreset.currentWeek:
      return StatisticsDateRange(
        reference.subtract(Duration(days: reference.weekday - 1)),
        reference,
      );
    case StatisticsPeriodPreset.currentBudget:
      final period = budgetPeriods.firstWhere(
        (p) => p.contains(reference),
        orElse: () => budgetPeriods.last,
      );
      return StatisticsDateRange(period.startDate, reference);
    case StatisticsPeriodPreset.last30Days:
      return StatisticsDateRange(
        reference.subtract(const Duration(days: 29)),
        reference,
      );
    case StatisticsPeriodPreset.threeMonths:
      return StatisticsDateRange(
        DateTime(reference.year, reference.month - 2),
        reference,
      );
    case StatisticsPeriodPreset.sixMonths:
      return StatisticsDateRange(
        DateTime(reference.year, reference.month - 5),
        reference,
      );
    case StatisticsPeriodPreset.currentYear:
      return StatisticsDateRange(DateTime(reference.year), reference);
    case StatisticsPeriodPreset.last12Months:
      return StatisticsDateRange(
        DateTime(reference.year, reference.month - 11),
        reference,
      );
    case StatisticsPeriodPreset.allTime:
      final dates = transactionDates.toList();
      final earliest = dates.isEmpty
          ? reference
          : dates.reduce((a, b) => a.isBefore(b) ? a : b);
      return StatisticsDateRange(earliest, reference);
    case StatisticsPeriodPreset.custom:
      return null;
  }
}
