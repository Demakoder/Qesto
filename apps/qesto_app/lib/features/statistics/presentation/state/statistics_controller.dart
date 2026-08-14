import 'package:flutter/foundation.dart';

import '../../../../data/models/qesto_models.dart';
import '../../../budget/state/budget_controller.dart';
import '../../domain/models/statistics_models.dart';
import '../../domain/services/statistics_calculation_service.dart';

class StatisticsController extends ChangeNotifier {
  StatisticsController({
    required this.budgetController,
    this.calculationService = const StatisticsCalculationService(),
  }) {
    final activePeriod = budgetController.periods.firstWhere(
      (period) => period.contains(budgetController.referenceDate),
      orElse: () => budgetController.periods.last,
    );
    _query = StatisticsQuery(
      period: StatisticsDateRange(
        activePeriod.startDate,
        budgetController.referenceDate,
      ),
    );
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

  StatisticsQuery get query => _query;
  StatisticsSnapshot get snapshot => _snapshot;
  StatisticsSection get section => _section;
  List<TrackedStatisticsItem> get tracked => List.unmodifiable(_tracked);

  void _handleBudgetChanged() {
    _recalculate();
    notifyListeners();
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

  void selectSection(StatisticsSection value) {
    if (_section == value) return;
    _section = value;
    notifyListeners();
  }

  void setPeriodPreset(StatisticsPeriodPreset preset) {
    final reference = budgetController.referenceDate;
    late final StatisticsDateRange range;
    switch (preset) {
      case StatisticsPeriodPreset.currentWeek:
        final start = reference.subtract(Duration(days: reference.weekday - 1));
        range = StatisticsDateRange(start, reference);
      case StatisticsPeriodPreset.currentBudget:
        final period = budgetController.periods.firstWhere(
          (item) => item.contains(reference),
          orElse: () => budgetController.periods.last,
        );
        range = StatisticsDateRange(period.startDate, reference);
      case StatisticsPeriodPreset.last30Days:
        range = StatisticsDateRange(
          reference.subtract(const Duration(days: 29)),
          reference,
        );
      case StatisticsPeriodPreset.threeMonths:
        range = StatisticsDateRange(
          DateTime(reference.year, reference.month - 2),
          reference,
        );
      case StatisticsPeriodPreset.sixMonths:
        range = StatisticsDateRange(
          DateTime(reference.year, reference.month - 5),
          reference,
        );
      case StatisticsPeriodPreset.currentYear:
        range = StatisticsDateRange(DateTime(reference.year), reference);
      case StatisticsPeriodPreset.last12Months:
        range = StatisticsDateRange(
          DateTime(reference.year, reference.month - 11),
          reference,
        );
      case StatisticsPeriodPreset.allTime:
        final earliest = budgetController.transactions.isEmpty
            ? reference
            : budgetController.transactions
                  .map((item) => item.date)
                  .reduce((a, b) => a.isBefore(b) ? a : b);
        range = StatisticsDateRange(earliest, reference);
      case StatisticsPeriodPreset.custom:
        return;
    }
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
    budgetController.removeListener(_handleBudgetChanged);
    super.dispose();
  }
}
