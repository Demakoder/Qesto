import 'dart:math' as math;

import '../../../../data/models/qesto_models.dart';
import '../../../budget/services/cash_flow_calculation_service.dart';
import '../models/statistics_models.dart';
import 'data_quality_service.dart';
import 'statistics_insights_service.dart';

class StatisticsCalculationService {
  const StatisticsCalculationService({
    this.dataQualityService = const DataQualityService(),
    this.insightsService = const StatisticsInsightsService(),
  });

  final DataQualityService dataQualityService;
  final StatisticsInsightsService insightsService;

  bool isConsumerExpense(BudgetTransaction transaction) {
    if (transaction.isPotentialDuplicate && !transaction.isConfirmed) {
      return false;
    }
    return transaction.type == TransactionType.expense ||
        transaction.type == TransactionType.refund ||
        (transaction.type == TransactionType.transfer &&
            transaction.transferDirection == TransferDirection.outgoing &&
            !transaction.tags.contains(qestoInternalTransferTag));
  }

  int signedExpense(BudgetTransaction transaction) =>
      switch (transaction.type) {
        TransactionType.expense => transaction.amount,
        TransactionType.refund => -transaction.amount,
        TransactionType.transfer
            when transaction.transferDirection == TransferDirection.outgoing &&
                !transaction.tags.contains(qestoInternalTransferTag) =>
          transaction.amount,
        _ => 0,
      };

  StatisticsDateRange? comparisonRange(StatisticsQuery query) {
    final ranges = comparisonRanges(query);
    return ranges.isEmpty ? null : ranges.first;
  }

  List<StatisticsDateRange> comparisonRanges(StatisticsQuery query) {
    if (query.comparison == StatisticsComparison.none) return const [];
    if (query.comparison == StatisticsComparison.previousYear) {
      return [
        StatisticsDateRange(
          DateTime(
            query.period.start.year - 1,
            query.period.start.month,
            query.period.start.day,
          ),
          DateTime(
            query.period.end.year - 1,
            query.period.end.month,
            query.period.end.day,
          ),
        ),
      ];
    }
    final averageCount = switch (query.comparison) {
      StatisticsComparison.average3 => 3,
      StatisticsComparison.average6 => 6,
      StatisticsComparison.average12 => 12,
      _ => 1,
    };
    if (averageCount > 1 && query.period.start.day == 1) {
      return [
        for (var offset = 1; offset <= averageCount; offset++)
          StatisticsDateRange(
            DateTime(
              query.period.start.year,
              query.period.start.month - offset,
            ),
            DateTime(
              query.period.start.year,
              query.period.start.month - offset,
            ).add(Duration(days: query.period.dayCount - 1)),
          ),
      ];
    }
    if (query.period.start.day == 1) {
      final previousMonthEnd = DateTime(
        query.period.start.year,
        query.period.start.month,
        0,
      );
      final previousMonthStart = DateTime(
        previousMonthEnd.year,
        previousMonthEnd.month,
      );
      return [
        StatisticsDateRange(
          previousMonthStart,
          previousMonthStart.add(Duration(days: query.period.dayCount - 1)),
        ),
      ];
    }
    final end = query.period.start.subtract(const Duration(days: 1));
    return [
      StatisticsDateRange(
        end.subtract(Duration(days: query.period.dayCount - 1)),
        end,
      ),
    ];
  }

