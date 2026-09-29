export 'budget_models.dart';
export 'classification_settings.dart';
export 'debt_models.dart';
export 'investment_models.dart';

import 'budget_models.dart';
import 'classification_settings.dart';
import 'debt_models.dart';
import 'investment_models.dart';
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

enum QestoAccountRole {
  everyday,
  emergency,
  savings,
  salary,
  mandatoryPayments,
  other,
}

/// User-owned account metadata. It intentionally lives outside Synoball:
/// changing how Qesto presents or analyses an account must not mutate the
/// canonical bank account received from an adapter.
class QestoAccountPreferences {
  const QestoAccountPreferences({
    required this.accountId,
    required this.role,
    this.includeInTotal = true,
    this.includeInNetWorth = true,
    this.includeInEmergencyFund = false,
    this.isVisible = true,
    this.includeTransactionsInAnalytics = true,
    this.isClosed = false,
  });

  final String accountId;
  final QestoAccountRole role;
  final bool includeInTotal;
  final bool includeInNetWorth;
  final bool includeInEmergencyFund;
  final bool isVisible;
  final bool includeTransactionsInAnalytics;
  final bool isClosed;

  QestoAccountPreferences copyWith({
    QestoAccountRole? role,
    bool? includeInTotal,
    bool? includeInNetWorth,
    bool? includeInEmergencyFund,
    bool? isVisible,
    bool? includeTransactionsInAnalytics,
    bool? isClosed,
  }) => QestoAccountPreferences(
    accountId: accountId,
    role: role ?? this.role,
    includeInTotal: includeInTotal ?? this.includeInTotal,
    includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
    includeInEmergencyFund:
        includeInEmergencyFund ?? this.includeInEmergencyFund,
    isVisible: isVisible ?? this.isVisible,
    includeTransactionsInAnalytics:
        includeTransactionsInAnalytics ?? this.includeTransactionsInAnalytics,
    isClosed: isClosed ?? this.isClosed,
  );
}

enum DealKind { coupon, promotion }

enum FinancialActionType { statementImport, transactionAdded }

class QestoUser {
  const QestoUser({
    required this.id,
    required this.name,
    required this.defaultCurrency,
    this.avatarUrl,
    this.expenseDisplayCurrency = 'RUB',
  });

  final String id;
  final String name;
  final String defaultCurrency;
  final String? avatarUrl;
  final String expenseDisplayCurrency;

  QestoUser copyWith({
    String? name,
    String? defaultCurrency,
    String? avatarUrl,
    String? expenseDisplayCurrency,
    bool clearAvatar = false,
  }) => QestoUser(
    id: id,
    name: name ?? this.name,
    defaultCurrency: defaultCurrency ?? this.defaultCurrency,
    avatarUrl: clearAvatar ? null : avatarUrl ?? this.avatarUrl,
    expenseDisplayCurrency:
        expenseDisplayCurrency ?? this.expenseDisplayCurrency,
  );
}

class QestoAccount {
  const QestoAccount({
    required this.id,
    required this.userId,
    required this.title,
    required this.balance,
    this.exactBalanceMinor,
    required this.currency,
    required this.type,
  });

  final String id;
  final String userId;
  final String title;
  final int balance;
  final int? exactBalanceMinor;
  int get balanceMinor => exactBalanceMinor ?? balance * 100;
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

enum GoalType { targetAmountDate, targetAmount, recurringSaving, reserve }

enum GoalPriority { low, medium, high }

enum GoalStatus { active, funded, spending, completed, paused, archived }

enum GoalReminderCadence { monthly, weekly }

class GoalReminder {
  const GoalReminder({
    required this.enabled,
    required this.amount,
    required this.day,
    this.cadence = GoalReminderCadence.monthly,
  });

  final bool enabled;
  final int amount;
  final int day;
  final GoalReminderCadence cadence;
}

enum GoalAllocationSourceType { account, investmentAccount, manualAsset }

enum GoalContributionSource {
  manual,
  transaction,
  accountAllocation,
  automatic,
}

enum GoalContributionType { contribution, withdrawal }

enum GoalHistoryEventType {
  created,
  targetChanged,
  targetDateChanged,
  statusChanged,
  allocationChanged,
  funded,
  completed,
}

class GoalContribution {
  const GoalContribution({
    required this.id,
    required this.goalId,
    required this.date,
    required this.amount,
    required this.currency,
    required this.type,
    required this.source,
    required this.createdAt,
    this.transactionId,
    this.accountId,
    this.comment,
  });

