import 'package:flutter/foundation.dart';

import '../../../data/models/qesto_models.dart';
import '../services/budget_calculation_service.dart';
import '../services/budget_forecast_service.dart';
import '../services/category_budget_calculation_service.dart';

class BudgetController extends ChangeNotifier {
  BudgetController({
    required BudgetConfiguration configuration,
    required UserFinancialData financialData,
    this.onChanged,
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
       _upcomingExpenses = List.of(financialData.upcomingExpenses),
       _actions = List.of(financialData.actions);

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
  final Future<void> Function()? onChanged;

  final List<BudgetTransaction> _transactions;
  final List<UpcomingExpense> _upcomingExpenses;
  final List<FinancialAction> _actions;

  List<BudgetTransaction> get transactions => List.unmodifiable(_transactions);
  List<UpcomingExpense> get upcomingExpenses =>
      List.unmodifiable(_upcomingExpenses);
  List<FinancialAction> get actions => List.unmodifiable(_actions);

  UserFinancialData mergeInto(UserFinancialData source) => source.copyWith(
    referenceDate: referenceDate,
    accounts: List.of(accounts),
    budgetPeriods: List.of(periods),
    categoryBudgets: List.of(categoryBudgets),
    transactions: List.of(_transactions),
    upcomingExpenses: List.of(_upcomingExpenses),
    plannedCumulativePoints: List.of(plannedCumulativePoints),
    actions: List.of(_actions),
  );

  void _addAction(FinancialAction action) {
    _actions.insert(0, action);
    if (_actions.length > 50) _actions.removeRange(50, _actions.length);
  }

  Future<void> _changed() async {
    notifyListeners();
    await onChanged?.call();
  }

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

  Future<void> addImportedTransactions(
    Iterable<BudgetTransaction> transactions, {
    String actionTitle = 'Добавление операции',
  }) async {
    final knownIds = _transactions.map((transaction) => transaction.id).toSet();
    final additions = <BudgetTransaction>[];
    for (final transaction in transactions) {
      if (knownIds.add(transaction.id)) additions.add(transaction);
    }
    if (additions.isEmpty) return;
    _transactions.addAll(additions);
    _addAction(
      FinancialAction(
        id: 'action-${DateTime.now().microsecondsSinceEpoch}',
        occurredAt: DateTime.now(),
        title: actionTitle,
        type: FinancialActionType.transactionAdded,
        createdTransactionIds: additions.map((item) => item.id).toList(),
      ),
    );
    await _changed();
  }

  Future<int> importStatement({
    required QestoAccount account,
    required Iterable<BudgetTransaction> transactions,
    required Set<String> createdPeriodIds,
    required String actionTitle,
  }) async {
    final additions = <BudgetTransaction>[];
    final previousTransactions = <BudgetTransaction>[];
    for (final transaction in transactions) {
      final index = _transactions.indexWhere(
        (item) => item.id == transaction.id,
      );
      if (index < 0) {
        additions.add(transaction);
        continue;
      }
      final existing = _transactions[index];
      if (existing.accountId != account.id ||
          existing.type != transaction.type ||
          existing.transferDirection != transaction.transferDirection) {
        previousTransactions.add(existing);
        _transactions[index] = existing.copyWith(
          accountId: account.id,
          type: transaction.type,
          transferDirection: transaction.transferDirection,
        );
      }
    }

    final previousAccounts = <QestoAccount>[];
    final createdAccountIds = <String>[];
    var accountChanged = false;
    final accountIndex = accounts.indexWhere((item) => item.id == account.id);
    if (accountIndex < 0) {
      accounts.add(account);
      createdAccountIds.add(account.id);
      accountChanged = true;
    } else if (!_sameAccount(accounts[accountIndex], account)) {
      previousAccounts.add(accounts[accountIndex]);
      accounts[accountIndex] = account;
      accountChanged = true;
    }

    final placeholderIndex = accounts.indexWhere(
      (item) =>
          item.id == 'local-default-account' &&
          item.balance == 0 &&
          !_transactions.any((transaction) => transaction.accountId == item.id),
    );
    if (placeholderIndex >= 0 && accounts.length > 1) {
      previousAccounts.add(accounts.removeAt(placeholderIndex));
      accountChanged = true;
    }

    _transactions.addAll(additions);
    if (additions.isEmpty && previousTransactions.isEmpty && !accountChanged) {
      return 0;
    }
    _addAction(
      FinancialAction(
        id: 'action-${DateTime.now().microsecondsSinceEpoch}',
        occurredAt: DateTime.now(),
        title: actionTitle,
        type: FinancialActionType.statementImport,
        createdTransactionIds: additions.map((item) => item.id).toList(),
        createdAccountIds: createdAccountIds,
        createdPeriodIds: createdPeriodIds.toList(),
        previousTransactions: previousTransactions,
        previousAccounts: previousAccounts,
      ),
    );
    await _changed();
    return additions.length;
  }

  Future<void> addExpense({
    required BudgetPeriod period,
    required int amount,
    required DateTime date,
    required String categoryId,
    required String accountId,
    required String title,
    String? subcategoryId,
    String? comment,
  }) async {
    final transaction = BudgetTransaction(
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
    );
    _transactions.add(transaction);
    _addAction(
      FinancialAction(
        id: 'action-${DateTime.now().microsecondsSinceEpoch}',
        occurredAt: DateTime.now(),
        title: 'Добавлен расход «$title»',
        type: FinancialActionType.transactionAdded,
        createdTransactionIds: [transaction.id],
      ),
    );
    await _changed();
  }

  Future<bool> undoAction(String id) async {
    final actionIndex = _actions.indexWhere((item) => item.id == id);
    if (actionIndex < 0 || _actions[actionIndex].isUndone) return false;
    final action = _actions[actionIndex];

    _transactions.removeWhere(
      (transaction) => action.createdTransactionIds.contains(transaction.id),
    );
    for (final previous in action.previousTransactions) {
      final index = _transactions.indexWhere((item) => item.id == previous.id);
      if (index < 0) {
        _transactions.add(previous);
      } else {
        _transactions[index] = previous;
      }
    }
    for (final accountId in action.createdAccountIds) {
      final isStillUsed = _transactions.any(
        (transaction) => transaction.accountId == accountId,
      );
      if (!isStillUsed) accounts.removeWhere((item) => item.id == accountId);
    }
    for (final previous in action.previousAccounts) {
      final index = accounts.indexWhere((item) => item.id == previous.id);
      if (index < 0) {
        accounts.add(previous);
      } else {
        accounts[index] = previous;
      }
    }
    for (final periodId in action.createdPeriodIds) {
      final hasTransactions = _transactions.any(
        (transaction) => periods
            .where((period) => period.id == periodId)
            .any((period) => period.contains(transaction.date)),
      );
      if (!hasTransactions && periods.length > 1) {
        periods.removeWhere((period) => period.id == periodId);
      }
    }
    _actions[actionIndex] = action.copyWith(isUndone: true);
    await _changed();
    return true;
  }

  bool _sameAccount(QestoAccount left, QestoAccount right) =>
      left.id == right.id &&
      left.userId == right.userId &&
      left.title == right.title &&
      left.balance == right.balance &&
      left.currency == right.currency &&
      left.type == right.type;

  Future<void> updateTransaction(BudgetTransaction transaction) async {
    final index = _transactions.indexWhere((item) => item.id == transaction.id);
    if (index < 0) return;
    _transactions[index] = transaction;
    await _changed();
  }

  Future<void> deleteTransaction(String id) async {
    final before = _transactions.length;
    _transactions.removeWhere((transaction) => transaction.id == id);
    if (_transactions.length != before) await _changed();
  }

  Future<void> addUpcoming(UpcomingExpense expense) async {
    _upcomingExpenses.add(expense);
    await _changed();
  }

  Future<void> updateUpcoming(UpcomingExpense expense) async {
    final index = _upcomingExpenses.indexWhere((item) => item.id == expense.id);
    if (index < 0) return;
    _upcomingExpenses[index] = expense;
    await _changed();
  }

  Future<void> deleteUpcoming(String id) async {
    final before = _upcomingExpenses.length;
    _upcomingExpenses.removeWhere((expense) => expense.id == id);
    if (_upcomingExpenses.length != before) await _changed();
  }
}
