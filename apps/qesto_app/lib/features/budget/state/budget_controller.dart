import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../data/models/qesto_models.dart';
import '../services/budget_calculation_service.dart';
import '../services/budget_forecast_service.dart';
import '../services/category_budget_calculation_service.dart';
import '../../../synoball/synoball.dart';

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
       _ledgerCurrency = financialData.user.defaultCurrency,
       user = financialData.user,
       periods = _resolvedPeriods(financialData),
       _baseCategories = List.of(configuration.categories),
       categories = _resolvedCategories(
         configuration.categories,
         financialData.categoryCustomizations,
       ),
       _categoryCustomizations = List.of(financialData.categoryCustomizations),
       categoryBudgets = List.of(financialData.categoryBudgets),
       plannedCumulativePoints = List.of(financialData.plannedCumulativePoints),
       _upcomingExpenses = List.of(financialData.upcomingExpenses),
       _actions = List.of(financialData.actions) {
    final storedState = financialData.synoballState;
    _synoball = SynoballCore(
      initialState: storedState ?? const SynoballState(),
    );
    if (storedState == null) {
      final input = _legacyBridge.buildInput(financialData);
      _synoball.upsertEntity(input.entity);
      _synoball.ingest(LegacyQestoAdapter(), input);
    }
    final readModel = _readModels.build(_synoball.state);
    accounts = List.of(
      readModel.accounts.isEmpty
          ? _resolvedAccounts(financialData)
          : readModel.accounts,
    );
    _transactions = List.of(readModel.transactions);
    _legacyTransactionIdentities = {
      for (final transaction in financialData.transactions)
        transaction.id: transaction,
    };
  }

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

  static List<BudgetCategory> _resolvedCategories(
    List<BudgetCategory> base,
    List<BudgetCategoryCustomization> customizations,
  ) {
    final byId = {
      for (final customization in customizations)
        customization.categoryId: customization,
    };
    return [
      for (final category in base)
        if (byId[category.id] case final customization?)
          category.copyWith(
            name: customization.name,
            iconKey: customization.iconKey,
            colorValue: customization.colorValue,
          )
        else
          category,
    ];
  }

  final DateTime referenceDate;
  final String _userId;
  final String _ledgerCurrency;
  QestoUser user;
  final List<BudgetPeriod> periods;
  final List<BudgetCategory> categories;
  final List<BudgetCategory> _baseCategories;
  final List<BudgetCategoryCustomization> _categoryCustomizations;
  final List<CategoryBudget> categoryBudgets;
  final List<BudgetPlanPoint> plannedCumulativePoints;
  late final List<QestoAccount> accounts;
  final BudgetCalculationService calculationService;
  final BudgetForecastService forecastService;
  final CategoryBudgetCalculationService categoryCalculationService;
  final Future<void> Function()? onChanged;

  late final List<BudgetTransaction> _transactions;
  late final Map<String, BudgetTransaction> _legacyTransactionIdentities;
  final List<UpcomingExpense> _upcomingExpenses;
  final List<FinancialAction> _actions;
  late SynoballCore _synoball;
  var _clearExternalData = false;
  final QestoLegacyBridge _legacyBridge = const QestoLegacyBridge();
  final QestoReadModelService _readModels = const QestoReadModelService();
  final FinancialStateService _financialStateService =
      const FinancialStateService();
  final AiContextService _aiContextService = const AiContextService();

  List<BudgetTransaction> get transactions => List.unmodifiable(_transactions);
  List<UpcomingExpense> get upcomingExpenses =>
      List.unmodifiable(_upcomingExpenses);
  List<FinancialAction> get actions => List.unmodifiable(_actions);
  SynoballState get synoballState => _synoball.state;
  List<TransactionCandidate> get pendingCandidates =>
      _synoball.pendingCandidates;

  FinancialState get financialState => _financialStateService.calculate(
    state: _synoball.state,
    entityId: _legacyBridge.entityIdFor(_userId),
    asOf: referenceDate,
    currency: _ledgerCurrency,
    plannedExpensesMinor: _upcomingExpenses
        .where((item) => !item.isCancelled)
        .fold(0, (total, item) => total + item.amount * 100),
  );

  AiFinancialContext aiContext(
    AiContextPurpose purpose, {
    int? proposedPurchaseMinor,
  }) => _aiContextService.build(
    purpose: purpose,
    state: financialState,
    proposedPurchaseMinor: proposedPurchaseMinor,
  );

  UserFinancialData mergeInto(UserFinancialData source) => source.copyWith(
    user: user,
    referenceDate: referenceDate,
    accounts: List.of(accounts),
    budgetPeriods: List.of(periods),
    categoryBudgets: List.of(categoryBudgets),
    categoryCustomizations: List.of(_categoryCustomizations),
    transactions: List.of(_transactions),
    upcomingExpenses: List.of(_upcomingExpenses),
    plannedCumulativePoints: List.of(plannedCumulativePoints),
    actions: List.of(_actions),
    savingsGoals: _clearExternalData ? const [] : source.savingsGoals,
    trackedProducts: _clearExternalData ? const [] : source.trackedProducts,
    synoballState: _synoball.state,
  );

  void _syncFromSynoball() {
    final readModel = _readModels.build(_synoball.state);
    accounts
      ..clear()
      ..addAll(readModel.accounts);
    _transactions
      ..clear()
      ..addAll(readModel.transactions);
  }

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
      currency: _ledgerCurrency,
    );
    periods.add(period);
    periods.sort((a, b) => a.startDate.compareTo(b.startDate));
    return period;
  }

  bool hasTransaction(String id) => _synoball.hasTransactionOrProviderId(id);

  Future<void> addImportedTransactions(
    Iterable<BudgetTransaction> transactions, {
    String actionTitle = 'Добавление операции',
  }) async {
    final createdIds = <String>[];
    for (final transaction in transactions) {
      if (hasTransaction(transaction.id)) continue;
      final receipt = transaction.receipt;
      final outcome = receipt == null
          ? _synoball.ingest(
              ManualInputAdapter(),
              ManualInput(
                entityId: _legacyBridge.entityIdFor(_userId),
                receivedAt: DateTime.now(),
                rawPayload: jsonEncode({
                  'source': 'qesto-import',
                  'id': transaction.id,
                  'description': transaction.description,
                }),
                transaction: _seedFromQesto(transaction),
              ),
            )
          : _ingestReceipt(
              transaction,
              rawPayload: jsonEncode({
                'fiscalDriveNumber': receipt.fiscalDriveNumber,
                'fiscalDocumentNumber': receipt.fiscalDocumentNumber,
                'fiscalSign': receipt.fiscalSign,
              }),
              rawText: transaction.description ?? transaction.comment ?? '',
            );
      createdIds.addAll(outcome.createdTransactionIds);
    }
    if (createdIds.isEmpty) {
      _syncFromSynoball();
      await _changed();
      return;
    }
    _syncFromSynoball();
    _addAction(
      FinancialAction(
        id: 'action-${DateTime.now().microsecondsSinceEpoch}',
        occurredAt: DateTime.now(),
        title: actionTitle,
        type: FinancialActionType.transactionAdded,
        createdTransactionIds: createdIds,
      ),
    );
    await _changed();
  }

  Future<int> importStatement({
    required QestoAccount account,
    required Iterable<BudgetTransaction> transactions,
    required Set<String> createdPeriodIds,
    required String actionTitle,
    String? rawPayload,
    Map<String, int> exactMinorById = const {},
    List<QestoAccount> additionalAccounts = const [],
  }) async {
    final incoming = transactions.toList(growable: false);
    final previousTransactions = <BudgetTransaction>[];
    for (final transaction in incoming) {
      final index = _transactions.indexWhere(
        (item) => item.id == transaction.id,
      );
      if (index < 0) continue;
      final existing = _transactions[index];
      previousTransactions.add(
        _legacyTransactionIdentities[existing.id] ?? existing,
      );
    }

    final previousAccounts = <QestoAccount>[];
    final createdAccountIds = <String>[];
    var accountChanged = false;
    final importedAccounts = <String, QestoAccount>{
      account.id: account,
      for (final item in additionalAccounts) item.id: item,
    };
    for (final importedAccount in importedAccounts.values) {
      final accountIndex = accounts.indexWhere(
        (item) => item.id == importedAccount.id,
      );
      if (accountIndex < 0) {
        createdAccountIds.add(importedAccount.id);
        accountChanged = true;
      } else if (!_sameAccount(accounts[accountIndex], importedAccount)) {
        previousAccounts.add(accounts[accountIndex]);
        accountChanged = true;
      }
    }
    final entityId = _legacyBridge.entityIdFor(_userId);
    final synoballAccount = _legacyBridge.accountFromQesto(account);
    for (final additional in importedAccounts.values.where(
      (item) => item.id != account.id,
    )) {
      _synoball.upsertAccount(_legacyBridge.accountFromQesto(additional));
    }
    final outcome = _synoball.ingest(
      StatementAdapter(),
      StatementInput(
        entityId: entityId,
        receivedAt: DateTime.now(),
        rawPayload:
            rawPayload ??
            jsonEncode({
              'source': 'qesto-statement',
              'transactions': incoming.map((item) => item.id).toList(),
            }),
        batchName: actionTitle,
        transactions: incoming
            .map(
              (item) => _seedFromQesto(
                item,
                exactMinor: exactMinorById[item.id],
                providerTransactionId: item.id,
              ),
            )
            .toList(growable: false),
        account: synoballAccount,
      ),
    );
    final incomingById = {for (final item in incoming) item.id: item};
    for (final matchedId in outcome.matchedTransactionIds) {
      final updated = incomingById[matchedId];
      final canonical = _synoball.transactionById(matchedId);
      if (updated == null || canonical == null) continue;
      // A re-import is an explicit adapter refresh. Replace the old legacy
      // type tag instead of leaving both `expense` and `investment` on the
      // same canonical operation after Synoball merges its evidence.
      _synoball.updateTransaction(
        _legacyBridge.canonicalFromQesto(updated, previous: canonical),
        actorId: _userId,
        purpose: 'Refresh a statement operation through its source adapter',
      );
    }
    if (accounts.any((item) => item.id == 'local-default-account') &&
        account.id != 'local-default-account') {
      final placeholder = accounts.firstWhere(
        (item) => item.id == 'local-default-account',
      );
      _synoball.removeAccountIfUnused(placeholder.id);
      if (!_synoball.state.accounts.any((item) => item.id == placeholder.id)) {
        previousAccounts.add(placeholder);
        accountChanged = true;
      }
    }
    _syncFromSynoball();
    if (outcome.createdTransactionIds.isEmpty &&
        outcome.matchedTransactionIds.isEmpty &&
        previousTransactions.isEmpty &&
        !accountChanged) {
      return 0;
    }
    _addAction(
      FinancialAction(
        id: 'action-${DateTime.now().microsecondsSinceEpoch}',
        occurredAt: DateTime.now(),
        title: actionTitle,
        type: FinancialActionType.statementImport,
        createdTransactionIds: outcome.createdTransactionIds,
        createdAccountIds: createdAccountIds,
        createdPeriodIds: createdPeriodIds.toList(),
        previousTransactions: previousTransactions,
        previousAccounts: previousAccounts,
      ),
    );
    await _changed();
    return outcome.createdTransactionIds.length;
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
      tags: const ['legacy-type-expense'],
    );
    final outcome = _synoball.ingest(
      ManualInputAdapter(),
      ManualInput(
        entityId: _legacyBridge.entityIdFor(_userId),
        receivedAt: DateTime.now(),
        rawPayload: jsonEncode({
          'amountMinor': amount * 100,
          'currency': period.currency,
          'date': date.toIso8601String(),
          'categoryId': categoryId,
          'accountId': accountId,
          'title': title,
          'subcategoryId': subcategoryId,
          'comment': comment,
        }),
        transaction: _seedFromQesto(transaction),
      ),
    );
    _syncFromSynoball();
    _addAction(
      FinancialAction(
        id: 'action-${DateTime.now().microsecondsSinceEpoch}',
        occurredAt: DateTime.now(),
        title: 'Добавлен расход «$title»',
        type: FinancialActionType.transactionAdded,
        createdTransactionIds: outcome.createdTransactionIds,
      ),
    );
    await _changed();
  }

  Future<IngestionOutcome> addAndroidNotificationExpense({
    required BudgetPeriod period,
    required int amountMinor,
    required DateTime date,
    required String categoryId,
    required String accountId,
    required String title,
    required String notificationKey,
    required String packageName,
    required String rawNotification,
    String? subcategoryId,
    double confidence = 0.8,
  }) async {
    final outcome = _synoball.ingest(
      AndroidNotificationAdapter(),
      AndroidNotificationInput(
        entityId: _legacyBridge.entityIdFor(_userId),
        receivedAt: DateTime.now(),
        rawPayload: rawNotification,
        notificationKey: notificationKey,
        packageName: packageName,
        transaction: TransactionSeed(
          accountId: accountId,
          amount: Money(
            minorUnits: amountMinor.abs(),
            currency: period.currency,
          ),
          direction: FinancialDirection.outflow,
          occurredAt: date,
          description: rawNotification,
          merchant: title,
          category: categoryId,
          subcategoryId: subcategoryId,
          providerTransactionId: notificationKey,
          tags: const ['legacy-type-expense', 'android-notification'],
          confidence: confidence,
        ),
      ),
    );
    _syncFromSynoball();
    if (outcome.createdTransactionIds.isNotEmpty) {
      _addAction(
        FinancialAction(
          id: 'action-${DateTime.now().microsecondsSinceEpoch}',
          occurredAt: DateTime.now(),
          title: 'Добавлен расход «$title»',
          type: FinancialActionType.transactionAdded,
          createdTransactionIds: outcome.createdTransactionIds,
        ),
      );
    }
    await _changed();
    return outcome;
  }

  Future<IngestionOutcome> ingestReceiptTransaction(
    BudgetTransaction transaction, {
    required String rawPayload,
    required String rawText,
  }) async {
    final outcome = _ingestReceipt(
      transaction,
      rawPayload: rawPayload,
      rawText: rawText,
    );
    _syncFromSynoball();
    if (outcome.createdTransactionIds.isNotEmpty) {
      _addAction(
        FinancialAction(
          id: 'action-${DateTime.now().microsecondsSinceEpoch}',
          occurredAt: DateTime.now(),
          title: 'Добавлен кассовый чек',
          type: FinancialActionType.transactionAdded,
          createdTransactionIds: outcome.createdTransactionIds,
        ),
      );
    }
    await _changed();
    return outcome;
  }

  Future<String> addVoiceCandidate({
    required String transcript,
    required int amountMinor,
    required String currency,
    required String accountId,
    required DateTime occurredAt,
    required String merchant,
    String? categoryId,
    double confidence = 0.7,
  }) async {
    final outcome = _synoball.ingest(
      VoiceInputAdapter(),
      VoiceInput(
        entityId: _legacyBridge.entityIdFor(_userId),
        receivedAt: DateTime.now(),
        rawPayload: transcript,
        transcript: transcript,
        transaction: TransactionSeed(
          accountId: accountId,
          amount: Money(minorUnits: amountMinor.abs(), currency: currency),
          direction: FinancialDirection.outflow,
          occurredAt: occurredAt,
          description: transcript,
          merchant: merchant,
          category: categoryId,
          confidence: confidence,
          requiresConfirmation: true,
          tags: const ['legacy-type-expense', 'voice-input'],
        ),
      ),
    );
    await _changed();
    return outcome.pendingCandidateIds.single;
  }

  Future<String> confirmVoiceCandidate(String candidateId) async {
    final id = _synoball.confirmCandidate(candidateId, actorId: _userId);
    _syncFromSynoball();
    await _changed();
    return id;
  }

  Future<bool> undoAction(String id) async {
    final actionIndex = _actions.indexWhere((item) => item.id == id);
    if (actionIndex < 0 || _actions[actionIndex].isUndone) return false;
    final action = _actions[actionIndex];

    for (final transactionId in action.createdTransactionIds) {
      _synoball.deleteTransaction(transactionId, actorId: _userId);
    }
    for (final previous in action.previousTransactions) {
      final canonical = _synoball.transactionById(previous.id);
      if (canonical != null) {
        _synoball.restoreTransaction(
          _legacyBridge.canonicalFromQesto(previous, previous: canonical),
        );
      }
    }
    for (final accountId in action.createdAccountIds) {
      _synoball.removeAccountIfUnused(accountId);
    }
    for (final previous in action.previousAccounts) {
      _synoball.upsertAccount(_legacyBridge.accountFromQesto(previous));
    }
    _syncFromSynoball();
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
    final canonical = _synoball.transactionById(transaction.id);
    if (canonical == null) return;
    _synoball.updateTransaction(
      _legacyBridge.canonicalFromQesto(transaction, previous: canonical),
      actorId: _userId,
    );
    _syncFromSynoball();
    await _changed();
  }

  Future<void> updateTransactions(
    Iterable<BudgetTransaction> transactions,
  ) async {
    var changed = false;
    for (final transaction in transactions) {
      final canonical = _synoball.transactionById(transaction.id);
      if (canonical == null) continue;
      _synoball.updateTransaction(
        _legacyBridge.canonicalFromQesto(transaction, previous: canonical),
        actorId: _userId,
      );
      changed = true;
    }
    if (!changed) return;
    _syncFromSynoball();
    await _changed();
  }

  Future<void> setCategoryBudget({
    required BudgetPeriod period,
    required String categoryId,
    required int plannedAmount,
  }) async {
    final index = categoryBudgets.indexWhere(
      (item) =>
          item.budgetPeriodId == period.id && item.categoryId == categoryId,
    );
    final value = CategoryBudget(
      id: index < 0
          ? 'category-budget-${period.id}-$categoryId'
          : categoryBudgets[index].id,
      budgetPeriodId: period.id,
      categoryId: categoryId,
      plannedAmount: plannedAmount.clamp(0, 1000000000),
    );
    if (index < 0) {
      categoryBudgets.add(value);
    } else {
      categoryBudgets[index] = value;
    }
    await _changed();
  }

  Future<void> setTotalBudget({
    required BudgetPeriod period,
    required int totalPlan,
  }) async {
    final index = periods.indexWhere((item) => item.id == period.id);
    if (index < 0) return;
    periods[index] = periods[index].copyWith(
      totalPlan: totalPlan.clamp(0, 1000000000),
    );
    plannedCumulativePoints.removeWhere(
      (point) => point.budgetPeriodId == period.id,
    );
    await _changed();
  }

  Future<void> updateCategoryAppearance({
    required String categoryId,
    required String name,
    required String iconKey,
    required int colorValue,
  }) async {
    final index = categories.indexWhere((item) => item.id == categoryId);
    if (index < 0) return;
    final cleanedName = name.trim();
    final current = categories[index];
    final updated = current.copyWith(
      name: cleanedName.isEmpty ? current.name : cleanedName,
      iconKey: iconKey,
      colorValue: colorValue,
    );
    categories[index] = updated;
    final customization = BudgetCategoryCustomization(
      categoryId: categoryId,
      name: updated.name,
      iconKey: updated.iconKey,
      colorValue: updated.colorValue,
    );
    final customizationIndex = _categoryCustomizations.indexWhere(
      (item) => item.categoryId == categoryId,
    );
    if (customizationIndex < 0) {
      _categoryCustomizations.add(customization);
    } else {
      _categoryCustomizations[customizationIndex] = customization;
    }
    await _changed();
  }

  Future<QestoAccount> addAccount({
    required String title,
    required int balance,
    required AccountType type,
    String? currency,
  }) async {
    final id = 'account-${DateTime.now().microsecondsSinceEpoch}';
    final resolvedCurrency = currency ?? user.defaultCurrency;
    final account = QestoAccount(
      id: id,
      userId: _userId,
      title: title,
      balance: balance,
      currency: resolvedCurrency,
      type: type,
    );
    _synoball.upsertAccount(
      SynoballAccount(
        id: id,
        entityId: _legacyBridge.entityIdFor(_userId),
        name: title,
        type: switch (type) {
          AccountType.cash => SynoballAccountType.cash,
          AccountType.bankCard => SynoballAccountType.card,
          AccountType.savings => SynoballAccountType.savings,
          AccountType.deposit => SynoballAccountType.deposit,
          AccountType.investment => SynoballAccountType.investment,
          AccountType.liability => SynoballAccountType.loan,
          _ => SynoballAccountType.other,
        },
        currency: resolvedCurrency,
        balance: Money(minorUnits: balance * 100, currency: resolvedCurrency),
      ),
    );
    _syncFromSynoball();
    await _changed();
    return account;
  }

  Future<void> deleteTransaction(String id) async {
    if (!hasTransaction(id)) return;
    _synoball.deleteTransaction(id, actorId: _userId);
    _syncFromSynoball();
    await _changed();
  }

  /// Clears user financial content while retaining only the minimum local
  /// profile/account scaffold required for the UI to remain operational.
  Future<void> clearAllFinancialData() async {
    _synoball = SynoballCore();
    final entityId = _legacyBridge.entityIdFor(_userId);
    _synoball.upsertEntity(
      SynoballEntity(
        id: entityId,
        type: SynoballEntityType.person,
        displayName: user.name,
      ),
    );
    _synoball.upsertAccount(
      SynoballAccount(
        id: 'local-default-account',
        entityId: entityId,
        name: 'Основной счёт',
        type: SynoballAccountType.other,
        currency: _ledgerCurrency,
        balance: Money(minorUnits: 0, currency: _ledgerCurrency),
        isVirtual: true,
      ),
    );
    _syncFromSynoball();
    periods
      ..clear()
      ..add(
        BudgetPeriod(
          id: 'local-${referenceDate.year}-${referenceDate.month.toString().padLeft(2, '0')}',
          userId: _userId,
          startDate: DateTime(referenceDate.year, referenceDate.month),
          endDate: DateTime(referenceDate.year, referenceDate.month + 1, 0),
          type: BudgetPeriodType.calendarMonth,
          totalPlan: 0,
          currency: _ledgerCurrency,
        ),
      );
    categoryBudgets.clear();
    _categoryCustomizations.clear();
    categories
      ..clear()
      ..addAll(_baseCategories);
    plannedCumulativePoints.clear();
    _upcomingExpenses.clear();
    _actions.clear();
    _legacyTransactionIdentities.clear();
    _clearExternalData = true;
    await _changed();
  }

  Future<void> updateUserProfile({
    required String name,
    required String defaultCurrency,
    String? avatarUrl,
  }) async {
    final cleanedName = name.trim();
    final cleanedCurrency = defaultCurrency.trim().toUpperCase();
    if (cleanedName.isEmpty || cleanedCurrency.length != 3) return;
    user = user.copyWith(
      name: cleanedName,
      defaultCurrency: cleanedCurrency,
      avatarUrl: avatarUrl,
      clearAvatar: avatarUrl == null,
    );
    _synoball.upsertEntity(
      SynoballEntity(
        id: _legacyBridge.entityIdFor(_userId),
        type: SynoballEntityType.person,
        displayName: cleanedName,
      ),
    );
    await _changed();
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

  TransactionSeed _seedFromQesto(
    BudgetTransaction transaction, {
    int? exactMinor,
    String? providerTransactionId,
  }) {
    final direction = switch (transaction.type) {
      TransactionType.income ||
      TransactionType.refund => FinancialDirection.inflow,
      TransactionType.transfer =>
        transaction.transferDirection == null
            ? FinancialDirection.neutral
            : transaction.transferDirection == TransferDirection.incoming
            ? FinancialDirection.inflow
            : FinancialDirection.outflow,
      _ => FinancialDirection.outflow,
    };
    return TransactionSeed(
      canonicalId: transaction.id,
      accountId: transaction.accountId,
      amount: Money(
        minorUnits: exactMinor?.abs() ?? transaction.amount.abs() * 100,
        currency: transaction.currency,
      ),
      direction: direction,
      occurredAt: transaction.date,
      description:
          transaction.description ??
          transaction.comment ??
          transaction.title ??
          transaction.merchant ??
          '',
      merchant:
          transaction.normalizedMerchant ??
          transaction.merchant ??
          transaction.title,
      providerCategory: transaction.originalCategoryId,
      category: transaction.categoryId,
      subcategoryId: transaction.subcategoryId,
      providerTransactionId: providerTransactionId ?? transaction.id,
      receiptId: transaction.receipt?.id,
      transferDirection: transaction.transferDirection?.name,
      tags: {
        ...transaction.tags,
        'legacy-type-${transaction.type.name}',
        if (transaction.type == TransactionType.refund) 'refund',
        if (transaction.isPotentialDuplicate) 'qesto-potential-duplicate',
        if (transaction.isLargePurchase) 'qesto-large-purchase',
        if (!transaction.isConfirmed) 'qesto-unconfirmed',
        if (transaction.isRecurring) 'qesto-recurring',
      }.toList(),
      confidence: transaction.classificationConfidence,
    );
  }

  IngestionOutcome _ingestReceipt(
    BudgetTransaction transaction, {
    required String rawPayload,
    required String rawText,
  }) {
    final receipt = transaction.receipt;
    if (receipt == null) {
      throw ArgumentError.value(transaction, 'transaction', 'Receipt required');
    }
    final fingerprint =
        '${receipt.fiscalDriveNumber}:'
        '${receipt.fiscalDocumentNumber}:${receipt.fiscalSign}';
    return _synoball.ingest(
      ReceiptAdapter(),
      ReceiptInput(
        entityId: _legacyBridge.entityIdFor(_userId),
        receivedAt: DateTime.now(),
        rawPayload: rawPayload,
        transaction: _seedFromQesto(
          transaction,
          exactMinor: receipt.totalMinor,
          providerTransactionId: fingerprint,
        ),
        fiscalFingerprint: fingerprint,
        rawText: rawText,
        merchant: receipt.merchant ?? transaction.merchant,
        items: receipt.items
            .map(
              (item) => ReceiptItem(
                name: item.name,
                quantity: item.quantity,
                unitPrice: item.unitPriceMinor == null
                    ? null
                    : Money(
                        minorUnits: item.unitPriceMinor!,
                        currency: transaction.currency,
                      ),
                total: Money(
                  minorUnits: item.totalMinor,
                  currency: transaction.currency,
                ),
              ),
            )
            .toList(growable: false),
        confidence: transaction.classificationConfidence,
      ),
    );
  }
}
