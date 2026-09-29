import 'dart:math' as math;

import '../../../data/models/qesto_models.dart';
import 'cash_flow_calculation_service.dart';

class BudgetCalculationService {
  const BudgetCalculationService();

  bool isConsumerTransaction(BudgetTransaction transaction) {
    if (transaction.isPotentialDuplicate && !transaction.isConfirmed) {
      return false;
    }
    return transaction.type == TransactionType.expense ||
        transaction.type == TransactionType.refund ||
        (transaction.type == TransactionType.transfer &&
            transaction.transferDirection == TransferDirection.outgoing &&
            !transaction.tags.contains(qestoInternalTransferTag));
  }

  int signedExpense(BudgetTransaction transaction) {
    return switch (transaction.type) {
      TransactionType.expense => transaction.amount,
      TransactionType.refund => -transaction.amount,
      TransactionType.transfer
          when transaction.transferDirection == TransferDirection.outgoing &&
              !transaction.tags.contains(qestoInternalTransferTag) =>
        transaction.amount,
      _ => 0,
    };
  }

  List<BudgetTransaction> transactionsForPeriod(
    BudgetPeriod period,
    Iterable<BudgetTransaction> transactions,
  ) {
    final result =
        transactions
            .where((transaction) => period.contains(transaction.date))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  int currentExpense(
    BudgetPeriod period,
    Iterable<BudgetTransaction> transactions, {
    DateTime? throughDate,
  }) {
    return transactionsForPeriod(period, transactions)
        .where(isConsumerTransaction)
        .where(
          (transaction) =>
              throughDate == null || !transaction.date.isAfter(throughDate),
        )
        .fold(0, (sum, transaction) => sum + signedExpense(transaction));
  }

  int categoryExpense(
    BudgetPeriod period,
    String categoryId,
    Iterable<BudgetTransaction> transactions,
  ) {
    return transactionsForPeriod(period, transactions)
        .where((transaction) => transaction.categoryId == categoryId)
        .fold(0, (sum, transaction) => sum + signedExpense(transaction));
  }

  BudgetSummary summary(
    BudgetPeriod period,
    Iterable<BudgetTransaction> transactions,
    Iterable<BudgetCategory> catalog,
  ) {
    final categoryMap = {for (final category in catalog) category.id: category};
    final amounts = <String, int>{};
    for (final transaction in transactionsForPeriod(period, transactions)) {
      if (!isConsumerTransaction(transaction) ||
          transaction.categoryId == null) {
        continue;
      }
      amounts.update(
        transaction.categoryId!,
        (value) => value + signedExpense(transaction),
        ifAbsent: () => signedExpense(transaction),
      );
    }

    final categories =
        amounts.entries
            .where(
              (entry) => entry.value > 0 && categoryMap.containsKey(entry.key),
            )
            .map((entry) {
              final category = categoryMap[entry.key]!;
              return SpendingCategory(
                id: category.id,
                name: category.shortName ?? category.name,
                amount: entry.value,
                colorValue: category.colorValue,
                iconKey: category.iconKey,
              );
            })
            .toList()
          ..sort((a, b) => b.amount.compareTo(a.amount));

    return BudgetSummary(
      period: period,
      currentExpense: currentExpense(period, transactions),
      categories: categories,
    );
  }

  double planProgress(int spent, int planned) {
    return planned <= 0 ? 0 : spent / planned;
  }

  int plannedAmountAtDate(
    BudgetPeriod period,
    DateTime date,
    Iterable<BudgetPlanPoint> points,
  ) {
    final periodPoints =
        points.where((point) => point.budgetPeriodId == period.id).toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    if (periodPoints.isNotEmpty) {
      var selected = periodPoints.first.cumulativePlannedAmount;
      for (final point in periodPoints) {
        if (point.date.isAfter(date)) break;
        selected = point.cumulativePlannedAmount;
      }
      return selected;
    }

    final elapsed =
        date.difference(period.startDate).inDays.clamp(0, period.dayCount - 1) +
        1;
    return (period.totalPlan * elapsed / period.dayCount).round();
  }

  int allowedDailyExpense(
    BudgetPeriod period,
    int currentExpense,
    DateTime asOfDate,
  ) {
    final remainingBudget = math.max(period.totalPlan - currentExpense, 0);
    if (remainingBudget == 0 || !asOfDate.isBefore(period.endDate)) return 0;
    final remainingDays = period.endDate.difference(asOfDate).inDays;
    return remainingDays <= 0 ? 0 : (remainingBudget / remainingDays).floor();
  }

  List<DailyBudgetPoint> cumulativePoints(
    BudgetPeriod period,
    Iterable<BudgetTransaction> transactions,
    DateTime throughDate,
  ) {
    final end = throughDate.isAfter(period.endDate)
        ? period.endDate
        : throughDate.isBefore(period.startDate)
        ? period.startDate
        : DateTime(throughDate.year, throughDate.month, throughDate.day);
    final daily = <DateTime, int>{};
    for (final transaction in transactionsForPeriod(period, transactions)) {
      if (!isConsumerTransaction(transaction) ||
          transaction.date.isAfter(end)) {
        continue;
      }
      final day = DateTime(
        transaction.date.year,
        transaction.date.month,
        transaction.date.day,
      );
      daily.update(
        day,
        (value) => value + signedExpense(transaction),
        ifAbsent: () => signedExpense(transaction),
      );
    }

    var running = 0;
    final points = <DailyBudgetPoint>[];
    for (
      var day = period.startDate;
      !day.isAfter(end);
      day = day.add(const Duration(days: 1))
    ) {
      running += daily[day] ?? 0;
      points.add(DailyBudgetPoint(date: day, amount: running.toDouble()));
    }
    return points;
  }
}