  final String id;
  final String goalId;
  final DateTime date;
  final int amount;
  final String currency;
  final GoalContributionType type;
  final GoalContributionSource source;
  final DateTime createdAt;
  final String? transactionId;
  final String? accountId;
  final String? comment;
}

class GoalHistoryEvent {
  const GoalHistoryEvent({
    required this.id,
    required this.goalId,
    required this.type,
    required this.date,
    required this.description,
    this.amount,
  });

  final String id;
  final String goalId;
  final GoalHistoryEventType type;
  final DateTime date;
  final String description;
  final int? amount;
}

class GoalAllocation {
  const GoalAllocation({
    required this.id,
    required this.goalId,
    required this.sourceType,
    required this.sourceId,
    required this.allocatedAmount,
    required this.currency,
    required this.updatedAt,
  });

  final String id;
  final String goalId;
  final GoalAllocationSourceType sourceType;
  final String sourceId;
  final int allocatedAmount;
  final String currency;
  final DateTime updatedAt;
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
    this.category = 'Другое',
    this.type = GoalType.targetAmount,
    this.targetDate,
    this.iconKey = 'flag',
    this.colorValue,
    this.comment,
    this.desiredMonthlyContribution,
    this.priority = GoalPriority.medium,
    this.status = GoalStatus.active,
    this.reminder,
    this.createdAt,
    this.fundedAt,
    this.completedAt,
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
  final String category;
  final GoalType type;
  final DateTime? targetDate;
  final String iconKey;
  final int? colorValue;
  final String? comment;
  final int? desiredMonthlyContribution;
  final GoalPriority priority;
  final GoalStatus status;
  final GoalReminder? reminder;
  final DateTime? createdAt;
  final DateTime? fundedAt;
  final DateTime? completedAt;

  double get progress => targetAmount == 0 ? 0 : savedAmount / targetAmount;
  GoalStatus get effectiveStatus {
    if (status == GoalStatus.archived) return GoalStatus.archived;
    if (status == GoalStatus.completed) return GoalStatus.completed;
    if (status == GoalStatus.spending) return GoalStatus.spending;
    if (targetAmount > 0 && savedAmount >= targetAmount) {
      return GoalStatus.funded;
    }
    if (status == GoalStatus.paused || !isActive) return GoalStatus.paused;
    return status;
  }

