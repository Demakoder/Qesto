import 'dart:math' as math;

import '../../../data/models/qesto_models.dart';
import '../../budget/services/cash_flow_calculation_service.dart';
import '../../profile/services/cbr_currency_service.dart';

enum DebtAnalyticsPeriod { oneMonth, threeMonths, sixMonths, oneYear, all }

extension DebtAnalyticsPeriodValue on DebtAnalyticsPeriod {
  String get label => switch (this) {
    DebtAnalyticsPeriod.oneMonth => '1М',
    DebtAnalyticsPeriod.threeMonths => '3М',
    DebtAnalyticsPeriod.sixMonths => '6М',
    DebtAnalyticsPeriod.oneYear => '1Г',
    DebtAnalyticsPeriod.all => 'Всё',
  };

  int? get days => switch (this) {
    DebtAnalyticsPeriod.oneMonth => 30,
    DebtAnalyticsPeriod.threeMonths => 91,
    DebtAnalyticsPeriod.sixMonths => 183,
    DebtAnalyticsPeriod.oneYear => 365,
    DebtAnalyticsPeriod.all => null,
  };
}

class DebtTrendPoint {
  const DebtTrendPoint({
    required this.date,
    required this.totalBalance,
    required this.isConfirmed,
  });

  final DateTime date;
  final int totalBalance;
  final bool isConfirmed;
}

class UpcomingDebtPayment {
  const UpcomingDebtPayment({
    required this.debtId,
    required this.title,
    required this.creditor,
    required this.type,
    required this.date,
    required this.amount,
    required this.currency,
    required this.confidence,
  });

  final String debtId;
  final String title;
  final String? creditor;
  final DebtType type;
  final DateTime date;
  final int amount;
  final String currency;
  final double confidence;
}

class DebtStructureItem {
  const DebtStructureItem({
    required this.type,
    required this.amount,
    required this.share,
  });

  final DebtType type;
  final int amount;
  final double share;
}

class DebtPayoffProjection {
  const DebtPayoffProjection({
    required this.payoffDate,
    required this.months,
    required this.totalInterest,
    required this.isEstimated,
  });

  final DateTime payoffDate;
  final int months;
  final int? totalInterest;
  final bool isEstimated;
}

class DebtPrepaymentSimulation {
  const DebtPrepaymentSimulation({
    required this.payoffDate,
    required this.months,
    required this.monthsSaved,
    required this.interestSaved,
    required this.monthlyPayment,
  });

  final DateTime payoffDate;
  final int months;
  final int? monthsSaved;
  final int? interestSaved;
  final int monthlyPayment;
}

class OneTimePrepaymentSimulation {
  const OneTimePrepaymentSimulation({
    required this.amount,
    required this.reduceTerm,
    required this.reducePayment,
  });

  final int amount;
  final DebtPrepaymentSimulation reduceTerm;
  final DebtPrepaymentSimulation reducePayment;
}

class DebtAccountInsight {
  const DebtAccountInsight({
    required this.debt,
    required this.balanceBaseCurrency,
    required this.payoff,
    required this.utilization,
    required this.paidPrincipal,
    required this.paidInterest,
  });

  final DebtAccount debt;
  final int balanceBaseCurrency;
  final DebtPayoffProjection? payoff;
  final double? utilization;
  final int? paidPrincipal;
  final int? paidInterest;
}

class DebtPortfolioSnapshot {
  const DebtPortfolioSnapshot({
    required this.baseCurrency,
    required this.totalDebt,
    required this.trend,
    required this.change,
    required this.changePercent,
    required this.monthlyDebtPayments,
    required this.hasCompletePaymentData,
    required this.averageMonthlyIncome,
    required this.debtPaymentToIncomeRatio,
    required this.monthlyInterestCost,
    required this.hasCompleteInterestData,
    required this.weightedAverageInterestRate,
    required this.nextPayments,
    required this.next30DaysDebtPayments,
    required this.structure,
    required this.debts,
    required this.portfolioDebtFreeDate,
    required this.securedDebt,
    required this.unsecuredDebt,
    required this.creditCardDebt,
    required this.paidPrincipal,
    required this.paidInterest,
    required this.hasUnconvertedCurrencies,
  });

