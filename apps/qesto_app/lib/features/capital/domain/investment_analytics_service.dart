import 'dart:math' as math;

import '../../../data/models/qesto_models.dart';
import '../../profile/services/cbr_currency_service.dart';

enum InvestmentPeriod { oneMonth, threeMonths, sixMonths, oneYear, all }

extension InvestmentPeriodLabel on InvestmentPeriod {
  String get label => switch (this) {
    InvestmentPeriod.oneMonth => '1М',
    InvestmentPeriod.threeMonths => '3М',
    InvestmentPeriod.sixMonths => '6М',
    InvestmentPeriod.oneYear => '1Г',
    InvestmentPeriod.all => 'Всё',
  };

  int? get months => switch (this) {
    InvestmentPeriod.oneMonth => 1,
    InvestmentPeriod.threeMonths => 3,
    InvestmentPeriod.sixMonths => 6,
    InvestmentPeriod.oneYear => 12,
    InvestmentPeriod.all => null,
  };
}

enum InvestmentFreshness { current, aging, stale }

class InvestmentBalancePoint {
  const InvestmentBalancePoint({required this.date, required this.balance});
  final DateTime date;
  final int balance;
}

class InvestmentMonthlyContribution {
  const InvestmentMonthlyContribution({
    required this.month,
    required this.contributions,
    required this.withdrawals,
  });
  final DateTime month;
  final int contributions;
  final int withdrawals;
  int get net => contributions - withdrawals;
}

class InvestmentAccountInsight {
  const InvestmentAccountInsight({
    required this.account,
    required this.balanceBaseCurrency,
    required this.history,
    required this.change,
    required this.contributions,
    required this.withdrawals,
    required this.netContributions,
    required this.differenceFromRecordedFlows,
    required this.freshness,
  });

  final InvestmentAccount account;
  final int balanceBaseCurrency;
  final List<InvestmentBalancePoint> history;
  final int? change;
  final int contributions;
  final int withdrawals;
  final int netContributions;
  final int? differenceFromRecordedFlows;
  final InvestmentFreshness freshness;
}

class InvestmentPortfolioSnapshot {
  const InvestmentPortfolioSnapshot({
    required this.baseCurrency,
    required this.totalBalance,
    required this.change,
    required this.history,
    required this.investedThisMonth,
    required this.contributedThreeMonths,
    required this.contributedTwelveMonths,
    required this.averageMonthlyContribution,
    required this.withdrawnTwelveMonths,
    required this.monthlyContributions,
    required this.monthlyPlan,
    required this.monthlyPlanProgress,
    required this.monthlyPlanRemaining,
    required this.accounts,
    required this.hasUnconvertedCurrencies,
  });

  final String baseCurrency;
  final int totalBalance;
  final int? change;
  final List<InvestmentBalancePoint> history;
  final int investedThisMonth;
  final int contributedThreeMonths;
  final int contributedTwelveMonths;
  final int averageMonthlyContribution;
  final int withdrawnTwelveMonths;
  final List<InvestmentMonthlyContribution> monthlyContributions;
  final int monthlyPlan;
  final double monthlyPlanProgress;
  final int monthlyPlanRemaining;
  final List<InvestmentAccountInsight> accounts;
  final bool hasUnconvertedCurrencies;
}

class InvestmentAnalyticsService {
  const InvestmentAnalyticsService();

