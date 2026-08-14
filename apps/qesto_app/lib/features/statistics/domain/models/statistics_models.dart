import '../../../../data/models/qesto_models.dart';

enum StatisticsSection {
  overview('Обзор'),
  expenses('Расходы'),
  rhythm('Ритм жизни'),
  merchants('Магазины'),
  categories('Категории'),
  cashFlow('Денежный поток'),
  budget('Бюджет'),
  recurring('Регулярные');

  const StatisticsSection(this.label);
  final String label;
}

enum StatisticsPeriodPreset {
  currentWeek,
  currentBudget,
  last30Days,
  threeMonths,
  sixMonths,
  currentYear,
  last12Months,
  allTime,
  custom,
}

enum StatisticsComparison {
  none,
  previousSameLength,
  previousYear,
  average3,
  average6,
  average12,
}

class StatisticsDateRange {
  StatisticsDateRange(DateTime start, DateTime end)
    : start = DateTime(start.year, start.month, start.day),
      end = DateTime(end.year, end.month, end.day);

  final DateTime start;
  final DateTime end;

  int get dayCount => end.difference(start).inDays + 1;

  bool contains(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    return !date.isBefore(start) && !date.isAfter(end);
  }
}

class StatisticsQuery {
  const StatisticsQuery({
    required this.period,
    this.preset = StatisticsPeriodPreset.currentBudget,
    this.comparison = StatisticsComparison.previousSameLength,
    this.accountIds = const {},
    this.categoryIds = const {},
    this.subcategoryIds = const {},
    this.merchantNames = const {},
    this.tagIds = const {},
    this.transactionTypes = const {},
    this.includeLargePurchases = true,
    this.includeRecurring = true,
    this.includeRefunds = true,
    this.includeCash = true,
    this.includeUncategorized = true,
    this.onlyConfirmed = false,
  });

  final StatisticsDateRange period;
  final StatisticsPeriodPreset preset;
  final StatisticsComparison comparison;
  final Set<String> accountIds;
  final Set<String> categoryIds;
  final Set<String> subcategoryIds;
  final Set<String> merchantNames;
  final Set<String> tagIds;
  final Set<TransactionType> transactionTypes;
  final bool includeLargePurchases;
  final bool includeRecurring;
  final bool includeRefunds;
  final bool includeCash;
  final bool includeUncategorized;
  final bool onlyConfirmed;

  int get activeFilterCount =>
      accountIds.length +
      categoryIds.length +
      subcategoryIds.length +
      merchantNames.length +
      tagIds.length +
      transactionTypes.length +
      (includeLargePurchases ? 0 : 1) +
      (includeRecurring ? 0 : 1) +
      (includeRefunds ? 0 : 1) +
      (includeCash ? 0 : 1) +
      (includeUncategorized ? 0 : 1) +
      (onlyConfirmed ? 1 : 0);

  StatisticsQuery copyWith({
    StatisticsDateRange? period,
    StatisticsPeriodPreset? preset,
    StatisticsComparison? comparison,
    Set<String>? accountIds,
    Set<String>? categoryIds,
    Set<String>? subcategoryIds,
    Set<String>? merchantNames,
    Set<String>? tagIds,
    Set<TransactionType>? transactionTypes,
    bool? includeLargePurchases,
    bool? includeRecurring,
    bool? includeRefunds,
    bool? includeCash,
    bool? includeUncategorized,
    bool? onlyConfirmed,
  }) {
    return StatisticsQuery(
      period: period ?? this.period,
      preset: preset ?? this.preset,
      comparison: comparison ?? this.comparison,
      accountIds: accountIds ?? this.accountIds,
      categoryIds: categoryIds ?? this.categoryIds,
      subcategoryIds: subcategoryIds ?? this.subcategoryIds,
      merchantNames: merchantNames ?? this.merchantNames,
      tagIds: tagIds ?? this.tagIds,
      transactionTypes: transactionTypes ?? this.transactionTypes,
      includeLargePurchases:
          includeLargePurchases ?? this.includeLargePurchases,
      includeRecurring: includeRecurring ?? this.includeRecurring,
      includeRefunds: includeRefunds ?? this.includeRefunds,
      includeCash: includeCash ?? this.includeCash,
      includeUncategorized: includeUncategorized ?? this.includeUncategorized,
      onlyConfirmed: onlyConfirmed ?? this.onlyConfirmed,
    );
  }
}

class StatisticsSummary {
  const StatisticsSummary({
    required this.expenses,
    required this.income,
    required this.savings,
    required this.purchaseCount,
    required this.averageCheck,
    required this.medianCheck,
    required this.averageDailyExpense,
    required this.changePercent,
    required this.averageCheckChange,
  });