  List<BudgetTransaction> filterTransactions({
    required Iterable<BudgetTransaction> transactions,
    required StatisticsQuery query,
    required StatisticsDateRange range,
    required List<QestoAccount> accounts,
    bool includePotentialDuplicates = false,
  }) {
    final accountTypes = {
      for (final account in accounts) account.id: account.type,
    };
    final result = transactions.where((transaction) {
      if (!range.contains(transaction.date)) return false;
      if (!includePotentialDuplicates &&
          transaction.isPotentialDuplicate &&
          !transaction.isConfirmed) {
        return false;
      }
      if (query.accountIds.isNotEmpty &&
          !query.accountIds.contains(transaction.accountId)) {
        return false;
      }
      if (query.categoryIds.isNotEmpty &&
          !query.categoryIds.contains(transaction.categoryId)) {
        return false;
      }
      if (query.subcategoryIds.isNotEmpty &&
          !query.subcategoryIds.contains(transaction.subcategoryId)) {
        return false;
      }
      if (query.tagIds.isNotEmpty &&
          transaction.tags.toSet().intersection(query.tagIds).isEmpty) {
        return false;
      }
      final merchant = merchantName(transaction);
      if (query.merchantNames.isNotEmpty &&
          !query.merchantNames.contains(merchant)) {
        return false;
      }
      if (query.transactionTypes.isNotEmpty &&
          !query.transactionTypes.contains(transaction.type)) {
        return false;
      }
      if (!query.includeLargePurchases && transaction.isLargePurchase) {
        return false;
      }
      if (!query.includeRecurring && transaction.isRecurring) return false;
      if (!query.includeRefunds && transaction.type == TransactionType.refund) {
        return false;
      }
      if (!query.includeCash &&
          accountTypes[transaction.accountId] == AccountType.cash) {
        return false;
      }
      if (!query.includeUncategorized && transaction.categoryId == null) {
        return false;
      }
      if (query.onlyConfirmed && !transaction.isConfirmed) return false;
      return true;
    }).toList()..sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  int expenses(Iterable<BudgetTransaction> transactions) => transactions
      .where(isConsumerExpense)
      .fold(0, (sum, transaction) => sum + signedExpense(transaction));

  int income(Iterable<BudgetTransaction> transactions) => transactions
      .where((transaction) => transaction.type == TransactionType.income)
      .fold(0, (sum, transaction) => sum + transaction.amount);

  int savings(Iterable<BudgetTransaction> transactions) => transactions
      .where(
        (transaction) => transaction.type == TransactionType.savingsTransfer,
      )
      .fold(0, (sum, transaction) => sum + transaction.amount);

  List<int> purchaseAmounts(Iterable<BudgetTransaction> transactions) =>
      transactions
          .where(isConsumerExpense)
          .where((transaction) => signedExpense(transaction) > 0)
          .map(signedExpense)
          .toList();

  double average(Iterable<int> values) {
    final list = values.toList();
    if (list.isEmpty) return 0;
    return list.reduce((a, b) => a + b) / list.length;
  }

  double median(Iterable<int> values) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) return 0;
    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle].toDouble();
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  double? percentChange(num current, num previous) {
    if (previous == 0) return null;
    return (current - previous) / previous * 100;
  }

  String merchantName(BudgetTransaction transaction) =>
      transaction.normalizedMerchant ??
      transaction.merchant ??
      transaction.title ??
      'Неизвестный продавец';

  List<StatisticsGroupStat> categoryStats({
    required Iterable<BudgetTransaction> current,
    required Iterable<BudgetTransaction> comparison,
    required List<BudgetCategory> categories,
    int comparisonDivisor = 1,
  }) {
    final catalog = {for (final category in categories) category.id: category};
    final currentGroups = _groupExpenses(
      current,
      (item) => item.categoryId ?? 'uncategorized',
    );
    final comparisonGroups = _groupExpenses(
      comparison,
      (item) => item.categoryId ?? 'uncategorized',
    );
    final total = expenses(current);
    final result = <StatisticsGroupStat>[];
    for (final entry in currentGroups.entries) {
      if (entry.value.amount <= 0) continue;
      final category = catalog[entry.key];
      final previous = comparisonGroups[entry.key];
      final previousAmount = (previous?.amount ?? 0) / comparisonDivisor;
      result.add(
        StatisticsGroupStat(
          id: entry.key,
          label: category?.name ?? 'Без категории',
          amount: entry.value.amount,
          count: entry.value.amounts.length,
          averageCheck: average(entry.value.amounts),
          medianCheck: median(entry.value.amounts),
          share: total <= 0 ? 0 : entry.value.amount / total,
          changePercent: percentChange(entry.value.amount, previousAmount),
          colorValue: category?.colorValue ?? 0xFF8A8F9C,
          iconKey: category?.iconKey ?? 'other',
        ),
      );
    }
    result.sort((a, b) => b.amount.compareTo(a.amount));
    return result;
  }

  List<StatisticsGroupStat> merchantStats({
    required Iterable<BudgetTransaction> current,
    required Iterable<BudgetTransaction> comparison,
    int comparisonDivisor = 1,
  }) {
    final currentGroups = _groupExpenses(current, merchantName);
    final comparisonGroups = _groupExpenses(comparison, merchantName);
    final total = expenses(current);
    final result = <StatisticsGroupStat>[];
    for (final entry in currentGroups.entries) {
      if (entry.value.amount <= 0) continue;
      final previous = comparisonGroups[entry.key];
      final previousAmount = (previous?.amount ?? 0) / comparisonDivisor;
      result.add(
        StatisticsGroupStat(
          id: entry.key,
          label: entry.key,
          amount: entry.value.amount,
          count: entry.value.amounts.length,
          averageCheck: average(entry.value.amounts),
          medianCheck: median(entry.value.amounts),
          share: total <= 0 ? 0 : entry.value.amount / total,
          changePercent: percentChange(entry.value.amount, previousAmount),
        ),
      );
    }
    result.sort((a, b) => b.amount.compareTo(a.amount));
    return result;
  }

  Map<String, _ExpenseGroup> _groupExpenses(
    Iterable<BudgetTransaction> transactions,
    String Function(BudgetTransaction) keyOf,
  ) {
    final result = <String, _ExpenseGroup>{};
    for (final transaction in transactions.where(isConsumerExpense)) {
      final key = keyOf(transaction);
      final group = result.putIfAbsent(key, _ExpenseGroup.new);
      group.amount += signedExpense(transaction);
      final amount = signedExpense(transaction);
      if (amount > 0) {
        group.amounts.add(amount);
      }
    }
    return result;
  }

  List<StatisticsDailyPoint> dailyPoints(
    StatisticsDateRange range,
    Iterable<BudgetTransaction> transactions,
  ) {
    final perDay = <DateTime, List<BudgetTransaction>>{};
    for (final transaction in transactions.where(isConsumerExpense)) {
      final day = DateTime(
        transaction.date.year,
        transaction.date.month,
        transaction.date.day,
      );
      perDay.putIfAbsent(day, () => []).add(transaction);
    }
    var cumulative = 0;
    final result = <StatisticsDailyPoint>[];
    for (
      var date = range.start;
      !date.isAfter(range.end);
      date = date.add(const Duration(days: 1))
    ) {
      final dayTransactions = perDay[date] ?? const [];
      final amount = dayTransactions.fold<int>(
        0,
        (sum, item) => sum + signedExpense(item),
      );
      cumulative += amount;
      result.add(
        StatisticsDailyPoint(
          date: date,
          amount: amount,
          cumulative: cumulative,
          count: dayTransactions
              .where((item) => signedExpense(item) > 0)
              .length,
        ),
      );
    }
    return result;
  }

  List<StatisticsAmountBucket> amountBuckets(
    Iterable<BudgetTransaction> transactions,
  ) {
    const labels = [
      'до 300 ₽',
      '300–1 000 ₽',
      '1 000–3 000 ₽',
      '3 000–10 000 ₽',
      'более 10 000 ₽',
    ];
    final counts = List.filled(labels.length, 0);
    final amounts = List.filled(labels.length, 0);
    for (final value in purchaseAmounts(transactions)) {
      final index = value < 300
          ? 0
          : value < 1000
          ? 1
          : value < 3000
          ? 2
          : value < 10000
          ? 3
          : 4;
      counts[index]++;
      amounts[index] += value;
    }
    return [
      for (var i = 0; i < labels.length; i++)
        StatisticsAmountBucket(
          label: labels[i],
          count: counts[i],
          amount: amounts[i],
        ),
    ];
  }

  List<StatisticsWeekdayStat> weekdayStats(
    Iterable<BudgetTransaction> transactions,
  ) {
    final amounts = List.filled(7, 0);
    final counts = List.filled(7, 0);
    final checks = List.generate(7, (_) => <int>[]);
    for (final transaction in transactions.where(isConsumerExpense)) {
      final index = transaction.date.weekday - 1;
      amounts[index] += signedExpense(transaction);
      final amount = signedExpense(transaction);
      if (amount > 0) {
        counts[index]++;
        checks[index].add(amount);
      }
    }
    return [
      for (var index = 0; index < 7; index++)
        StatisticsWeekdayStat(
          weekday: index + 1,
          amount: amounts[index],
          count: counts[index],
          averageCheck: average(checks[index]),
        ),
    ];
  }

  List<StatisticsPeriodPoint> periodPoints({
    required List<BudgetPeriod> periods,
    required Iterable<BudgetTransaction> transactions,
    required DateTime referenceDate,
  }) {
    final result = <StatisticsPeriodPoint>[];
    for (final period in periods.where(
      (period) => !period.startDate.isAfter(referenceDate),
    )) {
      final periodTransactions = transactions
          .where((item) => period.contains(item.date))
          .where((item) => !item.date.isAfter(referenceDate))
          .toList();
      final large = periodTransactions
          .where((item) => isLargePurchase(item, periodTransactions))
          .fold<int>(0, (sum, item) => sum + item.amount);
      result.add(
        StatisticsPeriodPoint(
          period: period,
          expenses: expenses(periodTransactions),
          income: income(periodTransactions),
          plan: period.totalPlan,
          largePurchases: large,
        ),
      );
    }
    return result;
  }

  bool isLargePurchase(
    BudgetTransaction transaction,
    Iterable<BudgetTransaction> context,
  ) {
    if (transaction.isLargePurchase) return true;
    if (!transaction.isConfirmed ||
        !isConsumerExpense(transaction) ||
        signedExpense(transaction) <= 0) {
      return false;
    }
    final ordinary = median(purchaseAmounts(context));
    return transaction.amount >= math.max(10000, ordinary * 3);
  }

  StatisticsSnapshot buildSnapshot({
    required StatisticsQuery query,
    required List<BudgetTransaction> allTransactions,
    required List<BudgetCategory> categories,
    required List<BudgetPeriod> periods,
    required List<QestoAccount> accounts,
    required DateTime referenceDate,
    Set<String> ignoredQualityIssueIds = const {},
  }) {
    final current = filterTransactions(
      transactions: allTransactions,
      query: query,
      range: query.period,
      accounts: accounts,
    );
    final previousRanges = comparisonRanges(query);
    final previousRange = previousRanges.isEmpty ? null : previousRanges.first;
    final previous = <BudgetTransaction>[
      for (final range in previousRanges)
        ...filterTransactions(
          transactions: allTransactions,
          query: query,
          range: range,
          accounts: accounts,
        ),
    ];
    final comparisonDivisor = math.max(previousRanges.length, 1);
    final currentChecks = purchaseAmounts(current);
    final previousChecks = purchaseAmounts(previous);
    final currentExpense = expenses(current);
    final previousExpense = expenses(previous) / comparisonDivisor;
    final currentAverage = average(currentChecks);
    final previousAverage = average(previousChecks);
    final summary = StatisticsSummary(
      expenses: currentExpense,
      income: income(current),
      savings: savings(current),
      purchaseCount: currentChecks.length,
      averageCheck: currentAverage,
      medianCheck: median(currentChecks),
      averageDailyExpense: currentExpense / math.max(query.period.dayCount, 1),
      changePercent: query.comparison == StatisticsComparison.none
          ? null
          : percentChange(currentExpense, previousExpense),
      averageCheckChange: query.comparison == StatisticsComparison.none
          ? null
          : percentChange(currentAverage, previousAverage),
    );
    final categoryValues = categoryStats(
      current: current,
      comparison: previous,
      categories: categories,
      comparisonDivisor: comparisonDivisor,
    );
    final merchantValues = merchantStats(
      current: current,
      comparison: previous,
      comparisonDivisor: comparisonDivisor,
    );
    final qualitySource = filterTransactions(
      transactions: allTransactions,
      query: query,
      range: query.period,
      accounts: accounts,
      includePotentialDuplicates: true,
    );
    final quality = dataQualityService.evaluate(
      transactions: qualitySource,
      accountIds: accounts.map((account) => account.id).toSet(),
      ignoredIssueIds: ignoredQualityIssueIds,
    );
    final largeAmount = current
        .where((item) => isLargePurchase(item, current))
        .fold<int>(0, (sum, item) => sum + signedExpense(item));
    final largest =
        current
            .where(isConsumerExpense)
            .where((item) => signedExpense(item) > 0)
            .toList()
          ..sort((a, b) => signedExpense(b).compareTo(signedExpense(a)));
    final recurring = current.where((item) => item.isRecurring).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return StatisticsSnapshot(
      query: query,
      comparisonRange: previousRange,
      transactions: current,
      comparisonTransactions: previous,
      summary: summary,
      categories: categoryValues,
      merchants: merchantValues,
      daily: dailyPoints(query.period, current),
      comparisonDaily: previousRanges.length != 1
          ? const []
          : dailyPoints(previousRange!, previous),
      periods: periodPoints(
        periods: periods,
        transactions: allTransactions,
        referenceDate: referenceDate,
      ),
      buckets: amountBuckets(current),
      weekdays: weekdayStats(current),
      largestTransactions: largest.take(5).toList(),
      recurringTransactions: recurring,
      insights: insightsService.build(
        summary: summary,
        categories: categoryValues,
        merchants: merchantValues,
        quality: quality,
        largePurchaseAmount: largeAmount,
      ),
      dataQuality: quality,
    );
  }
}

class _ExpenseGroup {
  int amount = 0;
  final List<int> amounts = [];
}