  final String baseCurrency;
  final int totalDebt;
  final List<DebtTrendPoint> trend;
  final int? change;
  final double? changePercent;
  final int monthlyDebtPayments;
  final bool hasCompletePaymentData;
  final int? averageMonthlyIncome;
  final double? debtPaymentToIncomeRatio;
  final int? monthlyInterestCost;
  final bool hasCompleteInterestData;
  final double? weightedAverageInterestRate;
  final List<UpcomingDebtPayment> nextPayments;
  final int next30DaysDebtPayments;
  final List<DebtStructureItem> structure;
  final List<DebtAccountInsight> debts;
  final DateTime? portfolioDebtFreeDate;
  final int securedDebt;
  final int unsecuredDebt;
  final int creditCardDebt;
  final int? paidPrincipal;
  final int? paidInterest;
  final bool hasUnconvertedCurrencies;
}

class DebtAnalyticsService {
  const DebtAnalyticsService();

  static const _cashFlow = CashFlowCalculationService();

  DebtPortfolioSnapshot calculate({
    required List<DebtAccount> debts,
    required List<DebtBalanceSnapshot> balanceSnapshots,
    required List<DebtPayment> debtPayments,
    required List<BudgetTransaction> transactions,
    required DateTime asOf,
    required DebtAnalyticsPeriod period,
    required String baseCurrency,
  }) {
    final day = _day(asOf);
    final active = debts.where((item) => item.isOpen).toList(growable: false);
    var hasUnconvertedCurrencies = false;
    int? convert(int amount, String currency) {
      final value = _convert(amount, currency, baseCurrency);
      if (value == null) hasUnconvertedCurrencies = true;
      return value;
    }

    final total = active.fold<int>(
      0,
      (sum, item) => sum + (convert(item.currentBalance, item.currency) ?? 0),
    );
    final trend = _aggregateTrend(
      active,
      balanceSnapshots,
      day,
      period,
      convert,
      total,
    );
    final change = trend.length < 2
        ? null
        : trend.last.totalBalance - trend.first.totalBalance;
    final startBalance = trend.isEmpty ? 0 : trend.first.totalBalance;

    final insights = active
        .map((debt) {
          final converted = convert(debt.currentBalance, debt.currency) ?? 0;
          final payments = debtPayments.where((item) => item.debtId == debt.id);
          final paidPrincipalValues = payments
              .map((item) => item.principalAmount)
              .whereType<int>()
              .toList(growable: false);
          final paidInterestValues = payments
              .map((item) => item.interestAmount)
              .whereType<int>()
              .toList(growable: false);
          return DebtAccountInsight(
            debt: debt,
            balanceBaseCurrency: converted,
            payoff: projectedPayoffDate(debt, asOf: day),
            utilization: debt.creditCardDetails?.utilization(
              debt.currentBalance,
            ),
            paidPrincipal: paidPrincipalValues.isEmpty
                ? debt.originalPrincipal == null
                      ? null
                      : math.max(
                          0,
                          debt.originalPrincipal! - debt.currentBalance,
                        )
                : paidPrincipalValues.fold<int>(0, (sum, item) => sum + item),
            paidInterest: paidInterestValues.isEmpty
                ? null
                : paidInterestValues.fold<int>(0, (sum, item) => sum + item),
          );
        })
        .toList(growable: false);

    final debtsWithBalances = active.where((item) => item.currentBalance > 0);
    final hasCompletePaymentData = debtsWithBalances.every(
      (item) => _scheduledPayment(item) != null,
    );
    final monthlyPayments = active.fold<int>(0, (sum, item) {
      final payment = _scheduledPayment(item);
      return sum + (payment == null ? 0 : convert(payment, item.currency) ?? 0);
    });
    final averageIncome = _averageMonthlyIncome(transactions, day, convert);
    final interestCosts = <int>[];
    var hasCompleteInterestData = true;
    var weightedRateNumerator = 0.0;
    var weightedRateBalance = 0;
    for (final debt in active) {
      final rate = _effectiveRate(debt);
      final convertedBalance = convert(debt.currentBalance, debt.currency);
      if (convertedBalance == null) continue;
      if (rate == null) {
        if (debt.currentBalance > 0) hasCompleteInterestData = false;
        continue;
      }
      interestCosts.add((convertedBalance * rate / 1200).round());
      weightedRateNumerator += convertedBalance * rate;
      weightedRateBalance += convertedBalance;
    }
    final upcoming = getNextPayments(active, asOf: day, days: 30);
    final upcomingTotal = upcoming.fold<int>(
      0,
      (sum, item) => sum + (convert(item.amount, item.currency) ?? 0),
    );
    final structureTotals = <DebtType, int>{};
    for (final insight in insights) {
      structureTotals.update(
        insight.debt.type,
        (value) => value + insight.balanceBaseCurrency,
        ifAbsent: () => insight.balanceBaseCurrency,
      );
    }
    final structure =
        structureTotals.entries
            .where((entry) => entry.value > 0)
            .map(
              (entry) => DebtStructureItem(
                type: entry.key,
                amount: entry.value,
                share: total == 0 ? 0 : entry.value / total,
              ),
            )
            .toList()
          ..sort((left, right) => right.amount.compareTo(left.amount));
    final payoffDates = insights
        .map((item) => item.payoff?.payoffDate)
        .whereType<DateTime>()
        .toList(growable: false);
    final principalValues = insights
        .map((item) => item.paidPrincipal)
        .whereType<int>()
        .toList(growable: false);
    final interestValues = insights
        .map((item) => item.paidInterest)
        .whereType<int>()
        .toList(growable: false);
    int totalBy(bool Function(DebtType type) accepts) => insights
        .where((item) => accepts(item.debt.type))
        .fold(0, (sum, item) => sum + item.balanceBaseCurrency);

    return DebtPortfolioSnapshot(
      baseCurrency: baseCurrency,
      totalDebt: total,
      trend: trend,
      change: change,
      changePercent: change == null || startBalance == 0
          ? null
          : change / startBalance.abs() * 100,
      monthlyDebtPayments: monthlyPayments,
      hasCompletePaymentData: hasCompletePaymentData,
      averageMonthlyIncome: averageIncome,
      debtPaymentToIncomeRatio:
          !hasCompletePaymentData ||
              averageIncome == null ||
              averageIncome <= 0 ||
              monthlyPayments == 0
          ? null
          : monthlyPayments / averageIncome,
      monthlyInterestCost: !hasCompleteInterestData || interestCosts.isEmpty
          ? null
          : interestCosts.fold<int>(0, (sum, item) => sum + item),
      hasCompleteInterestData: hasCompleteInterestData,
      weightedAverageInterestRate:
          !hasCompleteInterestData || weightedRateBalance == 0
          ? null
          : weightedRateNumerator / weightedRateBalance,
      nextPayments: upcoming,
      next30DaysDebtPayments: upcomingTotal,
      structure: structure,
      debts: insights,
      portfolioDebtFreeDate:
          payoffDates.length != insights.length || payoffDates.isEmpty
          ? null
          : payoffDates.reduce(
              (left, right) => left.isAfter(right) ? left : right,
            ),
      securedDebt: totalBy(
        (type) => type == DebtType.mortgage || type == DebtType.autoLoan,
      ),
      unsecuredDebt: totalBy(
        (type) => type != DebtType.mortgage && type != DebtType.autoLoan,
      ),
      creditCardDebt: totalBy((type) => type == DebtType.creditCard),
      paidPrincipal: principalValues.isEmpty
          ? null
          : principalValues.fold<int>(0, (sum, item) => sum + item),
      paidInterest: interestValues.isEmpty
          ? null
          : interestValues.fold<int>(0, (sum, item) => sum + item),
      hasUnconvertedCurrencies: hasUnconvertedCurrencies,
    );
  }