  final int expenses;
  final int income;
  final int savings;
  final int purchaseCount;
  final double averageCheck;
  final double medianCheck;
  final double averageDailyExpense;
  final double? changePercent;
  final double? averageCheckChange;

  int get balance => income - expenses - savings;
}

class StatisticsGroupStat {
  const StatisticsGroupStat({
    required this.id,
    required this.label,
    required this.amount,
    required this.count,
    required this.averageCheck,
    required this.medianCheck,
    required this.share,
    required this.changePercent,
    this.colorValue,
    this.iconKey,
  });

  final String id;
  final String label;
  final int amount;
  final int count;
  final double averageCheck;
  final double medianCheck;
  final double share;
  final double? changePercent;
  final int? colorValue;
  final String? iconKey;
}

class StatisticsDailyPoint {
  const StatisticsDailyPoint({
    required this.date,
    required this.amount,
    required this.cumulative,
    required this.count,
  });

  final DateTime date;
  final int amount;
  final int cumulative;
  final int count;
}

class StatisticsPeriodPoint {
  const StatisticsPeriodPoint({
    required this.period,
    required this.expenses,
    required this.income,
    required this.plan,
    required this.largePurchases,
  });

  final BudgetPeriod period;
  final int expenses;
  final int income;
  final int plan;
  final int largePurchases;

  int get balance => income - expenses;
}

class StatisticsAmountBucket {
  const StatisticsAmountBucket({
    required this.label,
    required this.count,
    required this.amount,
  });

  final String label;
  final int count;
  final int amount;
}

class StatisticsWeekdayStat {
  const StatisticsWeekdayStat({
    required this.weekday,
    required this.amount,
    required this.count,
    required this.averageCheck,
  });

  final int weekday;
  final int amount;
  final int count;
  final double averageCheck;
}

enum StatisticsInsightType {
  change,
  category,
  merchant,
  largePurchase,
  quality,
}

class StatisticsInsight {
  const StatisticsInsight({
    required this.title,
    required this.explanation,
    required this.calculation,
    required this.type,
    required this.priority,
    this.targetId,
  });

  final String title;
  final String explanation;
  final String calculation;
  final StatisticsInsightType type;
  final int priority;
  final String? targetId;
}

enum DataQualityIssueType {
  uncategorized,
  unknownMerchant,
  potentialDuplicate,
  unconfirmedOperation,
  lowConfidence,
  missingAccount,
}

class DataQualityIssue {
  const DataQualityIssue({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.weight,
    this.transactionId,
    this.isCritical = false,
  });

  final String id;
  final DataQualityIssueType type;
  final String title;
  final String description;
  final int weight;
  final String? transactionId;
  final bool isCritical;
}

class DataQualityReport {
  const DataQualityReport({required this.score, required this.issues});

  final int score;
  final List<DataQualityIssue> issues;

  int get criticalCount => issues.where((issue) => issue.isCritical).length;
}

class StatisticsSnapshot {
  const StatisticsSnapshot({
    required this.query,
    required this.comparisonRange,
    required this.transactions,
    required this.comparisonTransactions,
    required this.summary,
    required this.categories,
    required this.merchants,
    required this.daily,
    required this.comparisonDaily,
    required this.periods,
    required this.buckets,
    required this.weekdays,
    required this.largestTransactions,
    required this.recurringTransactions,
    required this.insights,
    required this.dataQuality,
  });

  final StatisticsQuery query;
  final StatisticsDateRange? comparisonRange;
  final List<BudgetTransaction> transactions;
  final List<BudgetTransaction> comparisonTransactions;
  final StatisticsSummary summary;
  final List<StatisticsGroupStat> categories;
  final List<StatisticsGroupStat> merchants;
  final List<StatisticsDailyPoint> daily;
  final List<StatisticsDailyPoint> comparisonDaily;
  final List<StatisticsPeriodPoint> periods;
  final List<StatisticsAmountBucket> buckets;
  final List<StatisticsWeekdayStat> weekdays;
  final List<BudgetTransaction> largestTransactions;
  final List<BudgetTransaction> recurringTransactions;
  final List<StatisticsInsight> insights;
  final DataQualityReport dataQuality;
}

enum TrackedStatisticsType { category, merchant, account, recurring }

class TrackedStatisticsItem {
  const TrackedStatisticsItem({
    required this.id,
    required this.type,
    required this.label,
    this.isPinned = false,
  });

  final String id;
  final TrackedStatisticsType type;
  final String label;
  final bool isPinned;

  TrackedStatisticsItem copyWith({bool? isPinned}) => TrackedStatisticsItem(
    id: id,
    type: type,
    label: label,
    isPinned: isPinned ?? this.isPinned,
  );
}
