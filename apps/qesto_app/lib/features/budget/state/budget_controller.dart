import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import '../../../core/safety/financial_write_guard.dart';

import '../../../data/models/qesto_models.dart';
import '../services/budget_calculation_service.dart';
import '../services/budget_forecast_service.dart';
import '../services/cash_flow_calculation_service.dart';
import '../services/category_budget_calculation_service.dart';
import '../../../synoball/synoball.dart';
import '../../../synoball/adapters/notification_identity.dart';
import '../../../synoball/adapters/source_identity.dart';
import '../../bank_screenshot_import/domain/bank_screenshot_models.dart';
import '../../bank_screenshot_import/services/bank_screenshot_identity.dart';
import '../../bank_browser/sber/sber_connector_models.dart';
import '../../transaction_import/services/transaction_category_resolver.dart';

const _transactionCategoryResolver = TransactionCategoryResolver();

ResolvedTransactionCategory _sberCategory(SberTransactionFact value) =>
    _transactionCategoryResolver.resolve(
      '${value.merchant ?? ''} ${value.category ?? ''} '
      '${value.description} ${value.operationType ?? ''}',
    );

String _sberIdentityText(String value) => value
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _sberIdentityMoment(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}T'
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

String _sberFactIdentity(SberTransactionFact value) => [
  _sberIdentityMoment(value.date),
  value.amountMinor.abs(),
  value.currency.toUpperCase(),
  value.isIncome ? 'in' : 'out',
  _sberIdentityText(value.merchant ?? value.description),
].join('|');

String _storedSberIdentity(BudgetTransaction value) => [
  _sberIdentityMoment(value.date),
  value.amountMinor.abs(),
  value.currency.toUpperCase(),
  value.type == TransactionType.income ||
          value.type == TransactionType.refund ||
          value.transferDirection == TransferDirection.incoming
      ? 'in'
      : 'out',
  _sberIdentityText(
    value.merchant ?? value.title ?? value.description ?? value.comment ?? '',
  ),
].join('|');

String _candidateSberIdentity(TransactionCandidate value) => [
  _sberIdentityMoment(value.occurredAt),
  value.amount.minorUnits.abs(),
  value.amount.currency.toUpperCase(),
  value.direction == FinancialDirection.inflow ? 'in' : 'out',
  _sberIdentityText(
    value.merchantGuess ?? value.normalizedDescription ?? value.rawDescription,
  ),
].join('|');

bool _sameStringSet(List<String> left, List<String> right) =>
    left.length == right.length && left.toSet().containsAll(right);

