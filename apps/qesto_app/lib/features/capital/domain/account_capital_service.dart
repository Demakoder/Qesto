import 'dart:math' as math;

import '../../../data/models/qesto_models.dart';
import '../../budget/services/cash_flow_calculation_service.dart';
import 'debt_analytics_service.dart';
import '../../../features/profile/services/cbr_currency_service.dart';
import '../../../synoball/core/models.dart';

enum CapitalPeriod { oneMonth, threeMonths, sixMonths, oneYear, all }

extension CapitalPeriodValue on CapitalPeriod {
  String get label => switch (this) {
    CapitalPeriod.oneMonth => '1М',
    CapitalPeriod.threeMonths => '3М',
    CapitalPeriod.sixMonths => '6М',
    CapitalPeriod.oneYear => '1Г',
    CapitalPeriod.all => 'Всё',
  };

  int? get days => switch (this) {
    CapitalPeriod.oneMonth => 30,
    CapitalPeriod.threeMonths => 91,
    CapitalPeriod.sixMonths => 183,
    CapitalPeriod.oneYear => 365,
    CapitalPeriod.all => null,
  };
}

enum AccountDataStatus { current, needsUpdate, partial, manual }

enum LowBalanceRisk { normal, attention, critical, unknown }

class AccountBalancePoint {
  const AccountBalancePoint({
    required this.date,
    required this.balance,
    required this.isConfirmed,
  });

  final DateTime date;
  final int balance;
  final bool isConfirmed;
}

class AccountDistributionItem {
  const AccountDistributionItem({
    required this.label,
    required this.amount,
    required this.colorValue,
  });

  final String label;
  final int amount;
  final int colorValue;
}

class ExpectedIncomeInsight {
  const ExpectedIncomeInsight({
    required this.title,
    required this.date,
    required this.amount,
    required this.confidence,
  });

  final String title;
  final DateTime date;
  final int amount;
  final double confidence;
}

class AccountCapitalAccountInsight {
  const AccountCapitalAccountInsight({
    required this.account,
    required this.preferences,
    required this.balanceBaseCurrency,
    required this.history,
    required this.change,
    required this.changePercent,
    required this.inflow,
    required this.outflow,
    required this.internalTransfers,
    required this.netChange,
    required this.minimumBalance,
    required this.maximumBalance,
    required this.status,
    required this.lastUpdatedAt,
    required this.isHistoryReconstructed,
    required this.recurringTransactions,
    required this.transactions,
  });

  final QestoAccount account;
  final QestoAccountPreferences preferences;
  final int balanceBaseCurrency;
  final List<AccountBalancePoint> history;
  final int? change;
  final double? changePercent;
  final int inflow;
  final int outflow;
  final int internalTransfers;
  final int netChange;
  final int? minimumBalance;
  final int? maximumBalance;
  final AccountDataStatus status;
  final DateTime? lastUpdatedAt;
  final bool isHistoryReconstructed;
  final List<BudgetTransaction> recurringTransactions;
  final List<BudgetTransaction> transactions;
}

class AccountCapitalSnapshot {
  const AccountCapitalSnapshot({
    required this.baseCurrency,
    required this.totalLiquidAssets,
    required this.history,
    required this.change,
    required this.changePercent,
    required this.averageDailyBalance,
    required this.minimumBalance,
    required this.maximumBalance,
    required this.distribution,
    required this.emergencyFundAmount,
    required this.emergencyAccountCount,
    required this.averageEssentialMonthlyExpenses,
    required this.emergencyFundMonths,
    required this.emergencyGoal,
    required this.reservedCash,
    required this.debtPaymentsReserved,
    required this.availableCash,
    required this.nextExpectedIncome,
    required this.averageDailyExpenses,
    required this.minimumProjectedBalance,
    required this.lowBalanceRisk,
    required this.accounts,
    required this.excludedNonLiquidAccounts,
    required this.unlinkedTransactionCount,
    required this.hasUnconvertedCurrencies,
    required this.isHistoryReconstructed,
  });

