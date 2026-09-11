import 'dart:convert';

import '../models/qesto_models.dart';
import '../../synoball/core/models.dart';

class UserFinancialDataCodec {
  const UserFinancialDataCodec();

  static const schemaVersion = 6;

  String encode(UserFinancialData data) => jsonEncode({
    'schemaVersion': schemaVersion,
    'user': _userToJson(data.user),
    'referenceDate': data.referenceDate.toIso8601String(),
    'accounts': data.accounts.map(_accountToJson).toList(),
    'accountPreferences': data.accountPreferences
        .map(_accountPreferencesToJson)
        .toList(),
    'budgetPeriods': data.budgetPeriods.map(_periodToJson).toList(),
    'categoryBudgets': data.categoryBudgets.map(_categoryBudgetToJson).toList(),
    'categoryCustomizations': data.categoryCustomizations
        .map(_categoryCustomizationToJson)
        .toList(),
    'transactions': data.transactions.map(_transactionToJson).toList(),
    'upcomingExpenses': data.upcomingExpenses.map(_upcomingToJson).toList(),
    'plannedCumulativePoints': data.plannedCumulativePoints
        .map(_planPointToJson)
        .toList(),
    'savingsGoals': data.savingsGoals.map(_savingsGoalToJson).toList(),
    'goalAllocations': data.goalAllocations.map(_goalAllocationToJson).toList(),
    'goalContributions': data.goalContributions
        .map(_goalContributionToJson)
        .toList(),
    'goalHistoryEvents': data.goalHistoryEvents
        .map(_goalHistoryEventToJson)
        .toList(),
    'investmentAccounts': data.investmentAccounts
        .map(_investmentAccountToJson)
        .toList(),
    'investmentBalanceSnapshots': data.investmentBalanceSnapshots
        .map(_investmentBalanceSnapshotToJson)
        .toList(),
    'investmentContributions': data.investmentContributions
        .map(_investmentContributionToJson)
        .toList(),
    'debts': data.debts.map(_debtToJson).toList(),
    'debtBalanceSnapshots': data.debtBalanceSnapshots
        .map(_debtBalanceSnapshotToJson)
        .toList(),
    'debtPayments': data.debtPayments.map(_debtPaymentToJson).toList(),
    'trackedProducts': data.trackedProducts.map(_trackedProductToJson).toList(),
    'actions': data.actions.map(_actionToJson).toList(),
    'synoball': data.synoballState?.toJson(),
  });

  UserFinancialData decode(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;
    final version = root['schemaVersion'] as int? ?? 1;
    if (version < 1 || version > schemaVersion) {
      throw const FormatException('Unsupported user data schema');
    }
    return UserFinancialData(
      user: _userFromJson(_map(root['user'])),
      referenceDate: DateTime.parse(root['referenceDate'] as String),
      accounts: _list(
        root['accounts'],
      ).map((item) => _accountFromJson(_map(item))).toList(),
      accountPreferences: _list(
        root['accountPreferences'],
      ).map((item) => _accountPreferencesFromJson(_map(item))).toList(),
      budgetPeriods: _list(
        root['budgetPeriods'],
      ).map((item) => _periodFromJson(_map(item))).toList(),
      categoryBudgets: _list(
        root['categoryBudgets'],
      ).map((item) => _categoryBudgetFromJson(_map(item))).toList(),
      categoryCustomizations: _list(
        root['categoryCustomizations'],
      ).map((item) => _categoryCustomizationFromJson(_map(item))).toList(),
      transactions: _list(
        root['transactions'],
      ).map((item) => _transactionFromJson(_map(item))).toList(),
      upcomingExpenses: _list(
        root['upcomingExpenses'],
      ).map((item) => _upcomingFromJson(_map(item))).toList(),
      plannedCumulativePoints: _list(
        root['plannedCumulativePoints'],
      ).map((item) => _planPointFromJson(_map(item))).toList(),
      savingsGoals: _list(
        root['savingsGoals'],
      ).map((item) => _savingsGoalFromJson(_map(item))).toList(),
      goalAllocations: _list(
        root['goalAllocations'],
      ).map((item) => _goalAllocationFromJson(_map(item))).toList(),
      goalContributions: _list(
        root['goalContributions'],
      ).map((item) => _goalContributionFromJson(_map(item))).toList(),
      goalHistoryEvents: _list(
        root['goalHistoryEvents'],
      ).map((item) => _goalHistoryEventFromJson(_map(item))).toList(),
      investmentAccounts: _list(
        root['investmentAccounts'],
      ).map((item) => _investmentAccountFromJson(_map(item))).toList(),
      investmentBalanceSnapshots: _list(
        root['investmentBalanceSnapshots'],
      ).map((item) => _investmentBalanceSnapshotFromJson(_map(item))).toList(),
      investmentContributions: _list(
        root['investmentContributions'],
      ).map((item) => _investmentContributionFromJson(_map(item))).toList(),
      debts: _list(
        root['debts'],
      ).map((item) => _debtFromJson(_map(item))).toList(),
      debtBalanceSnapshots: _list(
        root['debtBalanceSnapshots'],
      ).map((item) => _debtBalanceSnapshotFromJson(_map(item))).toList(),
      debtPayments: _list(
        root['debtPayments'],
      ).map((item) => _debtPaymentFromJson(_map(item))).toList(),
      trackedProducts: _list(
        root['trackedProducts'],
      ).map((item) => _trackedProductFromJson(_map(item))).toList(),
      actions: _list(
        root['actions'],
      ).map((item) => _actionFromJson(_map(item))).toList(),
      synoballState: root['synoball'] == null
          ? null
          : SynoballState.fromJson(_map(root['synoball'])),
    );
  }
}

