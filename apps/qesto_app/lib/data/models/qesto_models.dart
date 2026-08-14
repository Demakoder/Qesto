export 'budget_models.dart';

import 'budget_models.dart';
import '../../synoball/core/models.dart';

enum AccountType {
  cash,
  bankCard,
  savings,
  deposit,
  investment,
  receivable,
  liability,
  other,
}

enum DealKind { coupon, promotion }

enum FinancialActionType { statementImport, transactionAdded }

class QestoUser {
  const QestoUser({
    required this.id,
    required this.name,
    required this.defaultCurrency,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String defaultCurrency;
  final String? avatarUrl;

  QestoUser copyWith({
    String? name,
    String? defaultCurrency,
    String? avatarUrl,
    bool clearAvatar = false,
  }) => QestoUser(
    id: id,
    name: name ?? this.name,
    defaultCurrency: defaultCurrency ?? this.defaultCurrency,
    avatarUrl: clearAvatar ? null : avatarUrl ?? this.avatarUrl,
  );
}

class QestoAccount {
  const QestoAccount({
    required this.id,
    required this.userId,
    required this.title,
    required this.balance,
    required this.currency,
    required this.type,
  });

  final String id;
  final String userId;
  final String title;
  final int balance;
  final String currency;
  final AccountType type;
}

class Deal {
  const Deal({
    required this.id,
    required this.userId,
    required this.kind,
    required this.category,
    required this.title,
    required this.description,
    required this.visualKey,
    this.badge,
    this.promoCode,
    this.merchantName,
    this.targetUrl,
    this.sourceUrl,
    this.discountType,
    this.discountValue,
    this.minimumOrder,
    this.maximumDiscount,
    this.customerType,
    this.validUntil,
    this.confidence,
  });

  final String id;
  final String userId;
  final DealKind kind;
  final String category;
  final String title;
  final String description;
  final String visualKey;
  final String? badge;
  final String? promoCode;
  final String? merchantName;
  final String? targetUrl;
  final String? sourceUrl;
  final String? discountType;
  final int? discountValue;
  final int? minimumOrder;
  final int? maximumDiscount;
  final String? customerType;
  final DateTime? validUntil;
  final int? confidence;
}

class TrackedProduct {
  const TrackedProduct({
    required this.id,
    required this.userId,
    required this.title,
    required this.currentPrice,
    required this.currency,
    required this.bestMarketplace,
    required this.changePercent,
    required this.trackedStoresCount,
    required this.visualKey,
  });

  final String id;
  final String userId;
  final String title;
  final int currentPrice;
  final String currency;
  final String bestMarketplace;
  final double changePercent;
  final int trackedStoresCount;
  final String visualKey;
}

class SavingsHistoryPoint {
  const SavingsHistoryPoint({required this.date, required this.amount});

  final DateTime date;
  final int amount;
}

class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.userId,
    required this.title,
    required this.targetAmount,
    required this.savedAmount,
    required this.currency,
    required this.streakWeeks,
    required this.isActive,
    required this.history,
  });

  final String id;
  final String userId;
  final String title;
  final int targetAmount;
  final int savedAmount;
  final String currency;
  final int streakWeeks;
  final bool isActive;
  final List<SavingsHistoryPoint> history;

  double get progress => targetAmount == 0 ? 0 : savedAmount / targetAmount;
}

class FinancialAction {
  const FinancialAction({
    required this.id,
    required this.occurredAt,
    required this.title,
    required this.type,
    this.createdTransactionIds = const [],
    this.createdAccountIds = const [],
    this.createdPeriodIds = const [],
    this.previousTransactions = const [],
    this.previousAccounts = const [],
    this.isUndone = false,
  });

  final String id;
  final DateTime occurredAt;
  final String title;
  final FinancialActionType type;
  final List<String> createdTransactionIds;
  final List<String> createdAccountIds;
  final List<String> createdPeriodIds;
  final List<BudgetTransaction> previousTransactions;
  final List<QestoAccount> previousAccounts;
  final bool isUndone;

  FinancialAction copyWith({bool? isUndone}) => FinancialAction(
    id: id,
    occurredAt: occurredAt,
    title: title,
    type: type,
    createdTransactionIds: createdTransactionIds,
    createdAccountIds: createdAccountIds,
    createdPeriodIds: createdPeriodIds,
    previousTransactions: previousTransactions,
    previousAccounts: previousAccounts,
    isUndone: isUndone ?? this.isUndone,
  );
}

class QestoAppData {
  const QestoAppData({
    required this.budgetConfiguration,
    required this.financialData,
    required this.coupons,
    required this.promotions,
  });

  final BudgetConfiguration budgetConfiguration;
  final UserFinancialData financialData;
  final List<Deal> coupons;
  final List<Deal> promotions;
}

class UserFinancialData {
  const UserFinancialData({
    required this.user,
    required this.referenceDate,
    this.accounts = const [],
    this.budgetPeriods = const [],
    this.categoryBudgets = const [],
    this.categoryCustomizations = const [],
    this.transactions = const [],
    this.upcomingExpenses = const [],
    this.plannedCumulativePoints = const [],
    this.savingsGoals = const [],
    this.trackedProducts = const [],
    this.actions = const [],
    this.synoballState,
  });

  final QestoUser user;
  final DateTime referenceDate;
  final List<QestoAccount> accounts;
  final List<BudgetPeriod> budgetPeriods;
  final List<CategoryBudget> categoryBudgets;
  final List<BudgetCategoryCustomization> categoryCustomizations;
  final List<BudgetTransaction> transactions;
  final List<UpcomingExpense> upcomingExpenses;
  final List<BudgetPlanPoint> plannedCumulativePoints;
  final List<SavingsGoal> savingsGoals;
  final List<TrackedProduct> trackedProducts;
  final List<FinancialAction> actions;
  final SynoballState? synoballState;

  UserFinancialData copyWith({
    QestoUser? user,
    DateTime? referenceDate,
    List<QestoAccount>? accounts,
    List<BudgetPeriod>? budgetPeriods,
    List<CategoryBudget>? categoryBudgets,
    List<BudgetCategoryCustomization>? categoryCustomizations,
    List<BudgetTransaction>? transactions,
    List<UpcomingExpense>? upcomingExpenses,
    List<BudgetPlanPoint>? plannedCumulativePoints,
    List<SavingsGoal>? savingsGoals,
    List<TrackedProduct>? trackedProducts,
    List<FinancialAction>? actions,
    SynoballState? synoballState,
  }) {
    return UserFinancialData(
      user: user ?? this.user,
      referenceDate: referenceDate ?? this.referenceDate,
      accounts: accounts ?? this.accounts,
      budgetPeriods: budgetPeriods ?? this.budgetPeriods,
      categoryBudgets: categoryBudgets ?? this.categoryBudgets,
      categoryCustomizations:
          categoryCustomizations ?? this.categoryCustomizations,
      transactions: transactions ?? this.transactions,
      upcomingExpenses: upcomingExpenses ?? this.upcomingExpenses,
      plannedCumulativePoints:
          plannedCumulativePoints ?? this.plannedCumulativePoints,
      savingsGoals: savingsGoals ?? this.savingsGoals,
      trackedProducts: trackedProducts ?? this.trackedProducts,
      actions: actions ?? this.actions,
      synoballState: synoballState ?? this.synoballState,
    );
  }
}