  final String baseCurrency;
  final int totalLiquidAssets;
  final List<AccountBalancePoint> history;
  final int? change;
  final double? changePercent;
  final int? averageDailyBalance;
  final int? minimumBalance;
  final int? maximumBalance;
  final List<AccountDistributionItem> distribution;
  final int emergencyFundAmount;
  final int emergencyAccountCount;
  final int? averageEssentialMonthlyExpenses;
  final double? emergencyFundMonths;
  final SavingsGoal? emergencyGoal;
  final int reservedCash;
  final int debtPaymentsReserved;
  final int availableCash;
  final ExpectedIncomeInsight? nextExpectedIncome;
  final int? averageDailyExpenses;
  final int? minimumProjectedBalance;
  final LowBalanceRisk lowBalanceRisk;
  final List<AccountCapitalAccountInsight> accounts;
  final int excludedNonLiquidAccounts;
  final int unlinkedTransactionCount;
  final bool hasUnconvertedCurrencies;
  final bool isHistoryReconstructed;
}

/// Builds the read model for Capital → Accounts from canonical account and
/// transaction data. No calculated value is written back to Synoball.
class AccountCapitalService {
  const AccountCapitalService();

  static const _liquidTypes = <AccountType>{
    AccountType.bankCard,
    AccountType.cash,
    AccountType.savings,
    AccountType.deposit,
  };
  static const _essentialCategories = <String>{
    'housing',
    'utilities',
    'groceries',
    'transport',
    'car',
    'health',
    'mobile',
    'internet',
    'children',
    'taxes',
    'loans',
    'insurance',
  };

