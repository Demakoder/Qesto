import 'package:flutter/foundation.dart';

import '../../../../data/models/qesto_models.dart';
import '../../../budget/state/budget_controller.dart';
import '../../domain/models/statistics_models.dart';
import '../../domain/services/statistics_calculation_service.dart';
import '../../domain/services/statistics_period_range.dart';

class StatisticsController extends ChangeNotifier {
  StatisticsController({
    required this.budgetController,
    this.calculationService = const StatisticsCalculationService(),
  }) {
    final activePeriod = budgetController.periods.firstWhere(
      (period) => period.contains(budgetController.referenceDate),
      orElse: () => budgetController.periods.last,
    );
    var initialRange = StatisticsDateRange(
      activePeriod.startDate,
      budgetController.referenceDate,
    );
    var initialPreset = StatisticsPeriodPreset.currentBudget;
    final hasOperationsInActiveRange = budgetController.transactions.any(
      (transaction) => initialRange.contains(transaction.date),
    );
    if (!hasOperationsInActiveRange &&
        budgetController.transactions.isNotEmpty) {
      final newest = budgetController.transactions
          .map((item) => item.date)
          .reduce((left, right) => left.isAfter(right) ? left : right);
      final recentEnd = newest.isAfter(budgetController.referenceDate)
          ? newest
          : budgetController.referenceDate;
      final recentRange = StatisticsDateRange(
        recentEnd.subtract(const Duration(days: 29)),
        recentEnd,
      );
      if (budgetController.transactions.any(
        (transaction) => recentRange.contains(transaction.date),
      )) {
        initialRange = recentRange;
        initialPreset = StatisticsPeriodPreset.last30Days;
      } else {
        final latestPeriod = budgetController.periods.firstWhere(
          (period) => period.contains(newest),
          orElse: () => budgetController.periods.last,
        );
        initialRange = StatisticsDateRange(
          latestPeriod.startDate,
          latestPeriod.endDate,
        );
        initialPreset = StatisticsPeriodPreset.custom;
      }
    }
    _query = StatisticsQuery(period: initialRange, preset: initialPreset);
    _tracked.addAll([
      const TrackedStatisticsItem(
        id: 'cafes',
        type: TrackedStatisticsType.category,
        label: 'Кафе и рестораны',
        isPinned: true,
      ),
      const TrackedStatisticsItem(
        id: 'Яндекс Go',
        type: TrackedStatisticsType.merchant,
        label: 'Яндекс Go',
      ),
    ]);
    budgetController.addListener(_handleBudgetChanged);
    _recalculate();
  }

  final BudgetController budgetController;
  final StatisticsCalculationService calculationService;
  late StatisticsQuery _query;
  late StatisticsSnapshot _snapshot;
  StatisticsSection _section = StatisticsSection.overview;
  final List<TrackedStatisticsItem> _tracked = [];
  final Set<String> _ignoredQualityIssueIds = {};
  bool _isRefreshing = false;
  bool _disposed = false;

  StatisticsQuery get query => _query;
  StatisticsSnapshot get snapshot => _snapshot;
  StatisticsSection get section => _section;
  List<TrackedStatisticsItem> get tracked => List.unmodifiable(_tracked);
  bool get isRefreshing => _isRefreshing;

  void _handleBudgetChanged() {
    // A manual refresh already reads the latest ledger after its await. Avoid
    // calculating the same snapshot twice when a mutation lands meanwhile.
    if (_isRefreshing) return;
    _recalculate();
    notifyListeners();
  }