Map<String, dynamic> _userToJson(QestoUser value) => {
  'id': value.id,
  'name': value.name,
  'defaultCurrency': value.defaultCurrency,
  'avatarUrl': value.avatarUrl,
  'expenseDisplayCurrency': value.expenseDisplayCurrency,
};

QestoUser _userFromJson(Map<String, dynamic> json) => QestoUser(
  id: json['id'] as String,
  name: json['name'] as String,
  defaultCurrency: json['defaultCurrency'] as String,
  avatarUrl: json['avatarUrl'] as String?,
  expenseDisplayCurrency: json['expenseDisplayCurrency'] as String? ?? 'RUB',
);

Map<String, dynamic> _accountToJson(QestoAccount value) => {
  'id': value.id,
  'userId': value.userId,
  'title': value.title,
  'balance': value.balance,
  'exactBalanceMinor': value.exactBalanceMinor,
  'currency': value.currency,
  'type': value.type.name,
};

QestoAccount _accountFromJson(Map<String, dynamic> json) => QestoAccount(
  id: json['id'] as String,
  userId: json['userId'] as String,
  title: json['title'] as String,
  balance: json['balance'] as int,
  exactBalanceMinor: json['exactBalanceMinor'] as int?,
  currency: json['currency'] as String,
  type: AccountType.values.byName(json['type'] as String),
);

Map<String, dynamic> _accountPreferencesToJson(QestoAccountPreferences value) =>
    {
      'accountId': value.accountId,
      'role': value.role.name,
      'includeInTotal': value.includeInTotal,
      'includeInNetWorth': value.includeInNetWorth,
      'includeInEmergencyFund': value.includeInEmergencyFund,
      'isVisible': value.isVisible,
      'includeTransactionsInAnalytics': value.includeTransactionsInAnalytics,
      'isClosed': value.isClosed,
    };

QestoAccountPreferences _accountPreferencesFromJson(
  Map<String, dynamic> json,
) => QestoAccountPreferences(
  accountId: json['accountId'] as String,
  role: QestoAccountRole.values.byName(
    json['role'] as String? ?? QestoAccountRole.other.name,
  ),
  includeInTotal: json['includeInTotal'] as bool? ?? true,
  includeInNetWorth: json['includeInNetWorth'] as bool? ?? true,
  includeInEmergencyFund: json['includeInEmergencyFund'] as bool? ?? false,
  isVisible: json['isVisible'] as bool? ?? true,
  includeTransactionsInAnalytics:
      json['includeTransactionsInAnalytics'] as bool? ?? true,
  isClosed: json['isClosed'] as bool? ?? false,
);

Map<String, dynamic> _periodToJson(BudgetPeriod value) => {
  'id': value.id,
  'userId': value.userId,
  'startDate': value.startDate.toIso8601String(),
  'endDate': value.endDate.toIso8601String(),
  'type': value.type.name,
  'totalPlan': value.totalPlan,
  'currency': value.currency,
};

BudgetPeriod _periodFromJson(Map<String, dynamic> json) => BudgetPeriod(
  id: json['id'] as String,
  userId: json['userId'] as String,
  startDate: DateTime.parse(json['startDate'] as String),
  endDate: DateTime.parse(json['endDate'] as String),
  type: BudgetPeriodType.values.byName(json['type'] as String),
  totalPlan: json['totalPlan'] as int,
  currency: json['currency'] as String,
);

Map<String, dynamic> _categoryBudgetToJson(CategoryBudget value) => {
  'id': value.id,
  'budgetPeriodId': value.budgetPeriodId,
  'categoryId': value.categoryId,
  'plannedAmount': value.plannedAmount,
};