  AccountCapitalSnapshot calculate({
    required List<QestoAccount> accounts,
    required List<QestoAccountPreferences> accountPreferences,
    required List<BudgetTransaction> transactions,
    required List<UpcomingExpense> upcomingExpenses,
    required List<SavingsGoal> savingsGoals,
    List<GoalAllocation> goalAllocations = const [],
    List<DebtAccount> debts = const [],
    required SynoballState synoballState,
    required DateTime asOf,
    required CapitalPeriod period,
    required String baseCurrency,
  }) {
    final normalizedAsOf = DateTime(asOf.year, asOf.month, asOf.day);
    final preferences = {
      for (final value in accountPreferences) value.accountId: value,
    };
    final liquid = accounts
        .where((item) => _liquidTypes.contains(item.type))
        .toList(growable: false);
    final start = _periodStart(period, transactions, normalizedAsOf);
    var hasUnconvertedCurrencies = false;
    int? converted(int amount, String currency) {
      final value = _convert(amount, currency, baseCurrency);
      if (value == null) hasUnconvertedCurrencies = true;
      return value;
    }

    QestoAccountPreferences settings(QestoAccount account) =>
        preferences[account.id] ?? _defaultsFor(account);

    final included = liquid
        .where((account) {
          final value = settings(account);
          return value.includeInTotal && !value.isClosed;
        })
        .toList(growable: false);
    final includedIds = included.map((item) => item.id).toSet();
    final liquidIds = liquid.map((item) => item.id).toSet();
    final accountsById = {for (final account in accounts) account.id: account};
    // Import adapters keep unresolved observations on a real, virtual account
    // record. That routing bucket is not evidence of a non-liquid asset.
    final unresolvedAccountIds = {
      for (final account in synoballState.accounts)
        if (account.isVirtual && account.type == SynoballAccountType.other)
          account.id,
    };
    final unlinkedTransactionCount = transactions
        .where(
          (item) =>
              item.tags.contains('sber-account-unresolved') &&
              !_day(item.date).isBefore(start) &&
              !_day(item.date).isAfter(normalizedAsOf),
        )
        .length;
    final accountInternalTransferIds = _internalTransferIds(
      transactions,
      liquidIds,
    );
    final total = included.fold<int>(
      0,
      (sum, item) => sum + (converted(item.balance, item.currency) ?? 0),
    );
    // The aggregate balance is anchored to today's included liquid accounts.
    // Unresolved routing accounts still contribute monetary observations.
    // Use signed movements within the observed account perimeter: paired
    // transfer legs cancel, but a lone debit to an unobserved account does not.
    final aggregateTransactions = transactions
        .where((item) {
          if (included.isEmpty) return false;
          final treatment = _cashFlow.treatment(item);
          if (treatment == CashFlowTreatment.ignored ||
              (item.type == TransactionType.transfer &&
                  item.transferDirection == null)) {
            return false;
          }
          final account = accountsById[item.accountId];
          return account == null ||
              unresolvedAccountIds.contains(item.accountId) ||
              (includedIds.contains(account.id) &&
                  settings(account).includeTransactionsInAnalytics);
        })
        .where(
          (item) =>
              !_day(item.date).isBefore(start) &&
              !_day(item.date).isAfter(normalizedAsOf) &&
              converted(
                    _aggregateSignedAmount(item, includedIds),
                    item.currency,
                  ) !=
                  null,
        )
        .toList(growable: false);
    final aggregateHistory = _history(
      currentBalance: total,
      transactions: aggregateTransactions,
      start: start,
      end: normalizedAsOf,
      convert: converted,
      signedAmount: (item) => _aggregateSignedAmount(item, includedIds),
    );
    final hasAggregateHistory = aggregateTransactions.isNotEmpty;
    final displayedHistory = hasAggregateHistory
        ? aggregateHistory
        : <AccountBalancePoint>[
            AccountBalancePoint(
              date: normalizedAsOf,
              balance: total,
              isConfirmed: true,
            ),
          ];
    final change = displayedHistory.length < 2
        ? null
        : total - displayedHistory.first.balance;
    final startingBalance = displayedHistory.first.balance;
    final changePercent = change == null || startingBalance == 0
        ? null
        : change / startingBalance.abs() * 100;

    final accountInsights = liquid
        .map((account) {
          final preference = settings(account);
          final accountTransactions =
              transactions
                  .where(
                    (item) =>
                        item.accountId == account.id &&
                        preference.includeTransactionsInAnalytics &&
                        _cashFlow.treatment(item) != CashFlowTreatment.ignored,
                  )
                  .toList()
                ..sort((left, right) => right.date.compareTo(left.date));
          final current = converted(account.balance, account.currency) ?? 0;
          final history = _history(
            currentBalance: current,
            transactions: accountTransactions,
            start: start,
            end: normalizedAsOf,
            convert: converted,
          );
          final periodTransactions = accountTransactions
              .where(
                (item) =>
                    !_day(item.date).isBefore(start) &&
                    !_day(item.date).isAfter(normalizedAsOf),
              )
              .toList(growable: false);
          final hasHistory = periodTransactions.isNotEmpty;
          final shownHistory = hasHistory
              ? history
              : <AccountBalancePoint>[
                  AccountBalancePoint(
                    date: normalizedAsOf,
                    balance: current,
                    isConfirmed: true,
                  ),
                ];
          final accountChange = shownHistory.length < 2
              ? null
              : current - shownHistory.first.balance;
          final accountStart = shownHistory.first.balance;
          final flow = _accountFlow(
            periodTransactions,
            converted,
            accountInternalTransferIds,
          );
          final freshness = _freshness(account, synoballState, normalizedAsOf);
          final values = shownHistory.map((item) => item.balance);
          return AccountCapitalAccountInsight(
            account: account,
            preferences: preference,
            balanceBaseCurrency: current,
            history: shownHistory,
            change: accountChange,
            changePercent: accountChange == null || accountStart == 0
                ? null
                : accountChange / accountStart.abs() * 100,
            inflow: flow.inflow,
            outflow: flow.outflow,
            internalTransfers: flow.transfers,
            netChange: flow.net,
            minimumBalance: hasHistory ? values.reduce(math.min) : null,
            maximumBalance: hasHistory ? values.reduce(math.max) : null,
            status: freshness.status,
            lastUpdatedAt: freshness.updatedAt,
            isHistoryReconstructed: hasHistory,
            recurringTransactions: accountTransactions
                .where((item) => item.isRecurring)
                .toList(growable: false),
            transactions: accountTransactions,
          );
        })
        .toList(growable: false);

    final distribution = _distribution(included, converted);
    final emergencyAccounts = liquid
        .where((item) {
          final value = settings(item);
          return value.includeInEmergencyFund && !value.isClosed;
        })
        .toList(growable: false);
    final emergencyAmount = emergencyAccounts.fold<int>(
      0,
      (sum, item) => sum + (converted(item.balance, item.currency) ?? 0),
    );
    final essentialMonthly = _averageEssentialMonthly(
      transactions,
      normalizedAsOf,
      converted,
    );
    final emergencyGoal = savingsGoals
        .where(
          (item) =>
              item.category.toLowerCase().contains('подуш') ||
              item.title.toLowerCase().contains('подуш'),
        )
        .firstOrNull;
    final expectedIncome = _expectedIncome(
      transactions,
      normalizedAsOf,
      converted,
      accountInternalTransferIds,
    );
    final horizon =
        expectedIncome?.date ?? normalizedAsOf.add(const Duration(days: 30));
    final recurringReserved = _reservedCash(
      upcomingExpenses,
      synoballState.recurringStreams,
      normalizedAsOf,
      horizon,
      converted,
    );
    final debtPayments = _debtAnalytics.getNextPayments(
      debts,
      asOf: normalizedAsOf,
      days: math.max(0, horizon.difference(normalizedAsOf).inDays),
    );
    final debtReserved = debtPayments.fold<int>(
      0,
      (sum, item) => sum + (converted(item.amount, item.currency) ?? 0),
    );
    final goalReserved = goalAllocations
        .where(
          (item) =>
              item.sourceType == GoalAllocationSourceType.account &&
              includedIds.contains(item.sourceId),
        )
        .fold<int>(
          0,
          (sum, item) =>
              sum + (converted(item.allocatedAmount, item.currency) ?? 0),
        );
    final reserved = recurringReserved + debtReserved + goalReserved;
    final dailyExpenses = _averageDailyExpenses(
      transactions,
      normalizedAsOf,
      converted,
      accountInternalTransferIds,
    );
    final projected = expectedIncome == null || dailyExpenses == null
        ? null
        : total -
              reserved -
              dailyExpenses *
                  math.max<int>(
                    0,
                    expectedIncome.date.difference(normalizedAsOf).inDays,
                  );
    final risk = _risk(projected, dailyExpenses);
    final historyValues = displayedHistory.map((item) => item.balance);
    return AccountCapitalSnapshot(
      baseCurrency: baseCurrency,
      totalLiquidAssets: total,
      history: displayedHistory,
      change: change,
      changePercent: changePercent,
      averageDailyBalance: hasAggregateHistory
          ? (historyValues.reduce((a, b) => a + b) / displayedHistory.length)
                .round()
          : null,
      minimumBalance: hasAggregateHistory
          ? historyValues.reduce((left, right) => left < right ? left : right)
          : null,
      maximumBalance: hasAggregateHistory
          ? historyValues.reduce((left, right) => left > right ? left : right)
          : null,
      distribution: distribution,
      emergencyFundAmount: emergencyAmount,
      emergencyAccountCount: emergencyAccounts.length,
      averageEssentialMonthlyExpenses: essentialMonthly,
      emergencyFundMonths:
          emergencyAccounts.isEmpty ||
              essentialMonthly == null ||
              essentialMonthly <= 0
          ? null
          : emergencyAmount / essentialMonthly,
      emergencyGoal: emergencyGoal,
      reservedCash: reserved,
      debtPaymentsReserved: debtReserved,
      availableCash: total - reserved,
      nextExpectedIncome: expectedIncome,
      averageDailyExpenses: dailyExpenses,
      minimumProjectedBalance: projected,
      lowBalanceRisk: risk,
      accounts: accountInsights,
      excludedNonLiquidAccounts: accounts.length - liquid.length,
      unlinkedTransactionCount: unlinkedTransactionCount,
      hasUnconvertedCurrencies: hasUnconvertedCurrencies,
      isHistoryReconstructed: hasAggregateHistory,
    );
  }