  /// Rebuilds the current query from the local Synoball read model only.
  /// This neither persists data nor invokes any bank/import integration.
  Future<bool> refreshFromLocalData() async {
    if (_isRefreshing) return false;
    _isRefreshing = true;
    notifyListeners();
    try {
      // Give the compact progress indicator one frame to become visible.
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (_disposed) return false;
      _recalculate(); // Assignment is atomic; a failed build keeps the last snapshot.
      notifyListeners();
      return true;
    } finally {
      _isRefreshing = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _recalculate() {
    _snapshot = calculationService.buildSnapshot(
      query: _query,
      allTransactions: budgetController.transactions,
      categories: budgetController.categories,
      periods: budgetController.periods,
      accounts: budgetController.accounts,
      referenceDate: budgetController.referenceDate,
      ignoredQualityIssueIds: _ignoredQualityIssueIds,
    );
  }

  void selectSection(StatisticsSection value, {bool notify = true}) {
    if (_section == value) return;
    _section = value;
    if (notify) notifyListeners();
  }

  void setPeriodPreset(StatisticsPeriodPreset preset) {
    final range = statisticsPeriodRange(
      preset: preset,
      reference: budgetController.referenceDate,
      transactionDates: budgetController.transactions.map((t) => t.date),
      budgetPeriods: budgetController.periods,
    );
    if (range == null) return;
    _query = _query.copyWith(period: range, preset: preset);
    _recalculate();
    notifyListeners();
  }

  void setCustomPeriod(DateTime start, DateTime end) {
    _query = _query.copyWith(
      period: StatisticsDateRange(start, end),
      preset: StatisticsPeriodPreset.custom,
    );
    _recalculate();
    notifyListeners();
  }

  void setComparison(StatisticsComparison comparison) {
    _query = _query.copyWith(comparison: comparison);
    _recalculate();
    notifyListeners();
  }

  void applyFilters({
    required Set<String> accountIds,
    required Set<String> categoryIds,
    Set<String> subcategoryIds = const {},
    Set<String> merchantNames = const {},
    Set<String> tagIds = const {},
    required Set<TransactionType> transactionTypes,
    required bool includeCash,
    required bool includeLargePurchases,
    required bool includeRecurring,
    required bool includeRefunds,
    required bool includeUncategorized,
    required bool onlyConfirmed,
  }) {
    _query = _query.copyWith(
      accountIds: accountIds,
      categoryIds: categoryIds,
      subcategoryIds: subcategoryIds,
      merchantNames: merchantNames,
      tagIds: tagIds,
      transactionTypes: transactionTypes,
      includeCash: includeCash,
      includeLargePurchases: includeLargePurchases,
      includeRecurring: includeRecurring,
      includeRefunds: includeRefunds,
      includeUncategorized: includeUncategorized,
      onlyConfirmed: onlyConfirmed,
    );
    _recalculate();
    notifyListeners();
  }

  void resetFilters() {
    _query = StatisticsQuery(
      period: _query.period,
      preset: _query.preset,
      comparison: _query.comparison,
    );
    _recalculate();
    notifyListeners();
  }

  bool isTracked(TrackedStatisticsType type, String id) =>
      _tracked.any((item) => item.type == type && item.id == id);

  void toggleTracked(TrackedStatisticsType type, String id, String label) {
    final index = _tracked.indexWhere(
      (item) => item.type == type && item.id == id,
    );
    if (index >= 0) {
      _tracked.removeAt(index);
    } else {
      _tracked.add(TrackedStatisticsItem(id: id, type: type, label: label));
    }
    notifyListeners();
  }

  void togglePinned(int index) {
    _tracked[index] = _tracked[index].copyWith(
      isPinned: !_tracked[index].isPinned,
    );
    notifyListeners();
  }

  void reorderTracked(int oldIndex, int newIndex) {
    final item = _tracked.removeAt(oldIndex);
    _tracked.insert(newIndex, item);
    notifyListeners();
  }

  void ignoreQualityIssue(String issueId) {
    _ignoredQualityIssueIds.add(issueId);
    _recalculate();
    notifyListeners();
  }

  BudgetPeriod periodFor(BudgetTransaction transaction) =>
      budgetController.periods.firstWhere(
        (period) => period.contains(transaction.date),
        orElse: () => budgetController.periods.last,
      );

  List<BudgetTransaction> transactionsForCategory(String categoryId) =>
      _snapshot.transactions
          .where(
            (item) =>
                item.categoryId == categoryId &&
                calculationService.isConsumerExpense(item),
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  List<BudgetTransaction> transactionsForMerchant(String merchant) =>
      _snapshot.transactions
          .where(
            (item) =>
                calculationService.merchantName(item) == merchant &&
                calculationService.isConsumerExpense(item),
          )
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  @override
  void dispose() {
    _disposed = true;
    budgetController.removeListener(_handleBudgetChanged);
    super.dispose();
  }
}