CategoryBudget _categoryBudgetFromJson(Map<String, dynamic> json) =>
    CategoryBudget(
      id: json['id'] as String,
      budgetPeriodId: json['budgetPeriodId'] as String,
      categoryId: json['categoryId'] as String,
      plannedAmount: json['plannedAmount'] as int,
    );

Map<String, dynamic> _categoryCustomizationToJson(
  BudgetCategoryCustomization value,
) => {
  'categoryId': value.categoryId,
  'name': value.name,
  'iconKey': value.iconKey,
  'colorValue': value.colorValue,
};

BudgetCategoryCustomization _categoryCustomizationFromJson(
  Map<String, dynamic> json,
) => BudgetCategoryCustomization(
  categoryId: json['categoryId'] as String,
  name: json['name'] as String,
  iconKey: json['iconKey'] as String,
  colorValue: json['colorValue'] as int,
);

Map<String, dynamic> _transactionToJson(BudgetTransaction value) => {
  'id': value.id,
  'userId': value.userId,
  'accountId': value.accountId,
  'date': value.date.toIso8601String(),
  'amount': value.amount,
  'exactAmountMinor': value.exactAmountMinor,
  'currency': value.currency,
  'type': value.type.name,
  'categoryId': value.categoryId,
  'subcategoryId': value.subcategoryId,
  'merchant': value.merchant,
  'title': value.title,
  'description': value.description,
  'comment': value.comment,
  'isLargePurchase': value.isLargePurchase,
  'normalizedMerchant': value.normalizedMerchant,
  'isRecurring': value.isRecurring,
  'isConfirmed': value.isConfirmed,
  'isPotentialDuplicate': value.isPotentialDuplicate,
  'classificationConfidence': value.classificationConfidence,
  'originalCategoryId': value.originalCategoryId,
  'transferDirection': value.transferDirection?.name,
  'tags': value.tags,
  'receipt': value.receipt == null ? null : _receiptToJson(value.receipt!),
};

BudgetTransaction _transactionFromJson(Map<String, dynamic> json) =>
    BudgetTransaction(
      id: json['id'] as String,
      userId: json['userId'] as String,
      accountId: json['accountId'] as String,
      date: DateTime.parse(json['date'] as String),
      amount: json['amount'] as int,
      exactAmountMinor: json['exactAmountMinor'] as int?,
      currency: json['currency'] as String,
      type: TransactionType.values.byName(json['type'] as String),
      categoryId: json['categoryId'] as String?,
      subcategoryId: json['subcategoryId'] as String?,
      merchant: json['merchant'] as String?,
      title: json['title'] as String?,
      description: json['description'] as String?,
      comment: json['comment'] as String?,
      isLargePurchase: json['isLargePurchase'] as bool? ?? false,
      normalizedMerchant: json['normalizedMerchant'] as String?,
      isRecurring: json['isRecurring'] as bool? ?? false,
      isConfirmed: json['isConfirmed'] as bool? ?? true,
      isPotentialDuplicate: json['isPotentialDuplicate'] as bool? ?? false,
      classificationConfidence:
          (json['classificationConfidence'] as num?)?.toDouble() ?? 1,
      originalCategoryId: json['originalCategoryId'] as String?,
      transferDirection: json['transferDirection'] == null
          ? null
          : TransferDirection.values.byName(
              json['transferDirection'] as String,
            ),
      tags: _list(json['tags']).cast<String>(),
      receipt: json['receipt'] == null
          ? null
          : _receiptFromJson(_map(json['receipt'])),
    );

Map<String, dynamic> _receiptToJson(TransactionReceiptDetails value) => {
  'id': value.id,
  'purchasedAt': value.purchasedAt.toIso8601String(),
  'totalMinor': value.totalMinor,
  'fiscalDriveNumber': value.fiscalDriveNumber,
  'fiscalDocumentNumber': value.fiscalDocumentNumber,
  'fiscalSign': value.fiscalSign,
  'merchant': value.merchant,
  'items': value.items
      .map(
        (item) => {
          'name': item.name,
          'quantity': item.quantity,
          'unitPriceMinor': item.unitPriceMinor,
          'totalMinor': item.totalMinor,
        },
      )
      .toList(),
};