  DateTime _periodStart(
    CapitalPeriod period,
    List<BudgetTransaction> transactions,
    DateTime asOf,
  ) {
    final days = period.days;
    if (days != null) return asOf.subtract(Duration(days: days));
    final dates = transactions.map((item) => _day(item.date)).toList();
    if (dates.isEmpty) return asOf.subtract(const Duration(days: 30));
    final earliest = dates.reduce(
      (left, right) => left.isBefore(right) ? left : right,
    );
    final twoYearsAgo = asOf.subtract(const Duration(days: 730));
    final beforeFirstOperation = earliest.subtract(const Duration(days: 1));
    return beforeFirstOperation.isBefore(twoYearsAgo)
        ? twoYearsAgo
        : beforeFirstOperation;
  }

  List<AccountBalancePoint> _history({
    required int currentBalance,
    required Iterable<BudgetTransaction> transactions,
    required DateTime start,
    required DateTime end,
    required int? Function(int amount, String currency) convert,
    int Function(BudgetTransaction item)? signedAmount,
  }) {
    final deltaByDay = <DateTime, int>{};
    for (final item in transactions) {
      final day = _day(item.date);
      if (day.isBefore(start) || day.isAfter(end)) continue;
      final amount = convert(
        (signedAmount ?? _signedAmount)(item),
        item.currency,
      );
      if (amount == null) continue;
      deltaByDay.update(day, (value) => value + amount, ifAbsent: () => amount);
    }
    // Earlier days are outside the observed transaction history. Keep one
    // pre-operation anchor when it fits the selected period, then reconstruct
    // end-of-day balances back from the current account balance.
    final firstObservedDay = deltaByDay.keys.isEmpty
        ? end
        : deltaByDay.keys.reduce(
            (left, right) => left.isBefore(right) ? left : right,
          );
    final previousDay = firstObservedDay.subtract(const Duration(days: 1));
    final historyStart = previousDay.isAfter(start) ? previousDay : start;
    final descending = <AccountBalancePoint>[];
    var balance = currentBalance;
    var date = end;
    while (!date.isBefore(historyStart)) {
      descending.add(
        AccountBalancePoint(
          date: date,
          balance: balance,
          isConfirmed: date == end,
        ),
      );
      balance -= deltaByDay[date] ?? 0;
      date = date.subtract(const Duration(days: 1));
    }
    return descending.reversed.toList(growable: false);
  }