  InvestmentPortfolioSnapshot calculate({
    required List<InvestmentAccount> accounts,
    required List<InvestmentBalanceSnapshot> balanceSnapshots,
    required List<InvestmentContribution> contributions,
    required DateTime asOf,
    required InvestmentPeriod period,
    required String baseCurrency,
  }) {
    final today = _day(asOf);
    final active = accounts
        .where((item) => item.isActive && item.includeInTotal)
        .toList(growable: false);
    var hasUnconverted = false;
    int convert(int amount, String from) {
      final result = convertAmount(amount, from, baseCurrency);
      if (result == null) hasUnconverted = true;
      return result ?? 0;
    }

    final start = period.months == null
        ? null
        : DateTime(today.year, today.month - period.months!, today.day);
    final history = _portfolioHistory(
      accounts: active,
      snapshots: balanceSnapshots,
      start: start,
      asOf: today,
      convert: convert,
    );
    final total = active.fold<int>(
      0,
      (sum, item) => sum + convert(item.currentBalance, item.currency),
    );
    final change = history.length < 2 ? null : total - history.first.balance;
    final monthStart = DateTime(today.year, today.month);
    final threeStart = DateTime(today.year, today.month - 2);
    final twelveStart = DateTime(today.year, today.month - 11);

    int contributionTotal(
      DateTime from,
      InvestmentContributionType type,
    ) => contributions
        .where(
          (item) =>
              active.any((account) => account.id == item.investmentAccountId) &&
              !_day(item.date).isBefore(from) &&
              !_day(item.date).isAfter(today) &&
              item.type == type,
        )
        .fold<int>(0, (sum, item) => sum + convert(item.amount, item.currency));

    final monthly = <InvestmentMonthlyContribution>[];
    for (var offset = 11; offset >= 0; offset--) {
      final month = DateTime(today.year, today.month - offset);
      final next = DateTime(month.year, month.month + 1);
      var deposits = 0;
      var withdrawals = 0;
      for (final item in contributions.where(
        (entry) =>
            active.any((account) => account.id == entry.investmentAccountId) &&
            !entry.date.isBefore(month) &&
            entry.date.isBefore(next),
      )) {
        final amount = convert(item.amount, item.currency);
        if (item.type == InvestmentContributionType.contribution) {
          deposits += amount;
        } else {
          withdrawals += amount;
        }
      }
      monthly.add(
        InvestmentMonthlyContribution(
          month: month,
          contributions: deposits,
          withdrawals: withdrawals,
        ),
      );
    }

    final earliestContribution = contributions
        .where(
          (item) =>
              active.any((account) => account.id == item.investmentAccountId),
        )
        .map((item) => item.date)
        .fold<DateTime?>(
          null,
          (earliest, item) =>
              earliest == null || item.isBefore(earliest) ? item : earliest,
        );
    final observedMonths = earliestContribution == null
        ? 0
        : math.min(
            12,
            math.max(
              1,
              (today.year - earliestContribution.year) * 12 +
                  today.month -
                  earliestContribution.month +
                  1,
            ),
          );
    final investedThisMonth = contributionTotal(
      monthStart,
      InvestmentContributionType.contribution,
    );
    final twelve = contributionTotal(
      twelveStart,
      InvestmentContributionType.contribution,
    );
    final plan = active.fold<int>(0, (sum, item) {
      final value = item.plan;
      if (value == null || !value.enabled) return sum;
      return sum + convert(value.amount, item.currency);
    });

    final accountInsights =
        accounts
            .where((item) => item.status != InvestmentAccountStatus.archived)
            .map((account) {
              final accountSnapshots =
                  balanceSnapshots
                      .where((item) => item.investmentAccountId == account.id)
                      .toList()
                    ..sort((left, right) => left.date.compareTo(right.date));
              final shown = accountSnapshots
                  .where(
                    (item) => start == null || !_day(item.date).isBefore(start),
                  )
                  .map(
                    (item) => InvestmentBalancePoint(
                      date: _day(item.date),
                      balance: convert(item.balance, item.currency),
                    ),
                  )
                  .toList(growable: false);
              final flows = contributions
                  .where((item) => item.investmentAccountId == account.id)
                  .toList(growable: false);
              final deposits = flows
                  .where(
                    (item) =>
                        item.type == InvestmentContributionType.contribution,
                  )
                  .fold<int>(0, (sum, item) => sum + item.amount);
              final withdrawn = flows
                  .where(
                    (item) =>
                        item.type == InvestmentContributionType.withdrawal,
                  )
                  .fold<int>(0, (sum, item) => sum + item.amount);
              final first = accountSnapshots.firstOrNull;
              final hasBaseline = accountSnapshots.length >= 2;
              final laterNet = !hasBaseline || first == null
                  ? null
                  : flows
                        .where(
                          (item) => item.createdAt.isAfter(first.createdAt),
                        )
                        .fold<int>(
                          0,
                          (sum, item) =>
                              item.type ==
                                  InvestmentContributionType.contribution
                              ? sum + item.amount
                              : sum - item.amount,
                        );
              return InvestmentAccountInsight(
                account: account,
                balanceBaseCurrency: convert(
                  account.currentBalance,
                  account.currency,
                ),
                history: shown,
                change: shown.length < 2
                    ? null
                    : convert(account.currentBalance, account.currency) -
                          shown.first.balance,
                contributions: deposits,
                withdrawals: withdrawn,
                netContributions: deposits - withdrawn,
                differenceFromRecordedFlows: !hasBaseline || first == null
                    ? null
                    : account.currentBalance - first.balance - (laterNet ?? 0),
                freshness: freshness(account, today),
              );
            })
            .toList(growable: false)
          ..sort(
            (left, right) =>
                right.balanceBaseCurrency.compareTo(left.balanceBaseCurrency),
          );

    return InvestmentPortfolioSnapshot(
      baseCurrency: baseCurrency,
      totalBalance: total,
      change: change,
      history: history,
      investedThisMonth: investedThisMonth,
      contributedThreeMonths: contributionTotal(
        threeStart,
        InvestmentContributionType.contribution,
      ),
      contributedTwelveMonths: twelve,
      averageMonthlyContribution: observedMonths == 0
          ? 0
          : (twelve / observedMonths).round(),
      withdrawnTwelveMonths: contributionTotal(
        twelveStart,
        InvestmentContributionType.withdrawal,
      ),
      monthlyContributions: monthly,
      monthlyPlan: plan,
      monthlyPlanProgress: plan <= 0
          ? 0
          : (investedThisMonth / plan).clamp(0, 1),
      monthlyPlanRemaining: math.max(0, plan - investedThisMonth),
      accounts: accountInsights,
      hasUnconvertedCurrencies: hasUnconverted,
    );
  }