class BudgetController extends ChangeNotifier {
  int _dataGeneration = 0;
  bool _disposed = false;
  int get dataGeneration => _dataGeneration;
  void _checkWrite([int? expectedGeneration]) {
    FinancialWriteGuard.check();
    if (_disposed ||
        (expectedGeneration != null && expectedGeneration != _dataGeneration)) {
      throw StateError(
        'Financial data changed while the operation was running',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _dataGeneration++;
    super.dispose();
  }

  BudgetController({
    required BudgetConfiguration configuration,
    required UserFinancialData financialData,
    this.onChanged,
    this.calculationService = const BudgetCalculationService(),
    this.forecastService = const BudgetForecastService(),
    this.categoryCalculationService = const CategoryBudgetCalculationService(),
    this.cashFlowCalculationService = const CashFlowCalculationService(),
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
       accountPreferences = List.of(financialData.accountPreferences),
       plannedCumulativePoints = List.of(financialData.plannedCumulativePoints),
       savingsGoals = List.of(financialData.savingsGoals),
       goalAllocations = List.of(financialData.goalAllocations),
       goalContributions = List.of(financialData.goalContributions),
       goalHistoryEvents = List.of(financialData.goalHistoryEvents),
       investmentAccounts = List.of(financialData.investmentAccounts),
       investmentBalanceSnapshots = List.of(
         financialData.investmentBalanceSnapshots,
       ),
       investmentContributions = List.of(financialData.investmentContributions),
       debts = List.of(financialData.debts),
       debtBalanceSnapshots = List.of(financialData.debtBalanceSnapshots),
       debtPayments = List.of(financialData.debtPayments),
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
    if (debts.isEmpty) {
      for (final account in accounts.where(
        (item) => item.type == AccountType.liability,
      )) {
        debts.add(
          DebtAccount(
            id: 'legacy-debt-${account.id}',
            userId: _userId,
            name: account.title,
            type: DebtType.other,
            currency: account.currency,
            currentBalance: account.balance.abs(),
            status: DebtStatus.active,
            source: DebtSource.calculated,
            dataQuality: DebtDataQuality.incomplete,
            confidence: 0.5,
            createdAt: referenceDate,
            updatedAt: referenceDate,
            linkedAccountId: account.id,
          ),
        );
      }
    }
    if (investmentAccounts.isEmpty) {
      for (final account in accounts.where(
        (item) => item.type == AccountType.investment,
      )) {
        final id = 'legacy-investment-${account.id}';
        investmentAccounts.add(
          InvestmentAccount(
            id: id,
            userId: _userId,
            linkedAccountId: account.id,
            name: account.title,
            type: InvestmentAccountType.other,
            currency: account.currency,
            currentBalance: account.balance,
            status: InvestmentAccountStatus.active,
            source: InvestmentDataSource.calculated,
            createdAt: referenceDate,
            updatedAt: referenceDate,
            lastBalanceUpdateAt: referenceDate,
          ),
        );
        investmentBalanceSnapshots.add(
          InvestmentBalanceSnapshot(
            id: 'legacy-investment-snapshot-${account.id}',
            investmentAccountId: id,
            date: referenceDate,
            balance: account.balance,
            currency: account.currency,
            source: InvestmentDataSource.calculated,
            createdAt: referenceDate,
          ),
        );
      }
    }
    _transactions = List.of(
      _applySberAdapterCompatibility(readModel.transactions),
    );
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

  static Iterable<BudgetTransaction> _applySberAdapterCompatibility(
    Iterable<BudgetTransaction> transactions,
  ) sync* {
    for (final transaction in transactions) {
      if (!transaction.tags.contains('sberbank')) {
        yield transaction;
        continue;
      }
      var compatible = transaction;
      final normalizedTransferText =
          '${transaction.merchant ?? ''} ${transaction.title ?? ''} '
                  '${transaction.description ?? ''} '
                  '${transaction.comment ?? ''} '
                  '${transaction.originalCategoryId ?? ''}'
              .toLowerCase()
              .replaceAll('ё', 'е');
      final ownAccountMovement = RegExp(
        r'между\s+(?:своими|собственными)|на\s+сво[юий]\s+(?:карт|счет)|со\s+своего\s+(?:счета|карт)',
      ).hasMatch(normalizedTransferText);
      final cashMovement =
          normalizedTransferText.contains('внесение наличных') ||
          normalizedTransferText.contains('выдача наличных');
      final hasTransferSemantics =
          transaction.type == TransactionType.transfer ||
          transaction.tags.contains(qestoInternalTransferTag) ||
          transaction.tags.contains(qestoExternalTransferTag);
      // Legacy data needs textual repair, but a current source classification
      // must not be re-decided from a shortened UI description. That text can
      // omit "между своими", while the original bank row states it explicitly.
      if (hasTransferSemantics &&
          !transaction.tags.contains('user-field:type') &&
          !transaction.tags.contains('sber-classification:v2')) {
        final tags = transaction.tags.toSet();
        if (ownAccountMovement || cashMovement) {
          tags
            ..remove(qestoExternalTransferTag)
            ..add(qestoInternalTransferTag);
          compatible = compatible.copyWith(
            type: TransactionType.transfer,
            tags: tags.toList(growable: false),
          );
        } else {
          tags
            ..remove(qestoInternalTransferTag)
            ..add(qestoExternalTransferTag);
          compatible = compatible.copyWith(
            type:
                transaction.transferDirection == TransferDirection.incoming ||
                    transaction.type == TransactionType.income
                ? TransactionType.income
                : TransactionType.expense,
            tags: tags.toList(growable: false),
          );
        }
      }
      if (!transaction.tags.contains(qestoManualCategoryTag)) {
        final resolved = compatible.type == TransactionType.income
            ? const ResolvedTransactionCategory(
                categoryId: 'business',
                confidence: 0.95,
              )
            : _transactionCategoryResolver.resolve(
                '${transaction.merchant ?? ''} ${transaction.title ?? ''} '
                '${transaction.description ?? ''} '
                '${transaction.originalCategoryId ?? ''}',
              );
        compatible = compatible.copyWith(
          categoryId: resolved.categoryId,
          subcategoryId: resolved.subcategoryId,
          classificationConfidence: resolved.confidence,
        );
      }
      if (compatible.tags.contains('sber-status-refund') &&
          !transaction.tags.contains('user-field:type') &&
          compatible.type != TransactionType.refund) {
        yield compatible.copyWith(type: TransactionType.refund);
        continue;
      }
      yield compatible;
    }
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
  final List<QestoAccountPreferences> accountPreferences;
  final List<BudgetPlanPoint> plannedCumulativePoints;
  final List<SavingsGoal> savingsGoals;
  final List<GoalAllocation> goalAllocations;
  final List<GoalContribution> goalContributions;
  final List<GoalHistoryEvent> goalHistoryEvents;
  final List<InvestmentAccount> investmentAccounts;
  final List<InvestmentBalanceSnapshot> investmentBalanceSnapshots;
  final List<InvestmentContribution> investmentContributions;
  final List<DebtAccount> debts;
  final List<DebtBalanceSnapshot> debtBalanceSnapshots;
  final List<DebtPayment> debtPayments;
  late final List<QestoAccount> accounts;
  final BudgetCalculationService calculationService;
  final BudgetForecastService forecastService;
  final CategoryBudgetCalculationService categoryCalculationService;
  final CashFlowCalculationService cashFlowCalculationService;
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
  List<CanonicalTransaction> get trashedTransactions {
    final items =
        _synoball.state.transactions
            .where((item) => item.status == CanonicalTransactionStatus.deleted)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(items);
  }

  List<UpcomingExpense> get upcomingExpenses =>
      List.unmodifiable(_upcomingExpenses);
  List<FinancialAction> get actions => List.unmodifiable(_actions);
  SynoballState get synoballState => _synoball.state;
  List<TransactionCandidate> get pendingCandidates =>
      _synoball.pendingCandidates;

  QestoCashFlowSummary cashFlowForRange({
    required DateTime from,
    required DateTime toExclusive,
    String? currency,
  }) => cashFlowCalculationService.calculate(
    transactions: _transactions,
    from: from,
    toExclusive: toExclusive,
    currency: currency,
  );

  QestoCashFlowSummary cashFlowFor(BudgetPeriod period) => cashFlowForRange(
    from: period.startDate,
    toExclusive: period.endDate.add(const Duration(days: 1)),
    currency: period.currency,
  );

  CashFlowTreatment cashFlowTreatment(BudgetTransaction transaction) =>
      cashFlowCalculationService.treatment(transaction);

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
    accountPreferences: List.of(accountPreferences),
    budgetPeriods: List.of(periods),
    categoryBudgets: List.of(categoryBudgets),
    categoryCustomizations: List.of(_categoryCustomizations),
    transactions: List.of(_transactions),
    upcomingExpenses: List.of(_upcomingExpenses),
    plannedCumulativePoints: List.of(plannedCumulativePoints),
    actions: List.of(_actions),
    savingsGoals: List.of(savingsGoals),
    goalAllocations: List.of(goalAllocations),
    goalContributions: List.of(goalContributions),
    goalHistoryEvents: List.of(goalHistoryEvents),
    investmentAccounts: List.of(investmentAccounts),
    investmentBalanceSnapshots: List.of(investmentBalanceSnapshots),
    investmentContributions: List.of(investmentContributions),
    debts: List.of(debts),
    debtBalanceSnapshots: List.of(debtBalanceSnapshots),
    debtPayments: List.of(debtPayments),
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
      ..addAll(_applySberAdapterCompatibility(readModel.transactions));
  }

  void _addAction(FinancialAction action) {
    _actions.insert(0, action);
    if (_actions.length > 50) _actions.removeRange(50, _actions.length);
  }

  Future<void> _changed() async {
    _checkWrite();
    await onChanged?.call();
    _checkWrite();
    notifyListeners();
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

  QestoAccountPreferences accountPreferencesFor(String accountId) {
    for (final value in accountPreferences) {
      if (value.accountId == accountId) return value;
    }
    final account = accounts.where((item) => item.id == accountId).firstOrNull;
    final type = account?.type ?? AccountType.other;
    final isLiquid = {
      AccountType.bankCard,
      AccountType.cash,
      AccountType.savings,
      AccountType.deposit,
    }.contains(type);
    final isReserve = {AccountType.savings, AccountType.deposit}.contains(type);
    return QestoAccountPreferences(
      accountId: accountId,
      role: isReserve ? QestoAccountRole.savings : QestoAccountRole.everyday,
      includeInTotal: isLiquid,
      includeInNetWorth: type != AccountType.liability,
      includeInEmergencyFund: isReserve,
    );
  }

  Future<void> updateAccountPreferences(
    QestoAccountPreferences preferences,
  ) async {
    if (!accounts.any((item) => item.id == preferences.accountId)) return;
    final index = accountPreferences.indexWhere(
      (item) => item.accountId == preferences.accountId,
    );
    if (index < 0) {
      accountPreferences.add(preferences);
    } else {
      accountPreferences[index] = preferences;
    }
    await _changed();
  }

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
    bool confirmedVoiceInput = false,
  }) async {
    final createdIds = <String>[];
    for (final transaction in transactions) {
      if (hasTransaction(transaction.id)) {
        if (confirmedVoiceInput) await updateTransaction(transaction);
        continue;
      }
      final receipt = transaction.receipt;
      final outcome = receipt != null
          ? _ingestReceipt(
              transaction,
              rawPayload: jsonEncode({
                'fiscalDriveNumber': receipt.fiscalDriveNumber,
                'fiscalDocumentNumber': receipt.fiscalDocumentNumber,
                'fiscalSign': receipt.fiscalSign,
              }),
              rawText: transaction.description ?? transaction.comment ?? '',
            )
          : confirmedVoiceInput
          ? _synoball.ingest(
              VoiceInputAdapter(),
              VoiceInput(
                entityId: _legacyBridge.entityIdFor(_userId),
                receivedAt: DateTime.now(),
                rawPayload:
                    transaction.comment ?? transaction.description ?? '',
                transcript:
                    transaction.comment ?? transaction.description ?? '',
                transaction: _seedFromQesto(transaction),
                userCorrections: const {'confirmedInPreview': 'true'},
              ),
            )
          : _synoball.ingest(
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
            );
      createdIds.addAll(outcome.createdTransactionIds);
      // This command comes from a preview the user has already confirmed.
      // Keep the adapter's safe pending default for unconfirmed speech.
      if (confirmedVoiceInput && receipt == null) {
        for (final candidateId in outcome.pendingCandidateIds) {
          createdIds.add(
            _synoball.confirmCandidate(candidateId, actorId: _userId),
          );
        }
      }
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

  String? rememberedStatementAccount(String sourceKey) => _synoball
      .sourceAccountMapping(_legacyBridge.entityIdFor(_userId), sourceKey);

  Future<int> importStatement({
    required QestoAccount account,
    required Iterable<BudgetTransaction> transactions,
    required Set<String> createdPeriodIds,
    required String actionTitle,
    String? rawPayload,
    Map<String, int> exactMinorById = const {},
    Map<String, String> providerTransactionIdsByTransactionId = const {},
    Map<String, String> externalAccountIdsById = const {},
    List<QestoAccount> additionalAccounts = const [],
    bool bankWebSource = false,
    String? connectionId,
    String? institutionId,
    String? confirmedSourceAccountKey,
    void Function(IngestionOutcome)? onIngestion,
  }) async {
    _checkWrite();
    if (confirmedSourceAccountKey != null) {
      final linked = rememberedStatementAccount(confirmedSourceAccountKey);
      if (linked != null && linked != account.id) {
        throw StateError(
          'Statement account is already linked to another account',
        );
      }
    }
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
    // Stage the entire source replay in isolation: account updates and identity
    // commands must not partially mutate the live ledger if validation throws.
    final stagedCore = SynoballCore(initialState: _synoball.state);
    SynoballAccount sourceAccount(QestoAccount value) {
      final fresh = _legacyBridge.accountFromQesto(value);
      final previous = stagedCore.state.accounts
          .where((a) => a.id == value.id)
          .firstOrNull;
      return SynoballAccount(
        id: fresh.id,
        entityId: fresh.entityId,
        name: fresh.name,
        type: fresh.type,
        currency: fresh.currency,
        balance: fresh.balance,
        isVirtual: previous?.isVirtual ?? fresh.isVirtual,
        connectionId:
            previous?.connectionId ??
            (bankWebSource && !fresh.isVirtual ? connectionId : null),
        institutionId: previous?.institutionId ?? institutionId,
        externalId: previous?.externalId ?? externalAccountIdsById[value.id],
      );
    }

    final synoballAccount = sourceAccount(account);
    for (final additional in importedAccounts.values.where(
      (item) => item.id != account.id,
    )) {
      stagedCore.upsertAccount(sourceAccount(additional));
    }
    final SynoballAdapter<StatementInput> adapter = bankWebSource
        ? BankWebAdapter()
        : StatementAdapter();
    final outcome = stagedCore.ingest(
      adapter,
      StatementInput(
        entityId: entityId,
        connectionId: connectionId,
        institutionId: institutionId,
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
                providerTransactionId:
                    providerTransactionIdsByTransactionId[item.id] ?? item.id,
              ),
            )
            .toList(growable: false),
        account: synoballAccount,
      ),
    );
    if (confirmedSourceAccountKey != null) {
      stagedCore.linkSourceAccount(
        entityId: entityId,
        sourceKey: confirmedSourceAccountKey,
        accountId: account.id,
        actorId: _userId,
      );
    }
    _checkWrite();
    _synoball = stagedCore;
    // Source refresh is reconciled by Synoball. Never write a rounded UI
    // projection back as if the user had edited every field.
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
        outcome.pendingCandidateIds.isEmpty &&
        outcome.failedCandidateIds.isEmpty &&
        outcome.suppressedTransactionIds.isEmpty &&
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
    onIngestion?.call(outcome);
    return outcome.createdTransactionIds.length;
  }

  /// Imports facts produced by the local read-only Sber connector through the
  /// Synoball bank-web adapter. The connector never writes raw HTML or banking
  /// credentials into this payload.
  Future<SberImportSummary> importSberSnapshot(
    SberSyncSnapshot snapshot, {
    int? expectedGeneration,
  }) async {
    _checkWrite(expectedGeneration);
    final accountsBeforeImport = List<QestoAccount>.of(accounts);
    final accountReconciliation = _reconcileSberAccounts(
      snapshot.accounts,
      connectionId: snapshot.connectionId,
    );
    final importedAccountsById = <String, QestoAccount>{};
    for (final value in snapshot.accounts) {
      final canonicalId = accountReconciliation.sourceToCanonical[value.id]!;
      final linkedCards = value.linkedCardLastFours
          .map((suffix) => '•• $suffix')
          .join(', ');
      final accountName =
          value.lastFour != null &&
              !_sberAccountSuffixes(value.name).contains(value.lastFour)
          ? '${value.name} •• ${value.lastFour}'
          : value.name;
      importedAccountsById[canonicalId] = QestoAccount(
        id: canonicalId,
        userId: _userId,
        title: linkedCards.isEmpty
            ? accountName
            : '$accountName · карта $linkedCards',
        balance: value.balance,
        exactBalanceMinor: value.balanceMinor,
        currency: value.currency,
        type: value.type,
      );
    }
    final importedAccounts = importedAccountsById.values.toList(
      growable: false,
    );
    final availableAccounts = <String, QestoAccount>{
      for (final account in accounts) account.id: account,
      ...importedAccountsById,
    };
    final unassignedAccounts = <String, QestoAccount>{};
    String resolveAccount(
      SberTransactionFact value,
      BudgetTransaction? previous,
    ) {
      final mapped =
          accountReconciliation.sourceToCanonical[value.accountId] ??
          value.accountId;
      final known = availableAccounts[mapped];
      if (known != null &&
          known.currency == value.currency &&
          known.id.startsWith('sber-account-')) {
        return known.id;
      }
      // Product discovery can fail independently of history extraction. Resolve
      // retained provider identifiers only within the same connection scope.
      final retained = synoballState.accounts
          .where(
            (account) =>
                value.accountId.isNotEmpty &&
                snapshot.connectionId != null &&
                account.connectionId == snapshot.connectionId &&
                account.institutionId == 'sberbank' &&
                account.externalId == value.accountId &&
                account.currency == value.currency &&
                !account.isVirtual &&
                availableAccounts.containsKey(account.id),
          )
          .toList();
      if (retained.length == 1) return retained.single.id;
      // A temporarily absent account reference must not move a known operation
      // to another account. Conflicting explicit references remain unresolved.
      final old = availableAccounts[previous?.accountId];
      if (value.accountId.isEmpty &&
          old != null &&
          old.currency == value.currency &&
          old.id.startsWith('sber-account-')) {
        return old.id;
      }
      final defaultAccount = availableAccounts['local-default-account'];
      if (defaultAccount != null && defaultAccount.currency == value.currency) {
        return defaultAccount.id;
      }
      final id = 'sber-unassigned-${value.currency}';
      unassignedAccounts.putIfAbsent(
        id,
        () => QestoAccount(
          id: id,
          userId: _userId,
          title: 'Сбер · счёт не определён, остаток неизвестен',
          balance: 0,
          currency: value.currency,
          type: AccountType.other,
        ),
      );
      return id;
    }

    final existingById = {for (final item in _transactions) item.id: item};
    final proposedIds = {
      for (final value in snapshot.transactions)
        value.fingerprint: snapshot.connectionId == null
            ? 'sber-${value.fingerprint}'
            : sourceIdentity('sber-operation-v2', [
                snapshot.connectionId,
                value.sourceId.isEmpty ? value.fingerprint : value.sourceId,
              ]),
    };
    final compatibleExistingIdByProposedId = <String, String>{};
    for (final value in snapshot.transactions) {
      final legacy = existingById['sber-${value.fingerprint}'];
      if (legacy == null) continue;
      final profiles = legacy.tags.where((t) => t.startsWith('sber-profile:'));
      if (profiles.isEmpty ||
          profiles.contains('sber-profile:${snapshot.connectionId}')) {
        compatibleExistingIdByProposedId[proposedIds[value.fingerprint]!] =
            legacy.id;
      }
    }
    final exactMatchedIds = proposedIds.values
        .where(existingById.containsKey)
        .followedBy(compatibleExistingIdByProposedId.values)
        .toSet();
    final unmatchedIncomingBySignature = <String, List<SberTransactionFact>>{};
    for (final value in snapshot.transactions) {
      final proposedId = proposedIds[value.fingerprint]!;
      if (existingById.containsKey(proposedId) ||
          compatibleExistingIdByProposedId.containsKey(proposedId)) {
        continue;
      }
      unmatchedIncomingBySignature
          .putIfAbsent(_sberFactIdentity(value), () => <SberTransactionFact>[])
          .add(value);
    }
    final unmatchedExistingBySignature = <String, List<BudgetTransaction>>{};
    for (final value in existingById.values.where(
      (item) =>
          item.tags.contains('sber-live') &&
          !item.tags.contains('sber-identity:v2') &&
          !exactMatchedIds.contains(item.id),
    )) {
      final sourceEvidence = synoballState.evidence
          .where(
            (e) =>
                e.transactionId == value.id &&
                e.sourceType == SynoballSourceType.bankWeb,
          )
          .toList();
      final sourceFacts = synoballState.candidates
          .where(
            (c) =>
                (c.status == CandidateStatus.confirmed ||
                    c.status == CandidateStatus.merged) &&
                sourceEvidence.any(
                  (e) =>
                      e.ingestionRecordId == c.ingestionRecordId &&
                      e.providerTransactionId == c.providerTransactionId,
                ),
          )
          .toList();
      final signatures = sourceFacts.isEmpty
          ? {_storedSberIdentity(value)}
          : sourceFacts.map(_candidateSberIdentity).toSet();
      for (final signature in signatures) {
        unmatchedExistingBySignature
            .putIfAbsent(signature, () => <BudgetTransaction>[])
            .add(value);
      }
    }
    for (final entry in unmatchedIncomingBySignature.entries) {
      final oldMatches = unmatchedExistingBySignature[entry.key];
      // Provider IDs introduced by a connector upgrade can replace an old
      // ordinal-based ID only for an unambiguous one-to-one economic fact.
      // Repeated equal payments must remain separate.
      if (entry.value.length != 1 || oldMatches?.length != 1) continue;
      final incoming = entry.value.single;
      final previousProfiles = oldMatches!.single.tags.where(
        (t) => t.startsWith('sber-profile:'),
      );
      if (previousProfiles.isNotEmpty &&
          !previousProfiles.contains('sber-profile:${snapshot.connectionId}')) {
        continue;
      }
      final oldAccount = oldMatches.single.accountId;
      final incomingAccount =
          accountReconciliation.sourceToCanonical[incoming.accountId] ??
          incoming.accountId;
      // A signature is not proof across two known accounts.
      if (incomingAccount.isNotEmpty &&
          oldAccount.startsWith('sber-account-') &&
          incomingAccount != oldAccount) {
        continue;
      }
      compatibleExistingIdByProposedId[proposedIds[incoming.fingerprint]!] =
          oldMatches.single.id;
    }
    final providerTransactionIdsByTransactionId = <String, String>{};
    final importedTransactions = snapshot.transactions
        .map((value) {
          final providerId = proposedIds[value.fingerprint]!;
          final id = compatibleExistingIdByProposedId[providerId] ?? providerId;
          // DOM labels, balances and status may change between observations.
          // The bank's operation ID must survive these presentation changes.
          providerTransactionIdsByTransactionId[id] =
              value.sourceId.isNotEmpty && value.sourceId != value.fingerprint
              ? sourceIdentity('sber-provider-v1', [
                  snapshot.connectionId,
                  value.sourceId,
                ])
              : providerId;
          final existing = existingById[id];
          final resolvedAccountId = resolveAccount(value, existing);
          final manualCategory =
              existing?.tags.contains(qestoManualCategoryTag) == true;
          final automaticCategory = value.isIncome
              ? const ResolvedTransactionCategory(
                  categoryId: 'business',
                  confidence: 0.95,
                )
              : _sberCategory(value);
          final type = value.status == 'REFUND'
              ? TransactionType.refund
              : value.isIncome
              ? TransactionType.income
              : value.isInternalTransfer
              ? TransactionType.transfer
              : TransactionType.expense;
          final tags = <String>{
            'sberbank',
            'sber-live',
            'sber-identity:v2',
            if (snapshot.connectionId != null)
              'sber-profile:${snapshot.connectionId}',
            'sber-classification:v2',
            if (resolvedAccountId == 'local-default-account' ||
                resolvedAccountId.startsWith('sber-unassigned-'))
              'sber-account-unresolved',
            'sber-status-${value.status.toLowerCase()}',
            if (value.isTransfer && value.isInternalTransfer)
              qestoInternalTransferTag,
            if (value.isTransfer && !value.isInternalTransfer)
              qestoExternalTransferTag,
            if (value.loyaltyReward != null) qestoLoyaltyMetadataTag,
            if (manualCategory)
              qestoManualCategoryTag
            else
              qestoAutoCategoryTag,
          };
          return BudgetTransaction(
            id: id,
            userId: _userId,
            accountId: resolvedAccountId,
            date: value.date,
            amount: value.amount,
            exactAmountMinor: value.amountMinor,
            currency: value.currency,
            type: type,
            categoryId: manualCategory
                ? existing!.categoryId
                : automaticCategory.categoryId,
            subcategoryId: manualCategory
                ? existing!.subcategoryId
                : automaticCategory.subcategoryId,
            merchant: value.merchant,
            title: value.merchant ?? value.description,
            description: value.description,
            comment: 'СберБанк Онлайн · ${value.status}',
            normalizedMerchant: value.merchant?.toLowerCase(),
            isConfirmed: value.status == 'POSTED' || value.status == 'REFUND',
            isPotentialDuplicate: false,
            classificationConfidence: manualCategory
                ? existing!.classificationConfidence
                : automaticCategory.confidence,
            originalCategoryId: value.category,
            transferDirection: value.isTransfer
                ? value.isIncome
                      ? TransferDirection.incoming
                      : TransferDirection.outgoing
                : null,
            tags: tags.toList(growable: false),
          );
        })
        .toList(growable: false);
    final accountsUpdated = importedAccounts.where((incoming) {
      final index = accountsBeforeImport.indexWhere(
        (item) => item.id == incoming.id,
      );
      // A first observation is also a balance update from the user's point
      // of view: the account did not exist in Qesto before this sync.
      return index < 0 || !_sameAccount(accountsBeforeImport[index], incoming);
    }).length;
    final accountItems = importedAccounts
        .map((incoming) {
          final index = accountsBeforeImport.indexWhere(
            (item) => item.id == incoming.id,
          );
          final change = index < 0
              ? SberImportChange.created
              : !_sameAccount(accountsBeforeImport[index], incoming)
              ? SberImportChange.updated
              : SberImportChange.unchanged;
          return SberAccountImportItem(
            title: incoming.title,
            balance: incoming.balance,
            currency: incoming.currency,
            change: change,
          );
        })
        .toList(growable: false);
    if (importedTransactions.isEmpty && importedAccounts.isEmpty) {
      return const SberImportSummary(
        found: 0,
        newCount: 0,
        updatedCount: 0,
        unchangedCount: 0,
        accountsFound: 0,
        accountsUpdated: 0,
      );
    }
    bool transactionChanged(
      BudgetTransaction existing,
      BudgetTransaction incoming,
    ) {
      return existing.amountMinor != incoming.amountMinor ||
          existing.accountId != incoming.accountId ||
          existing.currency != incoming.currency ||
          existing.date != incoming.date ||
          existing.type != incoming.type ||
          existing.categoryId != incoming.categoryId ||
          existing.subcategoryId != incoming.subcategoryId ||
          existing.title != incoming.title ||
          existing.merchant != incoming.merchant ||
          existing.description != incoming.description ||
          existing.transferDirection != incoming.transferDirection ||
          !_sameStringSet(existing.tags, incoming.tags) ||
          existing.isConfirmed != incoming.isConfirmed;
    }

    final periods = <String>{};
    for (final transaction in importedTransactions) {
      periods.add(periodForOrCreate(transaction.date).id);
    }
    final accountsToWrite = <QestoAccount>[
      ...importedAccounts,
      ...unassignedAccounts.values,
    ];
    final primaryAccount = accountsToWrite.isNotEmpty
        ? accountsToWrite.first
        : accounts.first;
    IngestionOutcome? ingestion;
    final created = await importStatement(
      account: primaryAccount,
      additionalAccounts: accountsToWrite.skip(1).toList(growable: false),
      transactions: importedTransactions,
      createdPeriodIds: periods,
      actionTitle: 'Синхронизация Сбера',
      rawPayload: jsonEncode({
        'source': 'sber-cef-read-only',
        'observedAt': snapshot.observedAt.toIso8601String(),
        'transactionIds': importedTransactions.map((item) => item.id).toList(),
      }),
      providerTransactionIdsByTransactionId:
          providerTransactionIdsByTransactionId,
      bankWebSource: true,
      connectionId: snapshot.connectionId,
      institutionId: 'sberbank',
      externalAccountIdsById: {
        for (final value in snapshot.accounts)
          accountReconciliation.sourceToCanonical[value.id]!: value.id,
      },
      onIngestion: (value) => ingestion = value,
    );
    var accountsMerged = 0;
    _checkWrite(expectedGeneration);
    for (final entry in accountReconciliation.duplicateToPrimary.entries) {
      if (entry.key == entry.value) continue;
      final duplicateExists = _synoball.state.accounts.any(
        (item) => item.id == entry.key,
      );
      final primaryExists = _synoball.state.accounts.any(
        (item) => item.id == entry.value,
      );
      if (!duplicateExists || !primaryExists) continue;
      _synoball.mergeAccountInto(
        duplicateAccountId: entry.key,
        primaryAccountId: entry.value,
        actorId: _userId,
        purpose:
            'Reconcile duplicate Sber account/card observations after sync',
      );
      accountsMerged += 1;
    }
    if (accountsMerged > 0) {
      _syncFromSynoball();
      await _changed();
    }
    // Report accepted, persisted canonical rows, not the adapter's proposed
    // IDs/values. In particular, fuzzy matches and protected user edits may
    // result in a different target or no visible change at all.
    final afterById = {for (final item in _transactions) item.id: item};
    final createdIds = ingestion?.createdTransactionIds.toSet() ?? <String>{};
    final suppressedIds =
        ingestion?.suppressedTransactionIds.toSet() ?? <String>{};
    final resolvedIds = ingestion?.resolvedTransactionIds ?? const <String?>[];
    final reported = <String>{};
    var recategorizedCount = 0;
    final transactionItems = <SberTransactionImportItem>[];
    for (var index = 0; index < importedTransactions.length; index++) {
      final incoming = importedTransactions[index];
      final targetId = index < resolvedIds.length ? resolvedIds[index] : null;
      final saved = afterById[targetId];
      final previous = existingById[targetId];
      var change = suppressedIds.contains(targetId)
          ? SberImportChange.deleted
          : SberImportChange.needsReview;
      if (saved != null) {
        if (!reported.add(saved.id)) {
          change = SberImportChange.unchanged;
        } else if (createdIds.contains(saved.id)) {
          change = SberImportChange.created;
        } else {
          change = previous != null && transactionChanged(previous, saved)
              ? SberImportChange.updated
              : SberImportChange.unchanged;
          if (previous != null && previous.categoryId != saved.categoryId) {
            recategorizedCount += 1;
          }
        }
      }
      final display = saved ?? incoming;
      transactionItems.add(
        SberTransactionImportItem(
          title: display.title ?? display.description ?? 'Операция Сбера',
          date: display.date,
          amount: display.amount,
          currency: display.currency,
          isIncome:
              display.type == TransactionType.income ||
              display.type == TransactionType.refund,
          isTransfer: display.type == TransactionType.transfer,
          change: change,
        ),
      );
    }
    int count(SberImportChange change) =>
        transactionItems.where((item) => item.change == change).length;
    return SberImportSummary(
      found: importedTransactions.length,
      newCount: created,
      updatedCount: count(SberImportChange.updated),
      unresolvedCount: count(SberImportChange.needsReview),
      deletedCount: count(SberImportChange.deleted),
      unassignedAccountCount: reported
          .where(
            (id) =>
                afterById[id]?.tags.contains('sber-account-unresolved') == true,
          )
          .length,
      unchangedCount: count(SberImportChange.unchanged),
      accountsFound: importedAccounts.length,
      accountsUpdated: accountsUpdated,
      accountsMerged: accountsMerged,
      accounts: accountItems,
      transactions: transactionItems,
      recategorizedCount: recategorizedCount,
    );
  }

  _SberAccountReconciliation _reconcileSberAccounts(
    List<SberAccountFact> facts, {
    String? connectionId,
  }) {
    final metadata = {for (final a in synoballState.accounts) a.id: a};
    final sourceToCanonical = <String, String>{};
    final duplicateToPrimary = <String, String>{};
    final alreadyAssigned = <String>{};
    for (final fact in facts) {
      final eligible = accounts
          .where(
            (account) =>
                account.id.startsWith('sber-account-') &&
                (metadata[account.id]?.connectionId == null ||
                    metadata[account.id]?.connectionId == connectionId) &&
                account.currency == fact.currency &&
                _sberAccountTypesCompatible(account.type, fact.type),
          )
          .toList(growable: false);
      final exact = eligible
          .where(
            (account) =>
                account.id == fact.id ||
                (metadata[account.id]?.connectionId == connectionId &&
                    metadata[account.id]?.externalId == fact.id),
          )
          .toList();
      final suffixes = <String>{
        if (fact.lastFour != null) fact.lastFour!,
        ...fact.linkedCardLastFours,
      };
      final suffixMatches = suffixes.isEmpty
          ? const <QestoAccount>[]
          : eligible
                .where(
                  (account) => _sberAccountSuffixes(
                    account.title,
                  ).intersection(suffixes).isNotEmpty,
                )
                .toList(growable: false);
      // A last-four collision or equal name is not account ownership evidence.
      // Only a bank-observed card -> account relationship may bridge old IDs.
      final linkedMatches = suffixMatches
          .where(
            (account) =>
                fact.linkedCardLastFours.isNotEmpty &&
                RegExp(r'карт', caseSensitive: false).hasMatch(account.title) &&
                _sberAccountSuffixes(
                  account.title,
                ).intersection(fact.linkedCardLastFours.toSet()).isNotEmpty &&
                !facts.any(
                  (other) =>
                      other.id != fact.id &&
                      other.linkedCardLastFours
                          .toSet()
                          .intersection(fact.linkedCardLastFours.toSet())
                          .isNotEmpty,
                ),
          )
          .toList(growable: false);
      final candidates = exact.isNotEmpty ? exact : linkedMatches;
      final unassigned = candidates
          .where((account) => !alreadyAssigned.contains(account.id))
          .toList(growable: false);
      final primary = _mostUsedSberAccount(unassigned);
      final canonicalId =
          primary?.id ??
          (connectionId == null
              ? fact.id
              : sourceIdentity('sber-account-v2', [connectionId, fact.id]));
      sourceToCanonical[fact.id] = canonicalId;
      for (final alias in fact.sourceAliases) {
        // Ambiguous aliases must not be resolved by list order.
        if (facts
                .where(
                  (other) =>
                      other.id == alias || other.sourceAliases.contains(alias),
                )
                .length ==
            1) {
          sourceToCanonical[alias] = canonicalId;
        }
      }
      alreadyAssigned.add(canonicalId);

      // Only suffix-linked accounts are safe to merge automatically. Equal
      // display names alone are insufficient because a user may own several
      // savings accounts with the same provider label.
      for (final duplicate in linkedMatches) {
        if (duplicate.id != canonicalId) {
          duplicateToPrimary[duplicate.id] = canonicalId;
        }
      }
    }
    return _SberAccountReconciliation(
      sourceToCanonical: sourceToCanonical,
      duplicateToPrimary: duplicateToPrimary,
    );
  }

  QestoAccount? _mostUsedSberAccount(List<QestoAccount> candidates) {
    if (candidates.isEmpty) return null;
    final sorted = List<QestoAccount>.of(candidates)
      ..sort((left, right) {
        final leftUses = _transactions
            .where((item) => item.accountId == left.id)
            .length;
        final rightUses = _transactions
            .where((item) => item.accountId == right.id)
            .length;
        final byUses = rightUses.compareTo(leftUses);
        return byUses != 0 ? byUses : left.id.compareTo(right.id);
      });
    return sorted.first;
  }

  static Set<String> _sberAccountSuffixes(String value) => RegExp(
    r'(?:\*{2,}|x{2,}|•{2,})\s*(\d{4})',
    caseSensitive: false,
  ).allMatches(value).map((match) => match.group(1)!).toSet();

  static bool _sberAccountTypesCompatible(
    AccountType existing,
    AccountType incoming,
  ) {
    if (existing == incoming) return true;
    const paymentTypes = {
      AccountType.bankCard,
      AccountType.cash,
      AccountType.other,
    };
    return paymentTypes.contains(existing) && paymentTypes.contains(incoming);
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
    _checkWrite();
    return addNotificationTransaction(
      period: period,
      amountMinor: amountMinor,
      currency: period.currency,
      date: date,
      type: TransactionType.expense,
      categoryId: categoryId,
      accountId: accountId,
      title: title,
      notificationKey: notificationKey,
      packageName: packageName,
      rawNotification: rawNotification,
      subcategoryId: subcategoryId,
      confidence: confidence,
    );
  }

  Future<IngestionOutcome> addNotificationTransaction({
    required BudgetPeriod period,
    required int amountMinor,
    required String currency,
    required DateTime date,
    required TransactionType type,
    required String categoryId,
    required String accountId,
    required String title,
    required String notificationKey,
    required String packageName,
    required String rawNotification,
    String? sender,
    String? subcategoryId,
    bool isSmsNotification = false,
    double confidence = 0.8,
  }) async {
    final direction = switch (type) {
      TransactionType.income ||
      TransactionType.refund => FinancialDirection.inflow,
      TransactionType.transfer => FinancialDirection.outflow,
      _ => FinancialDirection.outflow,
    };
    final transferDirection = type == TransactionType.transfer
        ? TransferDirection.outgoing.name
        : null;
    final seed = TransactionSeed(
      accountId: accountId,
      amount: Money(minorUnits: amountMinor.abs(), currency: currency),
      direction: direction,
      occurredAt: date,
      description: rawNotification,
      merchant: title,
      category: categoryId,
      subcategoryId: subcategoryId,
      providerTransactionId: notificationKey,
      transferDirection: transferDirection,
      tags: [
        'legacy-type-${type.name}',
        if (type == TransactionType.refund) 'refund',
        if (type == TransactionType.transfer) qestoExternalTransferTag,
        if (isSmsNotification) 'sms-notification' else 'android-notification',
      ],
      confidence: confidence,
    );
    final outcome = isSmsNotification
        ? _synoball.ingest(
            SmsNotificationAdapter(history: synoballState),
            SmsNotificationInput(
              entityId: _legacyBridge.entityIdFor(_userId),
              receivedAt: DateTime.now(),
              rawPayload: rawNotification,
              notificationKey: notificationKey,
              packageName: packageName,
              sender: sender ?? '',
              transaction: seed,
            ),
          )
        : _synoball.ingest(
            AndroidNotificationAdapter(history: synoballState),
            AndroidNotificationInput(
              entityId: _legacyBridge.entityIdFor(_userId),
              receivedAt: DateTime.now(),
              rawPayload: rawNotification,
              notificationKey: notificationKey,
              packageName: packageName,
              transaction: seed,
            ),
          );
    _syncFromSynoball();
    if (outcome.createdTransactionIds.isNotEmpty) {
      _addAction(
        FinancialAction(
          id: 'action-${DateTime.now().microsecondsSinceEpoch}',
          occurredAt: DateTime.now(),
          title: 'Добавлена операция «$title»',
          type: FinancialActionType.transactionAdded,
          createdTransactionIds: outcome.createdTransactionIds,
        ),
      );
    }
    await _changed();
    return outcome;
  }

  /// Resolves only an explicitly reviewed notification-slot revision.
  /// Retrying persistence after a failed save does not confirm a second time.
  Future<CanonicalTransaction> confirmNotificationRevision(
    String candidateId,
  ) async {
    _checkWrite();
    final state = synoballState;
    final candidate = state.candidates.firstWhere((c) => c.id == candidateId);
    final record = state.ingestionRecords.firstWhere(
      (r) => r.id == candidate.ingestionRecordId,
    );
    if (!candidate.tags.contains(notificationIdentityReviewTag) ||
        (record.sourceType != SynoballSourceType.androidNotification &&
            record.sourceType != SynoballSourceType.smsNotification)) {
      throw StateError('Not a notification identity review');
    }
    final String transactionId;
    if (candidate.status == CandidateStatus.pending) {
      transactionId = _synoball.confirmCandidate(candidateId, actorId: _userId);
    } else {
      final targets = state.evidence
          .where(
            (e) =>
                e.ingestionRecordId == record.id &&
                e.providerTransactionId == candidate.providerTransactionId,
          )
          .map((e) => e.transactionId)
          .toSet();
      if (targets.length != 1) {
        throw StateError('Unresolved notification identity');
      }
      transactionId = targets.single;
    }
    _syncFromSynoball();
    await _changed();
    return _synoball.transactionById(transactionId)!;
  }

  Future<IngestionOutcome> importBankScreenshotCandidates(
    Iterable<BankScreenshotCandidate> values,
  ) async {
    _checkWrite();
    final candidates = values
        .where((candidate) => candidate.selected && candidate.accountId != null)
        .toList(growable: false);
    if (candidates.isEmpty) {
      return const IngestionOutcome(
        ingestionRecordId: '',
        createdTransactionIds: [],
        matchedTransactionIds: [],
        pendingCandidateIds: [],
      );
    }
    for (final candidate in candidates) {
      periodForOrCreate(candidate.date);
    }
    final seeds = candidates
        .map((candidate) {
          final type = candidate.transactionType;
          final direction =
              type == TransactionType.income || type == TransactionType.refund
              ? FinancialDirection.inflow
              : FinancialDirection.outflow;
          return TransactionSeed(
            canonicalId: resolveScreenshotIdentity(
              candidate,
              synoballState,
            ).canonicalId,
            accountId: candidate.accountId!,
            amount: Money(
              minorUnits: candidate.amountMinor.abs(),
              currency: candidate.currency,
            ),
            direction: direction,
            occurredAt: candidate.date,
            description: candidate.merchant,
            merchant: candidate.merchant,
            category: candidate.categoryId,
            providerTransactionId: candidate.id,
            transferDirection: type == TransactionType.transfer
                ? TransferDirection.outgoing.name
                : null,
            tags: [
              'legacy-type-${type.name}',
              'bank-screenshot',
              'bank-screenshot-parser:${candidate.parserId}',
              if (candidate.legacyProviderId != null)
                'bank-screenshot-image:${candidate.imageHash}',
              if (candidate.dateOnly) 'date-precision:day',
              if (type == TransactionType.transfer) qestoExternalTransferTag,
              if (type == TransactionType.refund) 'refund',
            ],
            confidence: candidate.confidence,
          );
        })
        .toList(growable: false);
    final outcome = _synoball.ingest(
      BankScreenshotAdapter(),
      BankScreenshotInput(
        entityId: _legacyBridge.entityIdFor(_userId),
        receivedAt: DateTime.now(),
        rawPayload: '{"redacted":true}',
        batchName: 'Импорт скриншотов банка',
        transactions: seeds,
        imageHashes: candidates
            .map((candidate) => candidate.imageHash)
            .toSet()
            .toList(growable: false),
        parserIds: candidates
            .map((candidate) => candidate.parserId)
            .toSet()
            .toList(growable: false),
        institutionId:
            candidates.every(
              (candidate) => candidate.parserId.startsWith('sber'),
            )
            ? 'sberbank'
            : null,
      ),
    );
    _syncFromSynoball();
    if (outcome.createdTransactionIds.isNotEmpty) {
      _addAction(
        FinancialAction(
          id: 'action-${DateTime.now().microsecondsSinceEpoch}',
          occurredAt: DateTime.now(),
          title: 'Импорт скриншотов банка',
          type: FinancialActionType.statementImport,
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
      if (canonical != null &&
          canonical.status != CanonicalTransactionStatus.deleted) {
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
      left.balanceMinor == right.balanceMinor &&
      left.currency == right.currency &&
      left.type == right.type;

  Future<void> updateTransaction(BudgetTransaction transaction) async {
    final canonical = _synoball.transactionById(transaction.id);
    if (canonical == null) return;
    final categoryChanged =
        transaction.categoryId != canonical.effectiveCategory;
    final updated = categoryChanged
        ? transaction.copyWith(
            tags: {
              ...transaction.tags.where((tag) => tag != qestoAutoCategoryTag),
              qestoManualCategoryTag,
            }.toList(),
          )
        : transaction;
    _synoball.updateTransaction(
      _legacyBridge.canonicalFromQesto(updated, previous: canonical),
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
      final categoryChanged =
          transaction.categoryId != canonical.effectiveCategory;
      final updated = categoryChanged
          ? transaction.copyWith(
              tags: {
                ...transaction.tags.where((tag) => tag != qestoAutoCategoryTag),
                qestoManualCategoryTag,
              }.toList(),
            )
          : transaction;
      _synoball.updateTransaction(
        _legacyBridge.canonicalFromQesto(updated, previous: canonical),
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
    _checkWrite();
    if (!hasTransaction(id)) return;
    _synoball.deleteTransaction(id, actorId: _userId);
    _syncFromSynoball();
    await _changed();
  }

  Future<int> restoreTrashedTransactions(Iterable<String> ids) async {
    _checkWrite();
    var restored = 0;
    for (final id in ids.toSet()) {
      if (_synoball.restoreDeletedTransaction(id, actorId: _userId)) restored++;
    }
    _syncFromSynoball();
    // Persist even an idempotent retry after a failed save.
    await _changed();
    return restored;
  }

  /// Clears user financial content while retaining only the minimum local
  /// profile/account scaffold required for the UI to remain operational.
  Future<void> clearAllFinancialData() async {
    _dataGeneration++;
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
    accountPreferences.clear();
    _categoryCustomizations.clear();
    categories
      ..clear()
      ..addAll(_baseCategories);
    plannedCumulativePoints.clear();
    savingsGoals.clear();
    goalAllocations.clear();
    goalContributions.clear();
    goalHistoryEvents.clear();
    investmentAccounts.clear();
    investmentBalanceSnapshots.clear();
    investmentContributions.clear();
    debts.clear();
    debtBalanceSnapshots.clear();
    debtPayments.clear();
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

  Future<void> updateExpenseDisplayCurrency(String currency) async {
    final cleaned = currency.trim().toUpperCase();
    if (!const {'RUB', 'USD', 'EUR', 'CNY'}.contains(cleaned)) return;
    if (user.expenseDisplayCurrency == cleaned) return;
    user = user.copyWith(expenseDisplayCurrency: cleaned);
    await _changed();
  }

  Future<SavingsGoal?> addSavingsGoal({
    required String title,
    required String category,
    required int targetAmount,
    DateTime? targetDate,
    int savedAmount = 0,
    String? currency,
    int? desiredMonthlyContribution,
    GoalPriority priority = GoalPriority.medium,
    GoalStatus status = GoalStatus.active,
    GoalReminder? reminder,
    String iconKey = 'flag',
    GoalType type = GoalType.targetAmount,
    String? comment,
    int? colorValue,
  }) async {
    final cleanedTitle = title.trim();
    if (cleanedTitle.isEmpty ||
        targetAmount < 0 ||
        (type != GoalType.recurringSaving && targetAmount <= 0) ||
        (type == GoalType.recurringSaving &&
            targetAmount == 0 &&
            (desiredMonthlyContribution ?? 0) <= 0)) {
      return null;
    }
    final normalizedSaved = math.max(0, savedAmount);
    final resolvedStatus = targetAmount > 0 && normalizedSaved >= targetAmount
        ? GoalStatus.funded
        : status;
    final now = DateTime.now();
    final goal = SavingsGoal(
      id: 'goal-${now.microsecondsSinceEpoch}',
      userId: _userId,
      title: cleanedTitle,
      targetAmount: targetAmount,
      savedAmount: normalizedSaved,
      currency: currency ?? user.defaultCurrency,
      streakWeeks: 0,
      isActive: resolvedStatus == GoalStatus.active,
      history: normalizedSaved <= 0
          ? const []
          : [SavingsHistoryPoint(date: referenceDate, amount: normalizedSaved)],
      category: category.trim().isEmpty ? 'Другое' : category.trim(),
      type: type,
      targetDate: targetDate,
      desiredMonthlyContribution: desiredMonthlyContribution,
      priority: priority,
      status: resolvedStatus,
      reminder: reminder,
      iconKey: iconKey,
      comment: comment?.trim().isEmpty == true ? null : comment?.trim(),
      colorValue: colorValue,
      createdAt: now,
      fundedAt: resolvedStatus == GoalStatus.funded ? now : null,
    );
    savingsGoals.add(goal);
    goalHistoryEvents.add(
      GoalHistoryEvent(
        id: 'goal-event-${now.microsecondsSinceEpoch}',
        goalId: goal.id,
        type: GoalHistoryEventType.created,
        date: now,
        description: 'Цель создана',
        amount: targetAmount > 0 ? targetAmount : null,
      ),
    );
    _clearExternalData = false;
    await _changed();
    return goal;
  }

  Future<void> updateSavingsGoal(SavingsGoal goal) async {
    final index = savingsGoals.indexWhere((item) => item.id == goal.id);
    if (index < 0 ||
        goal.title.trim().isEmpty ||
        goal.targetAmount < 0 ||
        (goal.type != GoalType.recurringSaving && goal.targetAmount <= 0)) {
      return;
    }
    final previous = savingsGoals[index];
    final normalizedSaved = math.max(0, goal.savedAmount);
    final history = List<SavingsHistoryPoint>.of(previous.history);
    if (previous.savedAmount != normalizedSaved) {
      history.removeWhere(
        (item) =>
            item.date.year == referenceDate.year &&
            item.date.month == referenceDate.month &&
            item.date.day == referenceDate.day,
      );
      history.add(
        SavingsHistoryPoint(date: referenceDate, amount: normalizedSaved),
      );
      history.sort((left, right) => left.date.compareTo(right.date));
    }
    var resolvedStatus = goal.status;
    DateTime? fundedAt = goal.fundedAt;
    if (goal.type == GoalType.reserve &&
        goal.targetAmount > 0 &&
        normalizedSaved < goal.targetAmount &&
        resolvedStatus == GoalStatus.funded) {
      resolvedStatus = GoalStatus.active;
    } else if (goal.targetAmount > 0 &&
        normalizedSaved >= goal.targetAmount &&
        resolvedStatus == GoalStatus.active) {
      resolvedStatus = GoalStatus.funded;
      fundedAt ??= DateTime.now();
    }
    final now = DateTime.now();
    if (previous.targetAmount != goal.targetAmount) {
      goalHistoryEvents.add(
        GoalHistoryEvent(
          id: 'goal-event-target-${now.microsecondsSinceEpoch}',
          goalId: goal.id,
          type: GoalHistoryEventType.targetChanged,
          date: now,
          description: 'Целевая сумма изменена',
          amount: goal.targetAmount,
        ),
      );
    }
    if (previous.targetDate != goal.targetDate) {
      goalHistoryEvents.add(
        GoalHistoryEvent(
          id: 'goal-event-date-${now.microsecondsSinceEpoch}',
          goalId: goal.id,
          type: GoalHistoryEventType.targetDateChanged,
          date: now,
          description: 'Срок цели изменён',
        ),
      );
    }
    if (previous.status != resolvedStatus) {
      goalHistoryEvents.add(
        GoalHistoryEvent(
          id: 'goal-event-status-${now.microsecondsSinceEpoch}',
          goalId: goal.id,
          type: resolvedStatus == GoalStatus.completed
              ? GoalHistoryEventType.completed
              : resolvedStatus == GoalStatus.funded
              ? GoalHistoryEventType.funded
              : GoalHistoryEventType.statusChanged,
          date: now,
          description: 'Статус цели изменён',
        ),
      );
    }
    savingsGoals[index] = goal.copyWith(
      title: goal.title.trim(),
      savedAmount: normalizedSaved,
      history: history,
      status: resolvedStatus,
      isActive: resolvedStatus == GoalStatus.active,
      fundedAt: fundedAt,
      completedAt: resolvedStatus == GoalStatus.completed
          ? goal.completedAt ?? now
          : goal.completedAt,
    );
    await _changed();
  }

  Future<void> deleteSavingsGoal(String id) async {
    final index = savingsGoals.indexWhere((item) => item.id == id);
    if (index < 0) return;
    savingsGoals[index] = savingsGoals[index].copyWith(
      status: GoalStatus.archived,
      isActive: false,
    );
    await _changed();
  }

  Future<bool> upsertGoalAllocation(GoalAllocation allocation) async {
    if (allocation.allocatedAmount < 0 ||
        !savingsGoals.any((item) => item.id == allocation.goalId)) {
      return false;
    }
    final sourceBalance = _goalAllocationSourceBalance(allocation);
    if (sourceBalance == null) return false;
    final allocatedElsewhere = goalAllocations
        .where(
          (item) =>
              item.sourceType == allocation.sourceType &&
              item.sourceId == allocation.sourceId &&
              item.id != allocation.id,
        )
        .fold<int>(0, (sum, item) => sum + item.allocatedAmount);
    if (allocatedElsewhere + allocation.allocatedAmount > sourceBalance) {
      return false;
    }
    final index = goalAllocations.indexWhere(
      (item) => item.id == allocation.id,
    );
    if (index < 0) {
      goalAllocations.add(allocation);
    } else {
      goalAllocations[index] = allocation;
    }
    final now = DateTime.now();
    goalHistoryEvents.add(
      GoalHistoryEvent(
        id: 'goal-event-allocation-${now.microsecondsSinceEpoch}',
        goalId: allocation.goalId,
        type: GoalHistoryEventType.allocationChanged,
        date: now,
        description: 'Распределение средств изменено',
        amount: allocation.allocatedAmount,
      ),
    );
    await _changed();
    return true;
  }

  int? _goalAllocationSourceBalance(GoalAllocation allocation) {
    if (allocation.sourceType == GoalAllocationSourceType.manualAsset) {
      return allocation.allocatedAmount;
    }
    if (allocation.sourceType == GoalAllocationSourceType.account) {
      final account = accounts
          .where((item) => item.id == allocation.sourceId)
          .firstOrNull;
      if (account == null || account.currency != allocation.currency) {
        return null;
      }
      return math.max(0, account.balance);
    }
    final account = investmentAccounts
        .where((item) => item.id == allocation.sourceId)
        .firstOrNull;
    if (account == null || account.currency != allocation.currency) {
      return null;
    }
    return math.max(0, account.currentBalance);
  }

  Future<void> removeGoalAllocation(String id) async {
    final allocation = goalAllocations
        .where((item) => item.id == id)
        .firstOrNull;
    if (allocation == null) return;
    goalAllocations.removeWhere((item) => item.id == id);
    final now = DateTime.now();
    goalHistoryEvents.add(
      GoalHistoryEvent(
        id: 'goal-event-allocation-remove-${now.microsecondsSinceEpoch}',
        goalId: allocation.goalId,
        type: GoalHistoryEventType.allocationChanged,
        date: now,
        description: 'Распределение средств удалено',
      ),
    );
    await _changed();
  }

  Future<GoalContribution?> addGoalContribution({
    required String goalId,
    required int amount,
    required GoalContributionType type,
    required DateTime date,
    String? comment,
    String? transactionId,
    String? accountId,
    GoalContributionSource source = GoalContributionSource.manual,
  }) async {
    final index = savingsGoals.indexWhere((item) => item.id == goalId);
    if (index < 0 || amount <= 0) return null;
    final goal = savingsGoals[index];
    final now = DateTime.now();
    final contribution = GoalContribution(
      id: 'goal-contribution-${now.microsecondsSinceEpoch}',
      goalId: goalId,
      date: date,
      amount: amount,
      currency: goal.currency,
      type: type,
      source: source,
      createdAt: now,
      transactionId: transactionId,
      accountId: accountId,
      comment: comment?.trim().isEmpty == true ? null : comment?.trim(),
    );
    goalContributions.add(contribution);
    final nextAmount = type == GoalContributionType.contribution
        ? goal.savedAmount + amount
        : math.max(0, goal.savedAmount - amount);
    await updateSavingsGoal(goal.copyWith(savedAmount: nextAmount));
    return contribution;
  }

  Future<InvestmentAccount?> addInvestmentAccount({
    required String name,
    required int currentBalance,
    InvestmentAccountType type = InvestmentAccountType.brokerage,
    String? currency,
    String? brokerName,
    DateTime? openedAt,
    String? comment,
    bool includeInTotal = true,
    InvestmentPlan? plan,
  }) async {
    final cleanedName = name.trim();
    if (cleanedName.isEmpty || currentBalance < 0) return null;
    final now = DateTime.now();
    final id = 'investment-${now.microsecondsSinceEpoch}';
    final linkedAccountId = 'investment-account-${now.microsecondsSinceEpoch}';
    final resolvedCurrency = currency ?? user.defaultCurrency;
    final investment = InvestmentAccount(
      id: id,
      userId: _userId,
      linkedAccountId: linkedAccountId,
      name: cleanedName,
      brokerName: brokerName?.trim().isEmpty == true
          ? null
          : brokerName?.trim(),
      type: type,
      currency: resolvedCurrency,
      currentBalance: currentBalance,
      openedAt: openedAt,
      comment: comment?.trim().isEmpty == true ? null : comment?.trim(),
      includeInTotal: includeInTotal,
      status: InvestmentAccountStatus.active,
      source: InvestmentDataSource.manual,
      createdAt: now,
      updatedAt: now,
      lastBalanceUpdateAt: now,
      plan: plan,
    );
    _synoball.upsertAccount(
      SynoballAccount(
        id: linkedAccountId,
        entityId: _legacyBridge.entityIdFor(_userId),
        name: cleanedName,
        type:
            type == InvestmentAccountType.brokerage ||
                type == InvestmentAccountType.iis
            ? SynoballAccountType.brokerage
            : SynoballAccountType.investment,
        currency: resolvedCurrency,
        balance: Money(
          minorUnits: currentBalance * 100,
          currency: resolvedCurrency,
        ),
        externalId: id,
        isVirtual: true,
      ),
    );
    _syncFromSynoball();
    investmentAccounts.add(investment);
    _upsertInvestmentSnapshot(investment, currentBalance, now, now);
    _clearExternalData = false;
    await _changed();
    return investment;
  }

  Future<void> updateInvestmentAccount(InvestmentAccount investment) async {
    final index = investmentAccounts.indexWhere(
      (item) => item.id == investment.id,
    );
    if (index < 0 ||
        investment.name.trim().isEmpty ||
        investment.currentBalance < 0) {
      return;
    }
    final previous = investmentAccounts[index];
    final now = DateTime.now();
    final updated = investment.copyWith(
      name: investment.name.trim(),
      updatedAt: now,
      lastBalanceUpdateAt: previous.currentBalance == investment.currentBalance
          ? previous.lastBalanceUpdateAt
          : now,
    );
    investmentAccounts[index] = updated;
    _upsertCanonicalInvestmentAccount(updated);
    _syncFromSynoball();
    if (previous.currentBalance != updated.currentBalance) {
      _upsertInvestmentSnapshot(updated, updated.currentBalance, now, now);
    }
    await _changed();
  }

  Future<void> updateInvestmentBalance({
    required String investmentAccountId,
    required int balance,
    required DateTime date,
  }) async {
    final index = investmentAccounts.indexWhere(
      (item) => item.id == investmentAccountId,
    );
    if (index < 0 || balance < 0) return;
    final now = DateTime.now();
    final updated = investmentAccounts[index].copyWith(
      currentBalance: balance,
      updatedAt: now,
      lastBalanceUpdateAt: date,
    );
    investmentAccounts[index] = updated;
    _upsertCanonicalInvestmentAccount(updated);
    _syncFromSynoball();
    _upsertInvestmentSnapshot(updated, balance, date, now);
    await _changed();
  }

  Future<InvestmentContribution?> addInvestmentContribution({
    required String investmentAccountId,
    required int amount,
    required InvestmentContributionType type,
    required DateTime date,
    String? comment,
    String? transactionId,
    bool adjustBalance = false,
  }) async {
    final account = investmentAccounts
        .where((item) => item.id == investmentAccountId)
        .firstOrNull;
    if (account == null || amount <= 0) return null;
    final now = DateTime.now();
    final contribution = InvestmentContribution(
      id: 'investment-contribution-${now.microsecondsSinceEpoch}',
      investmentAccountId: investmentAccountId,
      transactionId: transactionId,
      date: date,
      amount: amount,
      currency: account.currency,
      type: type,
      source: transactionId == null
          ? InvestmentDataSource.manual
          : InvestmentDataSource.transaction,
      createdAt: now,
      comment: comment?.trim().isEmpty == true ? null : comment?.trim(),
    );
    investmentContributions.add(contribution);
    if (adjustBalance) {
      final next = type == InvestmentContributionType.contribution
          ? account.currentBalance + amount
          : math.max(0, account.currentBalance - amount);
      await updateInvestmentBalance(
        investmentAccountId: investmentAccountId,
        balance: next,
        date: date,
      );
    } else {
      await _changed();
    }
    return contribution;
  }

  void _upsertCanonicalInvestmentAccount(InvestmentAccount investment) {
    final canonical = _synoball.state.accounts
        .where((item) => item.id == investment.linkedAccountId)
        .firstOrNull;
    _synoball.upsertAccount(
      SynoballAccount(
        id: investment.linkedAccountId,
        entityId: canonical?.entityId ?? _legacyBridge.entityIdFor(_userId),
        name: investment.name,
        type:
            investment.type == InvestmentAccountType.brokerage ||
                investment.type == InvestmentAccountType.iis
            ? SynoballAccountType.brokerage
            : SynoballAccountType.investment,
        currency: investment.currency,
        balance: Money(
          minorUnits: investment.currentBalance * 100,
          currency: investment.currency,
        ),
        connectionId: canonical?.connectionId,
        institutionId: investment.institutionId ?? canonical?.institutionId,
        externalId:
            investment.externalAccountId ??
            canonical?.externalId ??
            investment.id,
        isVirtual: canonical?.isVirtual ?? true,
      ),
    );
  }

  void _upsertInvestmentSnapshot(
    InvestmentAccount investment,
    int balance,
    DateTime date,
    DateTime createdAt,
  ) {
    final day = DateTime(date.year, date.month, date.day);
    investmentBalanceSnapshots.removeWhere(
      (item) =>
          item.investmentAccountId == investment.id &&
          item.date.year == day.year &&
          item.date.month == day.month &&
          item.date.day == day.day,
    );
    investmentBalanceSnapshots.add(
      InvestmentBalanceSnapshot(
        id: 'investment-snapshot-${createdAt.microsecondsSinceEpoch}',
        investmentAccountId: investment.id,
        date: day,
        balance: balance,
        currency: investment.currency,
        source: investment.source,
        createdAt: createdAt,
      ),
    );
  }

  Future<DebtAccount?> addDebt({
    required String name,
    required int currentBalance,
    required DebtType type,
    String? currency,
    String? institutionName,
    int? originalPrincipal,
    double? interestRate,
    int? monthlyPayment,
    int? paymentDay,
    DateTime? nextPaymentDate,
    DateTime? startDate,
    DateTime? plannedEndDate,
    DebtPaymentType paymentType = DebtPaymentType.unknown,
    CreditCardDebtDetails? creditCardDetails,
  }) async {
    final cleanedName = name.trim();
    if (cleanedName.isEmpty || currentBalance < 0) return null;
    final now = DateTime.now();
    final debtId = 'debt-${now.microsecondsSinceEpoch}';
    final accountId = 'debt-account-${now.microsecondsSinceEpoch}';
    final resolvedCurrency = currency ?? user.defaultCurrency;
    final debt = DebtAccount(
      id: debtId,
      userId: _userId,
      name: cleanedName,
      type: type,
      currency: resolvedCurrency,
      currentBalance: currentBalance,
      status: DebtStatus.active,
      source: DebtSource.manual,
      dataQuality: DebtDataQuality.manual,
      confidence: 1,
      createdAt: now,
      updatedAt: now,
      linkedAccountId: accountId,
      institutionName: institutionName?.trim().isEmpty == true
          ? null
          : institutionName?.trim(),
      originalPrincipal: originalPrincipal,
      currentPrincipal: currentBalance,
      interestRate: interestRate,
      monthlyPayment: monthlyPayment,
      paymentDay: paymentDay,
      nextPaymentDate: nextPaymentDate,
      startDate: startDate,
      plannedEndDate: plannedEndDate,
      paymentType: paymentType,
      creditCardDetails: creditCardDetails,
    );
    _synoball.upsertAccount(
      SynoballAccount(
        id: accountId,
        entityId: _legacyBridge.entityIdFor(_userId),
        name: cleanedName,
        type: type == DebtType.creditCard
            ? SynoballAccountType.credit
            : SynoballAccountType.loan,
        currency: resolvedCurrency,
        balance: Money(
          minorUnits: currentBalance * 100,
          currency: resolvedCurrency,
        ),
        externalId: debtId,
        isVirtual: true,
      ),
    );
    _syncFromSynoball();
    debts.add(debt);
    debtBalanceSnapshots.add(
      DebtBalanceSnapshot(
        id: 'debt-snapshot-${now.microsecondsSinceEpoch}',
        debtId: debt.id,
        date: referenceDate,
        totalBalance: currentBalance,
        principalBalance: currentBalance,
        source: DebtSource.manual,
        confidence: 1,
      ),
    );
    _clearExternalData = false;
    await _changed();
    return debt;
  }

  Future<void> updateDebt(DebtAccount debt) async {
    final index = debts.indexWhere((item) => item.id == debt.id);
    if (index < 0 || debt.name.trim().isEmpty || debt.currentBalance < 0) {
      return;
    }
    final previous = debts[index];
    final accountId = debt.linkedAccountId ?? 'debt-account-${debt.id}';
    final updated = debt.copyWith(
      name: debt.name.trim(),
      updatedAt: DateTime.now(),
      linkedAccountId: accountId,
    );
    debts[index] = updated;
    final canonical = _synoball.state.accounts
        .where((item) => item.id == accountId)
        .firstOrNull;
    _synoball.upsertAccount(
      SynoballAccount(
        id: accountId,
        entityId: canonical?.entityId ?? _legacyBridge.entityIdFor(_userId),
        name: updated.name,
        type: updated.type == DebtType.creditCard
            ? SynoballAccountType.credit
            : SynoballAccountType.loan,
        currency: updated.currency,
        balance: Money(
          minorUnits: (updated.isOpen ? updated.currentBalance : 0) * 100,
          currency: updated.currency,
        ),
        connectionId: canonical?.connectionId,
        institutionId: updated.institutionId ?? canonical?.institutionId,
        externalId: canonical?.externalId ?? updated.id,
        isVirtual: canonical?.isVirtual ?? true,
      ),
    );
    _syncFromSynoball();
    if (previous.currentBalance != updated.currentBalance) {
      final now = DateTime.now();
      debtBalanceSnapshots.add(
        DebtBalanceSnapshot(
          id: 'debt-snapshot-${now.microsecondsSinceEpoch}',
          debtId: debt.id,
          date: referenceDate,
          totalBalance: updated.currentBalance,
          principalBalance: updated.currentPrincipal,
          accruedInterest: updated.accruedInterest,
          source: updated.source,
          confidence: updated.confidence,
        ),
      );
    }
    await _changed();
  }

  Future<void> archiveDebt(String id) async {
    final index = debts.indexWhere((item) => item.id == id);
    if (index < 0) return;
    debts[index] = debts[index].copyWith(
      status: DebtStatus.archived,
      updatedAt: DateTime.now(),
    );
    final debt = debts[index];
    final accountId = debt.linkedAccountId;
    if (accountId != null) {
      final canonical = _synoball.state.accounts
          .where((item) => item.id == accountId)
          .firstOrNull;
      if (canonical != null) {
        _synoball.upsertAccount(
          SynoballAccount(
            id: canonical.id,
            entityId: canonical.entityId,
            name: canonical.name,
            type: canonical.type,
            currency: canonical.currency,
            balance: Money(minorUnits: 0, currency: canonical.currency),
            connectionId: canonical.connectionId,
            institutionId: canonical.institutionId,
            externalId: canonical.externalId,
            isVirtual: canonical.isVirtual,
          ),
        );
        _syncFromSynoball();
      }
    }
    await _changed();
  }

  Future<void> addDebtPayment(DebtPayment payment) async {
    if (debts.every((item) => item.id != payment.debtId) ||
        debtPayments.any((item) => item.id == payment.id)) {
      return;
    }
    debtPayments.add(payment);
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
        minorUnits: exactMinor?.abs() ?? transaction.amountMinor.abs(),
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
          transaction.merchant ??
          transaction.normalizedMerchant ??
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

class _SberAccountReconciliation {
  const _SberAccountReconciliation({
    required this.sourceToCanonical,
    required this.duplicateToPrimary,
  });

  final Map<String, String> sourceToCanonical;
  final Map<String, String> duplicateToPrimary;
}