  List<UpcomingDebtPayment> getNextPayments(
    Iterable<DebtAccount> debts, {
    required DateTime asOf,
    int days = 30,
  }) {
    final end = _day(asOf).add(Duration(days: days));
    final values = <UpcomingDebtPayment>[];
    for (final debt in debts.where((item) => item.isOpen)) {
      final amount = _scheduledPayment(debt);
      if (amount == null || amount <= 0) continue;
      final date = _nextPaymentDate(debt, _day(asOf));
      if (date == null || date.isAfter(end)) continue;
      values.add(
        UpcomingDebtPayment(
          debtId: debt.id,
          title: debt.name,
          creditor: debt.institutionName,
          type: debt.type,
          date: date,
          amount: amount,
          currency: debt.currency,
          confidence: debt.confidence,
        ),
      );
    }
    values.sort((left, right) => left.date.compareTo(right.date));
    return values;
  }

  DebtPayoffProjection? projectedPayoffDate(
    DebtAccount debt, {
    required DateTime asOf,
    int extraMonthlyPayment = 0,
  }) {
    if (debt.currentBalance <= 0) {
      return DebtPayoffProjection(
        payoffDate: _day(asOf),
        months: 0,
        totalInterest: 0,
        isEstimated: true,
      );
    }
    final payment = _scheduledPayment(debt);
    if (payment == null || payment + extraMonthlyPayment <= 0) {
      if (debt.plannedEndDate == null) return null;
      return DebtPayoffProjection(
        payoffDate: debt.plannedEndDate!,
        months: _monthsBetween(asOf, debt.plannedEndDate!),
        totalInterest: null,
        isEstimated: true,
      );
    }
    return _amortize(
      balance: debt.currentBalance,
      annualRate: _effectiveRate(debt),
      monthlyPayment: payment + extraMonthlyPayment,
      asOf: asOf,
    );
  }