  InvestmentFreshness freshness(InvestmentAccount account, DateTime asOf) {
    final days = _day(
      asOf,
    ).difference(_day(account.lastBalanceUpdateAt)).inDays;
    if (days <= 7) return InvestmentFreshness.current;
    if (days <= 30) return InvestmentFreshness.aging;
    return InvestmentFreshness.stale;
  }

  int? convertAmount(int amount, String from, String to) {
    if (from == to) return amount;
    final rates = CbrCurrencyService.embeddedSnapshot.rates;
    final fromRate = rates[from]?.rublesPerUnit;
    final toRate = rates[to]?.rublesPerUnit;
    if (fromRate == null || toRate == null) return null;
    return (amount * fromRate / toRate).round();
  }

  List<InvestmentBalancePoint> _portfolioHistory({
    required List<InvestmentAccount> accounts,
    required List<InvestmentBalanceSnapshot> snapshots,
    required DateTime? start,
    required DateTime asOf,
    required int Function(int amount, String currency) convert,
  }) {
    final dates =
        snapshots
            .where(
              (item) =>
                  accounts.any(
                    (account) => account.id == item.investmentAccountId,
                  ) &&
                  (start == null || !_day(item.date).isBefore(start)) &&
                  !_day(item.date).isAfter(asOf),
            )
            .map((item) => _day(item.date))
            .toSet()
            .toList()
          ..sort();
    final result = <InvestmentBalancePoint>[];
    for (final date in dates) {
      var total = 0;
      var hasValue = false;
      for (final account in accounts) {
        final available =
            snapshots
                .where(
                  (item) =>
                      item.investmentAccountId == account.id &&
                      !_day(item.date).isAfter(date),
                )
                .toList()
              ..sort((left, right) => right.date.compareTo(left.date));
        final snapshot = available.firstOrNull;
        if (snapshot != null) {
          total += convert(snapshot.balance, snapshot.currency);
          hasValue = true;
        }
      }
      if (hasValue) {
        result.add(InvestmentBalancePoint(date: date, balance: total));
      }
    }
    if (accounts.isNotEmpty &&
        (result.isEmpty || result.last.date.isBefore(asOf))) {
      result.add(
        InvestmentBalancePoint(
          date: asOf,
          balance: accounts.fold<int>(
            0,
            (sum, item) => sum + convert(item.currentBalance, item.currency),
          ),
        ),
      );
    }
    return result;
  }

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
}