  SavingsGoal copyWith({
    String? title,
    int? targetAmount,
    int? savedAmount,
    String? currency,
    int? streakWeeks,
    bool? isActive,
    List<SavingsHistoryPoint>? history,
    String? category,
    GoalType? type,
    DateTime? targetDate,
    String? iconKey,
    int? colorValue,
    String? comment,
    int? desiredMonthlyContribution,
    GoalPriority? priority,
    GoalStatus? status,
    GoalReminder? reminder,
    DateTime? createdAt,
    DateTime? fundedAt,
    DateTime? completedAt,
    bool clearTargetDate = false,
    bool clearDesiredMonthlyContribution = false,
    bool clearReminder = false,
    bool clearComment = false,
    bool clearFundedAt = false,
    bool clearCompletedAt = false,
  }) => SavingsGoal(
    id: id,
    userId: userId,
    title: title ?? this.title,
    targetAmount: targetAmount ?? this.targetAmount,
    savedAmount: savedAmount ?? this.savedAmount,
    currency: currency ?? this.currency,
    streakWeeks: streakWeeks ?? this.streakWeeks,
    isActive: isActive ?? this.isActive,
    history: history ?? this.history,
    category: category ?? this.category,
    type: type ?? this.type,
    targetDate: clearTargetDate ? null : targetDate ?? this.targetDate,
    iconKey: iconKey ?? this.iconKey,
    colorValue: colorValue ?? this.colorValue,
    comment: clearComment ? null : comment ?? this.comment,
    desiredMonthlyContribution: clearDesiredMonthlyContribution
        ? null
        : desiredMonthlyContribution ?? this.desiredMonthlyContribution,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    reminder: clearReminder ? null : reminder ?? this.reminder,
    createdAt: createdAt ?? this.createdAt,
    fundedAt: clearFundedAt ? null : fundedAt ?? this.fundedAt,
    completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
  );
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
    this.accountPreferences = const [],
    this.budgetPeriods = const [],
    this.categoryBudgets = const [],
    this.categoryCustomizations = const [],
    this.classification = const ClassificationSettings(),
    this.transactions = const [],
    this.upcomingExpenses = const [],
    this.plannedCumulativePoints = const [],
    this.savingsGoals = const [],
    this.goalAllocations = const [],
    this.goalContributions = const [],
    this.goalHistoryEvents = const [],
    this.investmentAccounts = const [],
    this.investmentBalanceSnapshots = const [],
    this.investmentContributions = const [],
    this.debts = const [],
    this.debtBalanceSnapshots = const [],
    this.debtPayments = const [],
    this.trackedProducts = const [],
    this.actions = const [],
    this.synoballState,
  });

  final QestoUser user;
  final DateTime referenceDate;
  final List<QestoAccount> accounts;
  final List<QestoAccountPreferences> accountPreferences;
  final List<BudgetPeriod> budgetPeriods;
  final List<CategoryBudget> categoryBudgets;
  final List<BudgetCategoryCustomization> categoryCustomizations;
  final ClassificationSettings classification;
  final List<BudgetTransaction> transactions;
  final List<UpcomingExpense> upcomingExpenses;
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
  final List<TrackedProduct> trackedProducts;
  final List<FinancialAction> actions;
  final SynoballState? synoballState;

  UserFinancialData copyWith({
    QestoUser? user,
    DateTime? referenceDate,
    List<QestoAccount>? accounts,
    List<QestoAccountPreferences>? accountPreferences,
    List<BudgetPeriod>? budgetPeriods,
    List<CategoryBudget>? categoryBudgets,
    List<BudgetCategoryCustomization>? categoryCustomizations,
    ClassificationSettings? classification,
    List<BudgetTransaction>? transactions,
    List<UpcomingExpense>? upcomingExpenses,
    List<BudgetPlanPoint>? plannedCumulativePoints,
    List<SavingsGoal>? savingsGoals,
    List<GoalAllocation>? goalAllocations,
    List<GoalContribution>? goalContributions,
    List<GoalHistoryEvent>? goalHistoryEvents,
    List<InvestmentAccount>? investmentAccounts,
    List<InvestmentBalanceSnapshot>? investmentBalanceSnapshots,
    List<InvestmentContribution>? investmentContributions,
    List<DebtAccount>? debts,
    List<DebtBalanceSnapshot>? debtBalanceSnapshots,
    List<DebtPayment>? debtPayments,
    List<TrackedProduct>? trackedProducts,
    List<FinancialAction>? actions,
    SynoballState? synoballState,
  }) {
    return UserFinancialData(
      user: user ?? this.user,
      referenceDate: referenceDate ?? this.referenceDate,
      accounts: accounts ?? this.accounts,
      accountPreferences: accountPreferences ?? this.accountPreferences,
      budgetPeriods: budgetPeriods ?? this.budgetPeriods,
      categoryBudgets: categoryBudgets ?? this.categoryBudgets,
      categoryCustomizations:
          categoryCustomizations ?? this.categoryCustomizations,
      classification: classification ?? this.classification,
      transactions: transactions ?? this.transactions,
      upcomingExpenses: upcomingExpenses ?? this.upcomingExpenses,
      plannedCumulativePoints:
          plannedCumulativePoints ?? this.plannedCumulativePoints,
      savingsGoals: savingsGoals ?? this.savingsGoals,
      goalAllocations: goalAllocations ?? this.goalAllocations,
      goalContributions: goalContributions ?? this.goalContributions,
      goalHistoryEvents: goalHistoryEvents ?? this.goalHistoryEvents,
      investmentAccounts: investmentAccounts ?? this.investmentAccounts,
      investmentBalanceSnapshots:
          investmentBalanceSnapshots ?? this.investmentBalanceSnapshots,
      investmentContributions:
          investmentContributions ?? this.investmentContributions,
      debts: debts ?? this.debts,
      debtBalanceSnapshots: debtBalanceSnapshots ?? this.debtBalanceSnapshots,
      debtPayments: debtPayments ?? this.debtPayments,
      trackedProducts: trackedProducts ?? this.trackedProducts,
      actions: actions ?? this.actions,
      synoballState: synoballState ?? this.synoballState,
    );
  }
}