  ({int inflow, int outflow, int transfers, int net}) _accountFlow(
    Iterable<BudgetTransaction> transactions,
    int? Function(int amount, String currency) convert,
    Set<String> internalTransferIds,
  ) {
    var inflow = 0;
    var outflow = 0;
    var transfers = 0;
    var net = 0;
    for (final item in transactions) {
      final signed = convert(_signedAmount(item), item.currency);
      if (signed == null) continue;
      net += signed;
      if (internalTransferIds.contains(item.id)) {
        transfers += signed;
      } else if (signed > 0) {
        inflow += signed;
      } else {
        outflow += signed.abs();
      }
    }
    return (inflow: inflow, outflow: outflow, transfers: transfers, net: net);
  }

  List<AccountDistributionItem> _distribution(
    Iterable<QestoAccount> accounts,
    int? Function(int amount, String currency) convert,
  ) {
    final totals = <AccountType, int>{};
    for (final account in accounts) {
      totals.update(
        account.type,
        (value) => value + (convert(account.balance, account.currency) ?? 0),
        ifAbsent: () => convert(account.balance, account.currency) ?? 0,
      );
    }
    const definitions = <AccountType, (String, int)>{
      AccountType.bankCard: ('Повседневные', 0xFF3478F6),
      AccountType.savings: ('Накопительные', 0xFF55C96F),
      AccountType.deposit: ('Вклады', 0xFF8D63F6),
      AccountType.cash: ('Наличные', 0xFFFFB347),
    };
    return [
      for (final entry in definitions.entries)
        if ((totals[entry.key] ?? 0) != 0)
          AccountDistributionItem(
            label: entry.value.$1,
            amount: totals[entry.key]!,
            colorValue: entry.value.$2,
          ),
    ];
  }