  DebtPrepaymentSimulation? simulateExtraMonthlyPayment(
    DebtAccount debt, {
    required DateTime asOf,
    required int extraMonthlyPayment,
  }) {
    if (extraMonthlyPayment < 0) return null;
    final scheduled = _scheduledPayment(debt);
    final baseline = projectedPayoffDate(debt, asOf: asOf);
    final changed = projectedPayoffDate(
      debt,
      asOf: asOf,
      extraMonthlyPayment: extraMonthlyPayment,
    );
    if (scheduled == null || changed == null) return null;
    return DebtPrepaymentSimulation(
      payoffDate: changed.payoffDate,
      months: changed.months,
      monthsSaved: baseline == null
          ? null
          : math.max(0, baseline.months - changed.months),
      interestSaved:
          baseline?.totalInterest == null || changed.totalInterest == null
          ? null
          : math.max(0, baseline!.totalInterest! - changed.totalInterest!),
      monthlyPayment: scheduled + extraMonthlyPayment,
    );
  }

  OneTimePrepaymentSimulation? simulateOneTimePrepayment(
    DebtAccount debt, {
    required DateTime asOf,
    required int amount,
  }) {
    final scheduled = _scheduledPayment(debt);
    final baseline = projectedPayoffDate(debt, asOf: asOf);
    if (amount <= 0 || scheduled == null || baseline == null) return null;
    final reducedBalance = math.max(0, debt.currentBalance - amount);
    final reduceTermProjection = _amortize(
      balance: reducedBalance,
      annualRate: _effectiveRate(debt),
      monthlyPayment: scheduled,
      asOf: asOf,
    );
    if (reduceTermProjection == null) return null;
    final reducedPayment = _paymentForMonths(
      reducedBalance,
      _effectiveRate(debt),
      math.max(1, baseline.months),
    );
    final reducePaymentProjection = _amortize(
      balance: reducedBalance,
      annualRate: _effectiveRate(debt),
      monthlyPayment: reducedPayment,
      asOf: asOf,
    );
    if (reducePaymentProjection == null) return null;
    DebtPrepaymentSimulation result(DebtPayoffProjection value, int payment) =>
        DebtPrepaymentSimulation(
          payoffDate: value.payoffDate,
          months: value.months,
          monthsSaved: math.max(0, baseline.months - value.months),
          interestSaved:
              baseline.totalInterest == null || value.totalInterest == null
              ? null
              : math.max(0, baseline.totalInterest! - value.totalInterest!),
          monthlyPayment: payment,
        );
    return OneTimePrepaymentSimulation(
      amount: amount,
      reduceTerm: result(reduceTermProjection, scheduled),
      reducePayment: result(reducePaymentProjection, reducedPayment),
    );
  }

  List<DebtTrendPoint> _aggregateTrend(
    List<DebtAccount> debts,
    List<DebtBalanceSnapshot> snapshots,
    DateTime asOf,
    DebtAnalyticsPeriod period,
    int? Function(int amount, String currency) convert,
    int currentTotal,
  ) {
    final start = period.days == null
        ? null
        : asOf.subtract(Duration(days: period.days!));
    final byDebt = <String, List<DebtBalanceSnapshot>>{};
    for (final snapshot in snapshots) {
      if (debts.every((item) => item.id != snapshot.debtId) ||
          snapshot.date.isAfter(asOf) ||
          (start != null && snapshot.date.isBefore(start))) {
        continue;
      }
      byDebt.putIfAbsent(snapshot.debtId, () => []).add(snapshot);
    }
    for (final values in byDebt.values) {
      values.sort((left, right) => left.date.compareTo(right.date));
    }
    final dates =
        byDebt.values
            .expand((items) => items.map((item) => _day(item.date)))
            .toSet()
            .toList()
          ..sort();
    final result = <DebtTrendPoint>[];
    for (final date in dates) {
      var sum = 0;
      var complete = true;
      for (final debt in debts) {
        final known = (byDebt[debt.id] ?? const <DebtBalanceSnapshot>[])
            .where((item) => !_day(item.date).isAfter(date))
            .lastOrNull;
        if (known == null) {
          complete = false;
          break;
        }
        final value = convert(known.totalBalance, debt.currency);
        if (value == null) {
          complete = false;
          break;
        }
        sum += value;
      }
      if (complete) {
        result.add(
          DebtTrendPoint(date: date, totalBalance: sum, isConfirmed: true),
        );
      }
    }
    if (result.isEmpty || result.last.date != asOf) {
      result.add(
        DebtTrendPoint(
          date: asOf,
          totalBalance: currentTotal,
          isConfirmed: true,
        ),
      );
    }
    return result;
  }