TransactionReceiptDetails _receiptFromJson(Map<String, dynamic> json) =>
    TransactionReceiptDetails(
      id: json['id'] as String,
      purchasedAt: DateTime.parse(json['purchasedAt'] as String),
      totalMinor: json['totalMinor'] as int,
      fiscalDriveNumber: json['fiscalDriveNumber'] as String,
      fiscalDocumentNumber: json['fiscalDocumentNumber'] as String,
      fiscalSign: json['fiscalSign'] as String,
      merchant: json['merchant'] as String?,
      items: _list(json['items']).map((value) {
        final item = _map(value);
        return TransactionReceiptItem(
          name: item['name'] as String,
          quantity: (item['quantity'] as num?)?.toDouble() ?? 1,
          unitPriceMinor: item['unitPriceMinor'] as int?,
          totalMinor: item['totalMinor'] as int,
        );
      }).toList(),
    );

Map<String, dynamic> _upcomingToJson(UpcomingExpense value) => {
  'id': value.id,
  'userId': value.userId,
  'budgetPeriodId': value.budgetPeriodId,
  'title': value.title,
  'amount': value.amount,
  'currency': value.currency,
  'plannedDate': value.plannedDate.toIso8601String(),
  'categoryId': value.categoryId,
  'accountId': value.accountId,
  'isRecurring': value.isRecurring,
  'recurrenceRule': value.recurrenceRule,
  'source': value.source.name,
  'isCancelled': value.isCancelled,
};

UpcomingExpense _upcomingFromJson(Map<String, dynamic> json) => UpcomingExpense(
  id: json['id'] as String,
  userId: json['userId'] as String,
  budgetPeriodId: json['budgetPeriodId'] as String,
  title: json['title'] as String,
  amount: json['amount'] as int,
  currency: json['currency'] as String,
  plannedDate: DateTime.parse(json['plannedDate'] as String),
  categoryId: json['categoryId'] as String?,
  accountId: json['accountId'] as String?,
  isRecurring: json['isRecurring'] as bool? ?? false,
  recurrenceRule: json['recurrenceRule'] as String?,
  source: UpcomingExpenseSource.values.byName(json['source'] as String),
  isCancelled: json['isCancelled'] as bool? ?? false,
);

Map<String, dynamic> _planPointToJson(BudgetPlanPoint value) => {
  'budgetPeriodId': value.budgetPeriodId,
  'date': value.date.toIso8601String(),
  'cumulativePlannedAmount': value.cumulativePlannedAmount,
};

BudgetPlanPoint _planPointFromJson(Map<String, dynamic> json) =>
    BudgetPlanPoint(
      budgetPeriodId: json['budgetPeriodId'] as String,
      date: DateTime.parse(json['date'] as String),
      cumulativePlannedAmount: json['cumulativePlannedAmount'] as int,
    );

Map<String, dynamic> _savingsGoalToJson(SavingsGoal value) => {
  'id': value.id,
  'userId': value.userId,
  'title': value.title,
  'targetAmount': value.targetAmount,
  'savedAmount': value.savedAmount,
  'currency': value.currency,
  'streakWeeks': value.streakWeeks,
  'isActive': value.isActive,
  'category': value.category,
  'type': value.type.name,
  'targetDate': value.targetDate?.toIso8601String(),
  'iconKey': value.iconKey,
  'colorValue': value.colorValue,
  'comment': value.comment,
  'desiredMonthlyContribution': value.desiredMonthlyContribution,
  'priority': value.priority.name,
  'status': value.effectiveStatus.name,
  'createdAt': value.createdAt?.toIso8601String(),
  'fundedAt': value.fundedAt?.toIso8601String(),
  'completedAt': value.completedAt?.toIso8601String(),
  'reminder': value.reminder == null
      ? null
      : {
          'enabled': value.reminder!.enabled,
          'amount': value.reminder!.amount,
          'day': value.reminder!.day,
          'cadence': value.reminder!.cadence.name,
        },
  'history': value.history
      .map(
        (item) => {'date': item.date.toIso8601String(), 'amount': item.amount},
      )
      .toList(),
};

SavingsGoal _savingsGoalFromJson(Map<String, dynamic> json) => SavingsGoal(
  id: json['id'] as String,
  userId: json['userId'] as String,
  title: json['title'] as String,
  targetAmount: json['targetAmount'] as int,
  savedAmount: json['savedAmount'] as int,
  currency: json['currency'] as String,
  streakWeeks: json['streakWeeks'] as int,
  isActive: json['isActive'] as bool,
  category: json['category'] as String? ?? 'Другое',
  type: _enumByName(
    GoalType.values,
    json['type'],
    json['targetDate'] == null
        ? GoalType.targetAmount
        : GoalType.targetAmountDate,
  ),
  targetDate: json['targetDate'] == null
      ? null
      : DateTime.tryParse(json['targetDate'] as String),
  iconKey: json['iconKey'] as String? ?? 'flag',
  colorValue: json['colorValue'] as int?,
  comment: json['comment'] as String?,
  desiredMonthlyContribution: json['desiredMonthlyContribution'] as int?,
  priority: _enumByName(
    GoalPriority.values,
    json['priority'],
    GoalPriority.medium,
  ),
  status: _enumByName(
    GoalStatus.values,
    json['status'],
    (json['isActive'] as bool? ?? true) ? GoalStatus.active : GoalStatus.paused,
  ),
  reminder: json['reminder'] == null
      ? null
      : _goalReminderFromJson(_map(json['reminder'])),
  createdAt: _optionalDate(json['createdAt']),
  fundedAt: _optionalDate(json['fundedAt']),
  completedAt: _optionalDate(json['completedAt']),
  history: _list(json['history'])
      .map(
        (item) => SavingsHistoryPoint(
          date: DateTime.parse(_map(item)['date'] as String),
          amount: _map(item)['amount'] as int,
        ),
      )
      .toList(),
);