  int? _averageEssentialMonthly(
    List<BudgetTransaction> transactions,
    DateTime asOf,
    int? Function(int amount, String currency) convert,
  ) {
    final start = asOf.subtract(const Duration(days: 183));
    final relevant = transactions
        .where(
          (item) =>
              item.type == TransactionType.expense &&
              _essentialCategories.contains(item.categoryId) &&
              !item.date.isBefore(start) &&
              !item.date.isAfter(asOf),
        )
        .toList();
    if (relevant.length < 5) return null;
    final dates = relevant.map((item) => _day(item.date)).toList()..sort();
    final span = math.max(1, asOf.difference(dates.first).inDays + 1);
    if (span < 14) return null;
    final total = relevant.fold<int>(
      0,
      (sum, item) => sum + (convert(item.amount, item.currency) ?? 0),
    );
    return (total / span * 30.4375).round();
  }

  int? _averageDailyExpenses(
    List<BudgetTransaction> transactions,
    DateTime asOf,
    int? Function(int amount, String currency) convert,
    Set<String> internalTransferIds,
  ) {
    final start = asOf.subtract(const Duration(days: 60));
    final relevant = transactions
        .where(
          (item) =>
              _cashFlow.treatment(item) == CashFlowTreatment.externalOutflow &&
              !internalTransferIds.contains(item.id) &&
              !item.date.isBefore(start) &&
              !item.date.isAfter(asOf),
        )
        .toList();
    if (relevant.length < 8) return null;
    final dates = relevant.map((item) => _day(item.date)).toList()..sort();
    final span = math.max(1, asOf.difference(dates.first).inDays + 1);
    if (span < 14) return null;
    final total = relevant.fold<int>(
      0,
      (sum, item) => sum + (convert(item.amount, item.currency) ?? 0),
    );
    return (total / span).round();
  }

