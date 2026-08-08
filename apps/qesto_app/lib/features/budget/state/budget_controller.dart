import 'package:flutter/foundation.dart';

import '../../../data/models/qesto_models.dart';
import '../services/budget_calculation_service.dart';
import '../services/budget_forecast_service.dart';
import '../services/category_budget_calculation_service.dart';

class BudgetController extends ChangeNotifier {
  BudgetController({
    required BudgetConfiguration configuration,
    required UserFinancialData financialData,
    this.calculationService = const BudgetCalculationService(),
    this.forecastService = const BudgetForecastService(),
    this.categoryCalculationService = const CategoryBudgetCalculationService(),
  }) : referenceDate = financialData.referenceDate,
       _userId = financialData.user.id,
       _defaultCurrency = financialData.user.defaultCurrency,
       periods = _resolvedPeriods(financialData),
       categories = List.of(configuration.categories),
       categoryBudgets = List.of(financialData.categoryBudgets),
       plannedCumulativePoints = List.of(financialData.plannedCumulativePoints),
       accounts = _resolvedAccounts(financialData),
       _transactions = List.of(financialData.transactions),
       _upcomingExpenses = List.of(financialData.upcomingExpenses);

  static List<BudgetPeriod> _resolvedPeriods(UserFinancialData data) {
    if (data.budgetPeriods.isNotEmpty) {
      return List.of(data.budgetPeriods);
    }

    final date = data.referenceDate;
    return [
      BudgetPeriod(
        id: 'local-${date.year}-${date.month.toString().padLeft(2, '0')}',
        userId: data.user.id,
        startDate: DateTime(date.year, date.month),
        endDate: DateTime(date.year, date.month + 1, 0),
        type: BudgetPeriodType.calendarMonth,
        totalPlan: 0,
        currency: data.user.defaultCurrency,
      ),
    ];
  }

  static List<QestoAccount> _resolvedAccounts(UserFinancialData data) {
    if (data.accounts.isNotEmpty) {
      return List.of(data.accounts);
    }

    return [
      QestoAccount(
        id: 'local-default-account',
        userId: data.user.id,
        title: 'Основной счёт',
        balance: 0,
        currency: data.user.defaultCurrency,
        type: AccountType.other,
      ),
    ];
  }

  final DateTime referenceDate;
  final String _userId;
  final String _defaultCurrency;
  final List<BudgetPeriod> periods;
  final List<BudgetCategory> categories;
  final List<CategoryBudget> categoryBudgets;
  final List<BudgetPlanPoint> plannedCumulativePoints;
  final List<QestoAccount> accounts;
  final BudgetCalculationService calculationService;
  final BudgetForecastService forecastService;
  final CategoryBudgetCalculationService categoryCalculationService;

  final List<BudgetTransaction> _transactions;
  final List<UpcomingExpense> _upcomingExpenses;

  List<BudgetTransaction> get transactions => List.unmodifiable(_transactions);
  List<UpcomingExpense> get upcomingExpenses =>
      List.unmodifiable(_upcomingExpenses);

  BudgetSummary summaryFor(BudgetPeriod period) =>
      calculationService.summary(period, _transactions, categories);

  DateTime activeDateFor(BudgetPeriod period) {
    if (referenceDate.isAfter(period.endDate)) return period.endDate;
    if (!referenceDate.isBefore(period.startDate)) return referenceDate;
    final periodTransactions = transactionsFor(period);
    return periodTransactions.isEmpty
        ? period.startDate
        : periodTransactions.last.date;
  }

  List<BudgetTransaction> transactionsFor(BudgetPeriod period) =>
      calculationService.transactionsForPeriod(period, _transactions);