  int? _averageMonthlyIncome(
    List<BudgetTransaction> transactions,
    DateTime asOf,
    int? Function(int amount, String currency) convert,
  ) {
    final start = asOf.subtract(const Duration(days: 183));
    final values = transactions.where(
      (item) =>
          !item.date.isBefore(start) &&
          !item.date.isAfter(asOf) &&
          item.type != TransactionType.refund &&
          _cashFlow.treatment(item) == CashFlowTreatment.externalInflow,
    );
    final list = values.toList(growable: false);
    if (list.length < 2) return null;
    final dates = list.map((item) => _day(item.date)).toList()..sort();
    final span = asOf.difference(dates.first).inDays + 1;
    if (span < 14) return null;
    final total = list.fold<int>(
      0,
      (sum, item) => sum + (convert(item.amount, item.currency) ?? 0),
    );
    return (total / span * 30.4375).round();
  }

  DebtPayoffProjection? _amortize({
    required int balance,
    required double? annualRate,
    required int monthlyPayment,
    required DateTime asOf,
  }) {
    if (balance <= 0) {
      return DebtPayoffProjection(
        payoffDate: _day(asOf),
        months: 0,
        totalInterest: 0,
        isEstimated: true,
      );
    }
    if (monthlyPayment <= 0) return null;
    final monthlyRate = (annualRate ?? 0) / 1200;
    if (monthlyRate > 0 && monthlyPayment <= balance * monthlyRate) return null;
    var remaining = balance.toDouble();
    var interest = 0.0;
    var months = 0;
    while (remaining > 0.5 && months < 1200) {
      final currentInterest = remaining * monthlyRate;
      interest += currentInterest;
      remaining = math.max(0, remaining + currentInterest - monthlyPayment);
      months++;
    }
    if (months >= 1200) return null;
    return DebtPayoffProjection(
      payoffDate: _addMonths(_day(asOf), months),
      months: months,
      totalInterest: annualRate == null ? null : interest.round(),
      isEstimated: true,
    );
  }

  int _paymentForMonths(int balance, double? annualRate, int months) {
    if (balance <= 0) return 0;
    final rate = (annualRate ?? 0) / 1200;
    if (rate == 0) return (balance / months).ceil();
    final factor = math.pow(1 + rate, months).toDouble();
    return (balance * rate * factor / (factor - 1)).ceil();
  }

  int? _scheduledPayment(DebtAccount debt) => debt.type == DebtType.creditCard
      ? debt.creditCardDetails?.minimumPayment ?? debt.monthlyPayment
      : debt.monthlyPayment;

  double? _effectiveRate(DebtAccount debt) => debt.type == DebtType.creditCard
      ? debt.creditCardDetails?.interestRateAfterGrace ??
            debt.effectiveRate ??
            debt.interestRate
      : debt.effectiveRate ?? debt.interestRate;

  DateTime? _nextPaymentDate(DebtAccount debt, DateTime asOf) {
    var date = debt.type == DebtType.creditCard
        ? debt.creditCardDetails?.graceDeadline ?? debt.nextPaymentDate
        : debt.nextPaymentDate;
    if (date != null) {
      var normalizedDate = _day(date);
      while (normalizedDate.isBefore(asOf)) {
        normalizedDate = _addMonths(normalizedDate, 1);
      }
      return normalizedDate;
    }
    final paymentDay = debt.paymentDay;
    if (paymentDay == null) return null;
    var candidate = _dateWithSafeDay(asOf.year, asOf.month, paymentDay);
    if (candidate.isBefore(asOf)) {
      candidate = _dateWithSafeDay(asOf.year, asOf.month + 1, paymentDay);
    }
    return candidate;
  }

  int? _convert(int amount, String from, String to) {
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

  DateTime _dateWithSafeDay(int year, int month, int day) {
    final first = DateTime(year, month);
    final lastDay = DateTime(first.year, first.month + 1, 0).day;
    return DateTime(first.year, first.month, day.clamp(1, lastDay));
  }

  DateTime _addMonths(DateTime value, int months) =>
      _dateWithSafeDay(value.year, value.month + months, value.day);

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
}