  ExpectedIncomeInsight? _expectedIncome(
    List<BudgetTransaction> transactions,
    DateTime asOf,
    int? Function(int amount, String currency) convert,
    Set<String> internalTransferIds,
  ) {
    final groups = <String, List<BudgetTransaction>>{};
    for (final item in transactions) {
      final incoming =
          _cashFlow.treatment(item) == CashFlowTreatment.externalInflow;
      if (!incoming ||
          item.type == TransactionType.refund ||
          internalTransferIds.contains(item.id)) {
        continue;
      }
      final title = (item.merchant ?? item.title ?? item.description ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
          .trim();
      if (title.isEmpty) continue;
      groups.putIfAbsent(title, () => []).add(item);
    }
    final candidates = <ExpectedIncomeInsight>[];
    for (final items in groups.values) {
      items.sort((a, b) => a.date.compareTo(b.date));
      if (items.length < 3) continue;
      final recent = items.length > 6 ? items.sublist(items.length - 6) : items;
      final intervals = <int>[
        for (var index = 1; index < recent.length; index++)
          _day(
            recent[index].date,
          ).difference(_day(recent[index - 1].date)).inDays,
      ];
      final monthly = intervals.every((days) => days >= 25 && days <= 35);
      final weekly =
          recent.length >= 4 &&
          intervals.every((days) => days >= 6 && days <= 8);
      if (!monthly && !weekly) continue;
      final averageInterval =
          (intervals.reduce((a, b) => a + b) / intervals.length).round();
      var next = _day(recent.last.date).add(Duration(days: averageInterval));
      while (!next.isAfter(asOf)) {
        next = next.add(Duration(days: averageInterval));
      }
      if (next.difference(asOf).inDays > 60) continue;
      final convertedAmounts = recent
          .map((item) => convert(item.amount, item.currency))
          .whereType<int>()
          .toList();
      if (convertedAmounts.isEmpty) continue;
      convertedAmounts.sort();
      candidates.add(
        ExpectedIncomeInsight(
          title:
              recent.last.merchant ??
              recent.last.title ??
              recent.last.description ??
              'Регулярный доход',
          date: next,
          amount: convertedAmounts[convertedAmounts.length ~/ 2],
          confidence: monthly ? 0.86 : 0.82,
        ),
      );
    }
    candidates.sort((a, b) => a.date.compareTo(b.date));
    return candidates.firstOrNull;
  }

  int _reservedCash(
    List<UpcomingExpense> upcoming,
    List<RecurringStream> recurring,
    DateTime asOf,
    DateTime horizon,
    int? Function(int amount, String currency) convert,
  ) {
    var total = 0;
    final signatures = <String>{};
    for (final item in upcoming) {
      final day = _day(item.plannedDate);
      if (item.isCancelled || day.isBefore(asOf) || day.isAfter(horizon)) {
        continue;
      }
      final amount = convert(item.amount, item.currency);
      if (amount == null) continue;
      total += amount.abs();
      signatures.add('${_key(item.title)}:${day.year}-${day.month}-${day.day}');
    }
    for (final item in recurring) {
      if (item.isTentative) continue;
      final day = _day(item.nextExpectedAt);
      if (day.isBefore(asOf) || day.isAfter(horizon)) continue;
      final key = '${_key(item.title)}:${day.year}-${day.month}-${day.day}';
      if (signatures.contains(key)) continue;
      final major = (item.typicalAmount.minorUnits.abs() / 100).round();
      total += convert(major, item.typicalAmount.currency) ?? 0;
    }
    return total;
  }

  ({AccountDataStatus status, DateTime? updatedAt}) _freshness(
    QestoAccount account,
    SynoballState state,
    DateTime asOf,
  ) {
    final canonical = state.accounts
        .where((item) => item.id == account.id)
        .firstOrNull;
    if (canonical == null || canonical.isVirtual) {
      return (status: AccountDataStatus.manual, updatedAt: null);
    }
    DateTime? updatedAt;
    if (canonical.connectionId case final connectionId?) {
      updatedAt = state.connections
          .where((item) => item.id == connectionId)
          .map((item) => item.lastSyncedAt)
          .whereType<DateTime>()
          .firstOrNull;
    }
    final transactionUpdates = state.transactions
        .where((item) => item.accountId == account.id)
        .map((item) => item.updatedAt)
        .toList();
    if (transactionUpdates.isNotEmpty) {
      final latest = transactionUpdates.reduce(
        (left, right) => left.isAfter(right) ? left : right,
      );
      if (updatedAt == null || latest.isAfter(updatedAt)) {
        updatedAt = latest;
      }
    }
    if (updatedAt == null) {
      return (status: AccountDataStatus.partial, updatedAt: null);
    }
    final age = asOf.difference(_day(updatedAt)).inDays;
    if (age <= 1) {
      return (status: AccountDataStatus.current, updatedAt: updatedAt);
    }
    if (age <= 7) {
      return (status: AccountDataStatus.needsUpdate, updatedAt: updatedAt);
    }
    return (status: AccountDataStatus.partial, updatedAt: updatedAt);
  }

  LowBalanceRisk _risk(int? projected, int? dailyExpenses) {
    if (projected == null || dailyExpenses == null || dailyExpenses <= 0) {
      return LowBalanceRisk.unknown;
    }
    if (projected < 0 || projected < dailyExpenses * 3) {
      return LowBalanceRisk.critical;
    }
    if (projected < dailyExpenses * 14) return LowBalanceRisk.attention;
    return LowBalanceRisk.normal;
  }

  QestoAccountPreferences _defaultsFor(QestoAccount account) {
    final isReserve = {
      AccountType.savings,
      AccountType.deposit,
    }.contains(account.type);
    return QestoAccountPreferences(
      accountId: account.id,
      role: isReserve ? QestoAccountRole.savings : QestoAccountRole.everyday,
      includeInEmergencyFund: isReserve,
    );
  }

  int? _convert(int amount, String from, String to) {
    if (from == to) return amount;
    final rates = CbrCurrencyService.embeddedSnapshot.rates;
    final fromRate = rates[from]?.rublesPerUnit;
    final toRate = rates[to]?.rublesPerUnit;
    if (fromRate == null || toRate == null) return null;
    return (amount * fromRate / toRate).round();
  }

  int _signedAmount(BudgetTransaction item) => switch (item.type) {
    TransactionType.income || TransactionType.refund => item.amount,
    TransactionType.transfer =>
      item.transferDirection == TransferDirection.incoming
          ? item.amount
          : -item.amount,
    _ => -item.amount,
  };

  int _aggregateSignedAmount(
    BudgetTransaction item,
    Set<String> includedAccountIds,
  ) {
    if (_cashFlow.treatment(item) != CashFlowTreatment.internalTransfer) {
      return _signedAmount(item);
    }
    String? accountTagged(String prefix) {
      for (final tag in item.tags) {
        if (tag.startsWith(prefix)) return tag.substring(prefix.length);
      }
      return null;
    }

    final source = accountTagged(qestoInternalTransferSourceAccountPrefix);
    final destination = accountTagged(
      qestoInternalTransferDestinationAccountPrefix,
    );
    // The Sber document can identify both owned products even when its global
    // history exposes only the debit. Its two legs cancel in total liquidity;
    // a transfer to an unobserved product retains the signed movement.
    if (source == null || destination == null || source == destination) {
      return _signedAmount(item);
    }
    return (includedAccountIds.contains(destination) ? item.amount : 0) -
        (includedAccountIds.contains(source) ? item.amount : 0);
  }

  Set<String> _internalTransferIds(
    List<BudgetTransaction> transactions,
    Set<String> accountIds,
  ) {
    final result = <String>{
      for (final item in transactions)
        if (accountIds.contains(item.accountId) &&
            _cashFlow.treatment(item) == CashFlowTreatment.internalTransfer)
          item.id,
    };
    final candidates = transactions
        .where(
          (item) =>
              accountIds.contains(item.accountId) &&
              item.type == TransactionType.transfer &&
              item.transferDirection != null &&
              !item.tags.contains(qestoExternalTransferTag) &&
              _cashFlow.treatment(item) != CashFlowTreatment.ignored,
        )
        .toList(growable: false);
    final incoming = candidates
        .where((item) => item.transferDirection == TransferDirection.incoming)
        .toList(growable: false);
    final matchedIncoming = <String>{};
    for (final outgoing in candidates.where(
      (item) => item.transferDirection == TransferDirection.outgoing,
    )) {
      BudgetTransaction? match;
      var bestDistance = 2;
      for (final candidate in incoming) {
        if (matchedIncoming.contains(candidate.id) ||
            candidate.accountId == outgoing.accountId ||
            candidate.amount != outgoing.amount ||
            candidate.currency != outgoing.currency ||
            !_compatibleTransferDescriptions(outgoing, candidate)) {
          continue;
        }
        final distance = _day(
          candidate.date,
        ).difference(_day(outgoing.date)).inDays.abs();
        if (distance <= 1 && distance < bestDistance) {
          match = candidate;
          bestDistance = distance;
        }
      }
      if (match != null) {
        result
          ..add(outgoing.id)
          ..add(match.id);
        matchedIncoming.add(match.id);
      }
    }
    return result;
  }

  bool _compatibleTransferDescriptions(
    BudgetTransaction left,
    BudgetTransaction right,
  ) {
    final leftText = _transferDescription(left);
    final rightText = _transferDescription(right);
    return leftText.isEmpty || rightText.isEmpty || leftText == rightText;
  }

  String _transferDescription(BudgetTransaction item) => _key(
    [
      item.merchant,
      item.title,
      item.description,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' '),
  );

  static const _cashFlow = CashFlowCalculationService();
  static const _debtAnalytics = DebtAnalyticsService();

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  String _key(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .trim();
}