GoalReminder _goalReminderFromJson(Map<String, dynamic> json) => GoalReminder(
  enabled: json['enabled'] as bool? ?? false,
  amount: json['amount'] as int? ?? 0,
  day: (json['day'] as int? ?? 1).clamp(1, 31),
  cadence: _enumByName(
    GoalReminderCadence.values,
    json['cadence'],
    GoalReminderCadence.monthly,
  ),
);

Map<String, dynamic> _goalAllocationToJson(GoalAllocation value) => {
  'id': value.id,
  'goalId': value.goalId,
  'sourceType': value.sourceType.name,
  'sourceId': value.sourceId,
  'allocatedAmount': value.allocatedAmount,
  'currency': value.currency,
  'updatedAt': value.updatedAt.toIso8601String(),
};

GoalAllocation _goalAllocationFromJson(Map<String, dynamic> json) =>
    GoalAllocation(
      id: json['id'] as String,
      goalId: json['goalId'] as String,
      sourceType: _enumByName(
        GoalAllocationSourceType.values,
        json['sourceType'],
        GoalAllocationSourceType.manualAsset,
      ),
      sourceId: json['sourceId'] as String,
      allocatedAmount: json['allocatedAmount'] as int,
      currency: json['currency'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _goalContributionToJson(GoalContribution value) => {
  'id': value.id,
  'goalId': value.goalId,
  'date': value.date.toIso8601String(),
  'amount': value.amount,
  'currency': value.currency,
  'type': value.type.name,
  'source': value.source.name,
  'createdAt': value.createdAt.toIso8601String(),
  'transactionId': value.transactionId,
  'accountId': value.accountId,
  'comment': value.comment,
};

GoalContribution _goalContributionFromJson(Map<String, dynamic> json) =>
    GoalContribution(
      id: json['id'] as String,
      goalId: json['goalId'] as String,
      date: DateTime.parse(json['date'] as String),
      amount: json['amount'] as int,
      currency: json['currency'] as String? ?? 'RUB',
      type: _enumByName(
        GoalContributionType.values,
        json['type'],
        GoalContributionType.contribution,
      ),
      source: _enumByName(
        GoalContributionSource.values,
        json['source'],
        GoalContributionSource.manual,
      ),
      createdAt:
          _optionalDate(json['createdAt']) ??
          DateTime.parse(json['date'] as String),
      transactionId: json['transactionId'] as String?,
      accountId: json['accountId'] as String?,
      comment: json['comment'] as String?,
    );

Map<String, dynamic> _goalHistoryEventToJson(GoalHistoryEvent value) => {
  'id': value.id,
  'goalId': value.goalId,
  'type': value.type.name,
  'date': value.date.toIso8601String(),
  'description': value.description,
  'amount': value.amount,
};

GoalHistoryEvent _goalHistoryEventFromJson(Map<String, dynamic> json) =>
    GoalHistoryEvent(
      id: json['id'] as String,
      goalId: json['goalId'] as String,
      type: _enumByName(
        GoalHistoryEventType.values,
        json['type'],
        GoalHistoryEventType.created,
      ),
      date: DateTime.parse(json['date'] as String),
      description: json['description'] as String? ?? '',
      amount: json['amount'] as int?,
    );

Map<String, dynamic> _investmentAccountToJson(InvestmentAccount value) => {
  'id': value.id,
  'userId': value.userId,
  'linkedAccountId': value.linkedAccountId,
  'name': value.name,
  'brokerName': value.brokerName,
  'type': value.type.name,
  'currency': value.currency,
  'currentBalance': value.currentBalance,
  'openedAt': value.openedAt?.toIso8601String(),
  'comment': value.comment,
  'includeInTotal': value.includeInTotal,
  'status': value.status.name,
  'source': value.source.name,
  'createdAt': value.createdAt.toIso8601String(),
  'updatedAt': value.updatedAt.toIso8601String(),
  'lastBalanceUpdateAt': value.lastBalanceUpdateAt.toIso8601String(),
  'externalAccountId': value.externalAccountId,
  'institutionId': value.institutionId,
  'lastSyncAt': value.lastSyncAt?.toIso8601String(),
  'plan': value.plan == null ? null : _investmentPlanToJson(value.plan!),
};

InvestmentAccount _investmentAccountFromJson(Map<String, dynamic> json) =>
    InvestmentAccount(
      id: json['id'] as String,
      userId: json['userId'] as String,
      linkedAccountId: json['linkedAccountId'] as String,
      name: json['name'] as String,
      brokerName: json['brokerName'] as String?,
      type: _enumByName(
        InvestmentAccountType.values,
        json['type'],
        InvestmentAccountType.other,
      ),
      currency: json['currency'] as String? ?? 'RUB',
      currentBalance: json['currentBalance'] as int? ?? 0,
      openedAt: _optionalDate(json['openedAt']),
      comment: json['comment'] as String?,
      includeInTotal: json['includeInTotal'] as bool? ?? true,
      status: _enumByName(
        InvestmentAccountStatus.values,
        json['status'],
        InvestmentAccountStatus.active,
      ),
      source: _enumByName(
        InvestmentDataSource.values,
        json['source'],
        InvestmentDataSource.manual,
      ),
      createdAt:
          _optionalDate(json['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          _optionalDate(json['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastBalanceUpdateAt:
          _optionalDate(json['lastBalanceUpdateAt']) ??
          _optionalDate(json['updatedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      externalAccountId: json['externalAccountId'] as String?,
      institutionId: json['institutionId'] as String?,
      lastSyncAt: _optionalDate(json['lastSyncAt']),
      plan: json['plan'] == null
          ? null
          : _investmentPlanFromJson(_map(json['plan'])),
    );

Map<String, dynamic> _investmentPlanToJson(InvestmentPlan value) => {
  'amount': value.amount,
  'frequency': value.frequency.name,
  'preferredDay': value.preferredDay,
  'enabled': value.enabled,
  'reminderEnabled': value.reminderEnabled,
};

InvestmentPlan _investmentPlanFromJson(Map<String, dynamic> json) =>
    InvestmentPlan(
      amount: json['amount'] as int? ?? 0,
      frequency: _enumByName(
        InvestmentPlanFrequency.values,
        json['frequency'],
        InvestmentPlanFrequency.monthly,
      ),
      preferredDay: json['preferredDay'] as int?,
      enabled: json['enabled'] as bool? ?? true,
      reminderEnabled: json['reminderEnabled'] as bool? ?? false,
    );

Map<String, dynamic> _investmentBalanceSnapshotToJson(
  InvestmentBalanceSnapshot value,
) => {
  'id': value.id,
  'investmentAccountId': value.investmentAccountId,
  'date': value.date.toIso8601String(),
  'balance': value.balance,
  'currency': value.currency,
  'balanceBaseCurrency': value.balanceBaseCurrency,
  'source': value.source.name,
  'createdAt': value.createdAt.toIso8601String(),
};

InvestmentBalanceSnapshot _investmentBalanceSnapshotFromJson(
  Map<String, dynamic> json,
) => InvestmentBalanceSnapshot(
  id: json['id'] as String,
  investmentAccountId: json['investmentAccountId'] as String,
  date: DateTime.parse(json['date'] as String),
  balance: json['balance'] as int,
  currency: json['currency'] as String? ?? 'RUB',
  balanceBaseCurrency: json['balanceBaseCurrency'] as int?,
  source: _enumByName(
    InvestmentDataSource.values,
    json['source'],
    InvestmentDataSource.manual,
  ),
  createdAt:
      _optionalDate(json['createdAt']) ??
      DateTime.parse(json['date'] as String),
);

Map<String, dynamic> _investmentContributionToJson(
  InvestmentContribution value,
) => {
  'id': value.id,
  'investmentAccountId': value.investmentAccountId,
  'transactionId': value.transactionId,
  'date': value.date.toIso8601String(),
  'amount': value.amount,
  'currency': value.currency,
  'type': value.type.name,
  'source': value.source.name,
  'createdAt': value.createdAt.toIso8601String(),
  'comment': value.comment,
};

InvestmentContribution _investmentContributionFromJson(
  Map<String, dynamic> json,
) => InvestmentContribution(
  id: json['id'] as String,
  investmentAccountId: json['investmentAccountId'] as String,
  transactionId: json['transactionId'] as String?,
  date: DateTime.parse(json['date'] as String),
  amount: json['amount'] as int,
  currency: json['currency'] as String? ?? 'RUB',
  type: _enumByName(
    InvestmentContributionType.values,
    json['type'],
    InvestmentContributionType.contribution,
  ),
  source: _enumByName(
    InvestmentDataSource.values,
    json['source'],
    InvestmentDataSource.manual,
  ),
  createdAt:
      _optionalDate(json['createdAt']) ??
      DateTime.parse(json['date'] as String),
  comment: json['comment'] as String?,
);

Map<String, dynamic> _debtToJson(DebtAccount value) => {
  'id': value.id,
  'userId': value.userId,
  'name': value.name,
  'type': value.type.name,
  'currency': value.currency,
  'currentBalance': value.currentBalance,
  'status': value.status.name,
  'source': value.source.name,
  'dataQuality': value.dataQuality.name,
  'confidence': value.confidence,
  'createdAt': value.createdAt.toIso8601String(),
  'updatedAt': value.updatedAt.toIso8601String(),
  'institutionId': value.institutionId,
  'institutionName': value.institutionName,
  'linkedAccountId': value.linkedAccountId,
  'originalPrincipal': value.originalPrincipal,
  'currentPrincipal': value.currentPrincipal,
  'accruedInterest': value.accruedInterest,
  'interestRate': value.interestRate,
  'effectiveRate': value.effectiveRate,
  'monthlyPayment': value.monthlyPayment,
  'paymentDay': value.paymentDay,
  'nextPaymentDate': value.nextPaymentDate?.toIso8601String(),
  'startDate': value.startDate?.toIso8601String(),
  'plannedEndDate': value.plannedEndDate?.toIso8601String(),
  'paymentType': value.paymentType.name,
  'creditCardDetails': value.creditCardDetails == null
      ? null
      : _creditCardDetailsToJson(value.creditCardDetails!),
};

DebtAccount _debtFromJson(Map<String, dynamic> json) => DebtAccount(
  id: json['id'] as String,
  userId: json['userId'] as String,
  name: json['name'] as String,
  type: _enumByName(DebtType.values, json['type'], DebtType.other),
  currency: json['currency'] as String? ?? 'RUB',
  currentBalance: json['currentBalance'] as int? ?? 0,
  status: _enumByName(DebtStatus.values, json['status'], DebtStatus.active),
  source: _enumByName(DebtSource.values, json['source'], DebtSource.manual),
  dataQuality: _enumByName(
    DebtDataQuality.values,
    json['dataQuality'],
    DebtDataQuality.incomplete,
  ),
  confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
  createdAt:
      DateTime.tryParse(json['createdAt'] as String? ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0),
  updatedAt:
      DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0),
  institutionId: json['institutionId'] as String?,
  institutionName: json['institutionName'] as String?,
  linkedAccountId: json['linkedAccountId'] as String?,
  originalPrincipal: json['originalPrincipal'] as int?,
  currentPrincipal: json['currentPrincipal'] as int?,
  accruedInterest: json['accruedInterest'] as int?,
  interestRate: (json['interestRate'] as num?)?.toDouble(),
  effectiveRate: (json['effectiveRate'] as num?)?.toDouble(),
  monthlyPayment: json['monthlyPayment'] as int?,
  paymentDay: json['paymentDay'] as int?,
  nextPaymentDate: _optionalDate(json['nextPaymentDate']),
  startDate: _optionalDate(json['startDate']),
  plannedEndDate: _optionalDate(json['plannedEndDate']),
  paymentType: _enumByName(
    DebtPaymentType.values,
    json['paymentType'],
    DebtPaymentType.unknown,
  ),
  creditCardDetails: json['creditCardDetails'] == null
      ? null
      : _creditCardDetailsFromJson(_map(json['creditCardDetails'])),
);

Map<String, dynamic> _creditCardDetailsToJson(CreditCardDebtDetails value) => {
  'creditLimit': value.creditLimit,
  'minimumPayment': value.minimumPayment,
  'gracePaymentAmount': value.gracePaymentAmount,
  'graceDeadline': value.graceDeadline?.toIso8601String(),
  'gracePeriodEnd': value.gracePeriodEnd?.toIso8601String(),
  'interestRateAfterGrace': value.interestRateAfterGrace,
};

CreditCardDebtDetails _creditCardDetailsFromJson(Map<String, dynamic> json) =>
    CreditCardDebtDetails(
      creditLimit: json['creditLimit'] as int?,
      minimumPayment: json['minimumPayment'] as int?,
      gracePaymentAmount: json['gracePaymentAmount'] as int?,
      graceDeadline: _optionalDate(json['graceDeadline']),
      gracePeriodEnd: _optionalDate(json['gracePeriodEnd']),
      interestRateAfterGrace: (json['interestRateAfterGrace'] as num?)
          ?.toDouble(),
    );

Map<String, dynamic> _debtBalanceSnapshotToJson(DebtBalanceSnapshot value) => {
  'id': value.id,
  'debtId': value.debtId,
  'date': value.date.toIso8601String(),
  'totalBalance': value.totalBalance,
  'principalBalance': value.principalBalance,
  'accruedInterest': value.accruedInterest,
  'source': value.source.name,
  'confidence': value.confidence,
};

DebtBalanceSnapshot _debtBalanceSnapshotFromJson(Map<String, dynamic> json) =>
    DebtBalanceSnapshot(
      id: json['id'] as String,
      debtId: json['debtId'] as String,
      date: DateTime.parse(json['date'] as String),
      totalBalance: json['totalBalance'] as int,
      principalBalance: json['principalBalance'] as int?,
      accruedInterest: json['accruedInterest'] as int?,
      source: _enumByName(DebtSource.values, json['source'], DebtSource.manual),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
    );

Map<String, dynamic> _debtPaymentToJson(DebtPayment value) => {
  'id': value.id,
  'debtId': value.debtId,
  'transactionId': value.transactionId,
  'date': value.date.toIso8601String(),
  'amount': value.amount,
  'currency': value.currency,
  'principalAmount': value.principalAmount,
  'interestAmount': value.interestAmount,
  'feeAmount': value.feeAmount,
  'source': value.source.name,
  'confidence': value.confidence,
};

DebtPayment _debtPaymentFromJson(Map<String, dynamic> json) => DebtPayment(
  id: json['id'] as String,
  debtId: json['debtId'] as String,
  transactionId: json['transactionId'] as String?,
  date: DateTime.parse(json['date'] as String),
  amount: json['amount'] as int,
  currency: json['currency'] as String,
  principalAmount: json['principalAmount'] as int?,
  interestAmount: json['interestAmount'] as int?,
  feeAmount: json['feeAmount'] as int?,
  source: _enumByName(DebtSource.values, json['source'], DebtSource.manual),
  confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
);

Map<String, dynamic> _trackedProductToJson(TrackedProduct value) => {
  'id': value.id,
  'userId': value.userId,
  'title': value.title,
  'currentPrice': value.currentPrice,
  'currency': value.currency,
  'bestMarketplace': value.bestMarketplace,
  'changePercent': value.changePercent,
  'trackedStoresCount': value.trackedStoresCount,
  'visualKey': value.visualKey,
};

TrackedProduct _trackedProductFromJson(Map<String, dynamic> json) =>
    TrackedProduct(
      id: json['id'] as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      currentPrice: json['currentPrice'] as int,
      currency: json['currency'] as String,
      bestMarketplace: json['bestMarketplace'] as String,
      changePercent: (json['changePercent'] as num).toDouble(),
      trackedStoresCount: json['trackedStoresCount'] as int,
      visualKey: json['visualKey'] as String,
    );

Map<String, dynamic> _actionToJson(FinancialAction value) => {
  'id': value.id,
  'occurredAt': value.occurredAt.toIso8601String(),
  'title': value.title,
  'type': value.type.name,
  'createdTransactionIds': value.createdTransactionIds,
  'createdAccountIds': value.createdAccountIds,
  'createdPeriodIds': value.createdPeriodIds,
  'previousTransactions': value.previousTransactions
      .map(_transactionToJson)
      .toList(),
  'previousAccounts': value.previousAccounts.map(_accountToJson).toList(),
  'isUndone': value.isUndone,
};

FinancialAction _actionFromJson(Map<String, dynamic> json) => FinancialAction(
  id: json['id'] as String,
  occurredAt: DateTime.parse(json['occurredAt'] as String),
  title: json['title'] as String,
  type: FinancialActionType.values.byName(json['type'] as String),
  createdTransactionIds: _list(json['createdTransactionIds']).cast<String>(),
  createdAccountIds: _list(json['createdAccountIds']).cast<String>(),
  createdPeriodIds: _list(json['createdPeriodIds']).cast<String>(),
  previousTransactions: _list(
    json['previousTransactions'],
  ).map((item) => _transactionFromJson(_map(item))).toList(),
  previousAccounts: _list(
    json['previousAccounts'],
  ).map((item) => _accountFromJson(_map(item))).toList(),
  isUndone: json['isUndone'] as bool? ?? false,
);

Map<String, dynamic> _map(Object? value) => value as Map<String, dynamic>;
List<dynamic> _list(Object? value) => value as List<dynamic>? ?? const [];

DateTime? _optionalDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  return values.where((item) => item.name == name).firstOrNull ?? fallback;
}
