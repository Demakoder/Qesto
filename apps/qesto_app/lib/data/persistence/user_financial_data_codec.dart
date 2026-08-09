import 'dart:convert';

import '../models/qesto_models.dart';

class UserFinancialDataCodec {
  const UserFinancialDataCodec();

  static const schemaVersion = 1;

  String encode(UserFinancialData data) => jsonEncode({
    'schemaVersion': schemaVersion,
    'user': _userToJson(data.user),
    'referenceDate': data.referenceDate.toIso8601String(),
    'accounts': data.accounts.map(_accountToJson).toList(),
    'budgetPeriods': data.budgetPeriods.map(_periodToJson).toList(),
    'categoryBudgets': data.categoryBudgets.map(_categoryBudgetToJson).toList(),
    'transactions': data.transactions.map(_transactionToJson).toList(),
    'upcomingExpenses': data.upcomingExpenses.map(_upcomingToJson).toList(),
    'plannedCumulativePoints': data.plannedCumulativePoints
        .map(_planPointToJson)
        .toList(),
    'savingsGoals': data.savingsGoals.map(_savingsGoalToJson).toList(),
    'trackedProducts': data.trackedProducts.map(_trackedProductToJson).toList(),
    'actions': data.actions.map(_actionToJson).toList(),
  });

  UserFinancialData decode(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;
    if (root['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported user data schema');
    }
    return UserFinancialData(
      user: _userFromJson(_map(root['user'])),
      referenceDate: DateTime.parse(root['referenceDate'] as String),
      accounts: _list(
        root['accounts'],
      ).map((item) => _accountFromJson(_map(item))).toList(),
      budgetPeriods: _list(
        root['budgetPeriods'],
      ).map((item) => _periodFromJson(_map(item))).toList(),
      categoryBudgets: _list(
        root['categoryBudgets'],
      ).map((item) => _categoryBudgetFromJson(_map(item))).toList(),
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
      trackedProducts: _list(
        root['trackedProducts'],
      ).map((item) => _trackedProductFromJson(_map(item))).toList(),
      actions: _list(
        root['actions'],
      ).map((item) => _actionFromJson(_map(item))).toList(),
    );
  }
}

Map<String, dynamic> _userToJson(QestoUser value) => {
  'id': value.id,
  'name': value.name,
  'defaultCurrency': value.defaultCurrency,
  'avatarUrl': value.avatarUrl,
};

QestoUser _userFromJson(Map<String, dynamic> json) => QestoUser(
  id: json['id'] as String,
  name: json['name'] as String,
  defaultCurrency: json['defaultCurrency'] as String,
  avatarUrl: json['avatarUrl'] as String?,
);

Map<String, dynamic> _accountToJson(QestoAccount value) => {
  'id': value.id,
  'userId': value.userId,
  'title': value.title,
  'balance': value.balance,
  'currency': value.currency,
  'type': value.type.name,
};

QestoAccount _accountFromJson(Map<String, dynamic> json) => QestoAccount(
  id: json['id'] as String,
  userId: json['userId'] as String,
  title: json['title'] as String,
  balance: json['balance'] as int,
  currency: json['currency'] as String,
  type: AccountType.values.byName(json['type'] as String),
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

Map<String, dynamic> _transactionToJson(BudgetTransaction value) => {
  'id': value.id,
  'userId': value.userId,
  'accountId': value.accountId,
  'date': value.date.toIso8601String(),
  'amount': value.amount,
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
  history: _list(json['history'])
      .map(
        (item) => SavingsHistoryPoint(
          date: DateTime.parse(_map(item)['date'] as String),
          amount: _map(item)['amount'] as int,
        ),
      )
      .toList(),
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