  List<BudgetTransaction> transactionsForCategory(
    BudgetPeriod period,
    String categoryId,
  ) {
    final result =
        transactionsFor(period)
            .where(
              (transaction) =>
                  transaction.categoryId == categoryId &&
                  calculationService.isConsumerTransaction(transaction),
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
    return result;
  }

  List<CategoryPlanStatus> categoryPlansFor(BudgetPeriod period) {
    return categoryCalculationService.calculate(
      period: period,
      categories: categories,
      budgets: categoryBudgets,
      transactions: _transactions,
    );
  }

  List<UpcomingExpense> upcomingFor(BudgetPeriod period) {
    final result =
        _upcomingExpenses
            .where(
              (expense) =>
                  expense.budgetPeriodId == period.id && !expense.isCancelled,
            )
            .toList()
          ..sort((a, b) => a.plannedDate.compareTo(b.plannedDate));
    return result;
  }

  BudgetForecast forecastFor(BudgetPeriod period) {
    return forecastService.buildForecast(
      period: period,
      transactions: _transactions,
      asOfDate: activeDateFor(period),
    );
  }

  int plannedAtActiveDate(BudgetPeriod period) {
    return calculationService.plannedAmountAtDate(
      period,
      activeDateFor(period),
      plannedCumulativePoints,
    );
  }

  int allowedDailyExpense(BudgetPeriod period) {
    final summary = summaryFor(period);
    return calculationService.allowedDailyExpense(
      period,
      summary.currentExpense,
      activeDateFor(period),
    );
  }

  BudgetCategory categoryById(String id) =>
      categories.firstWhere((category) => category.id == id);

  QestoAccount accountById(String id) => accounts.firstWhere(
    (account) => account.id == id,
    orElse: () => accounts.first,
  );

  BudgetPeriod periodForOrCreate(DateTime date) {
    for (final period in periods) {
      if (period.contains(date)) return period;
    }

    final period = BudgetPeriod(
      id: 'imported-${date.year}-${date.month.toString().padLeft(2, '0')}',
      userId: _userId,
      startDate: DateTime(date.year, date.month),
      endDate: DateTime(date.year, date.month + 1, 0),
      type: BudgetPeriodType.calendarMonth,
      totalPlan: 0,
      currency: _defaultCurrency,
    );
    periods.add(period);
    periods.sort((a, b) => a.startDate.compareTo(b.startDate));
    return period;
  }

  bool hasTransaction(String id) =>
      _transactions.any((transaction) => transaction.id == id);

  void addImportedTransactions(Iterable<BudgetTransaction> transactions) {
    final knownIds = _transactions.map((transaction) => transaction.id).toSet();
    final additions = <BudgetTransaction>[];
    for (final transaction in transactions) {
      if (knownIds.add(transaction.id)) additions.add(transaction);
    }
    if (additions.isEmpty) return;
    _transactions.addAll(additions);
    notifyListeners();
  }

  void addExpense({
    required BudgetPeriod period,
    required int amount,
    required DateTime date,
    required String categoryId,
    required String accountId,
    required String title,
    String? subcategoryId,
    String? comment,
  }) {
    _transactions.add(
      BudgetTransaction(
        id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
        userId: period.userId,
        accountId: accountId,
        date: date,
        amount: amount,
        currency: period.currency,
        type: TransactionType.expense,
        categoryId: categoryId,
        subcategoryId: subcategoryId,
        merchant: title,
        title: title,
        comment: comment,
      ),
    );
    notifyListeners();
  }

  void updateTransaction(BudgetTransaction transaction) {
    final index = _transactions.indexWhere((item) => item.id == transaction.id);
    if (index < 0) return;
    _transactions[index] = transaction;
    notifyListeners();
  }

  void deleteTransaction(String id) {
    _transactions.removeWhere((transaction) => transaction.id == id);
    notifyListeners();
  }

  void addUpcoming(UpcomingExpense expense) {
    _upcomingExpenses.add(expense);
    notifyListeners();
  }

  void updateUpcoming(UpcomingExpense expense) {
    final index = _upcomingExpenses.indexWhere((item) => item.id == expense.id);
    if (index < 0) return;
    _upcomingExpenses[index] = expense;
    notifyListeners();
  }

  void deleteUpcoming(String id) {
    _upcomingExpenses.removeWhere((expense) => expense.id == id);
    notifyListeners();
  }
}
