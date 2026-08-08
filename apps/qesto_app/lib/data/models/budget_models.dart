enum BudgetPeriodType { calendarMonth, salaryCycle, custom }

enum TransactionType {
  expense,
  income,
  transfer,
  refund,
  savingsTransfer,
  investment,
}

enum UpcomingExpenseSource { manual, detectedRecurring, subscription }

class BudgetPeriod {
  const BudgetPeriod({
    required this.id,
    required this.userId,
    required this.startDate,
    required this.endDate,
    required this.type,
    required this.totalPlan,
    required this.currency,
  });

  final String id;
  final String userId;
  final DateTime startDate;
  final DateTime endDate;
  final BudgetPeriodType type;
  final int totalPlan;
  final String currency;

  int get year => startDate.year;
  int get month => startDate.month;
  int get dayCount => endDate.difference(startDate).inDays + 1;

  bool contains(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return !normalized.isBefore(startDate) && !normalized.isAfter(endDate);
  }
}

class BudgetTransaction {
  const BudgetTransaction({
    required this.id,
    required this.userId,
    required this.accountId,
    required this.date,
    required this.amount,
    required this.currency,
    required this.type,
    this.categoryId,
    this.subcategoryId,
    this.merchant,
    this.title,
    this.description,
    this.comment,
    this.isLargePurchase = false,
    this.normalizedMerchant,
    this.isRecurring = false,
    this.isConfirmed = true,
    this.isPotentialDuplicate = false,
    this.classificationConfidence = 1,
    this.originalCategoryId,
    this.tags = const [],
  });

  final String id;
  final String userId;
  final String accountId;
  final DateTime date;
  final int amount;
  final String currency;
  final TransactionType type;
  final String? categoryId;
  final String? subcategoryId;
  final String? merchant;
  final String? title;
  final String? description;
  final String? comment;
  final bool isLargePurchase;
  final String? normalizedMerchant;
  final bool isRecurring;
  final bool isConfirmed;
  final bool isPotentialDuplicate;
  final double classificationConfidence;
  final String? originalCategoryId;
  final List<String> tags;

  BudgetTransaction copyWith({
    String? accountId,
    DateTime? date,
    int? amount,
    TransactionType? type,
    String? categoryId,
    String? subcategoryId,
    String? merchant,
    String? title,
    String? description,
    String? comment,
    bool? isLargePurchase,
    String? normalizedMerchant,
    bool? isRecurring,
    bool? isConfirmed,
    bool? isPotentialDuplicate,
    double? classificationConfidence,
    String? originalCategoryId,
    List<String>? tags,
  }) {
    return BudgetTransaction(
      id: id,
      userId: userId,
      accountId: accountId ?? this.accountId,
      date: date ?? this.date,
      amount: amount ?? this.amount,
      currency: currency,
      type: type ?? this.type,
      categoryId: categoryId ?? this.categoryId,
      subcategoryId: subcategoryId ?? this.subcategoryId,
      merchant: merchant ?? this.merchant,
      title: title ?? this.title,
      description: description ?? this.description,
      comment: comment ?? this.comment,
      isLargePurchase: isLargePurchase ?? this.isLargePurchase,
      normalizedMerchant: normalizedMerchant ?? this.normalizedMerchant,
      isRecurring: isRecurring ?? this.isRecurring,
      isConfirmed: isConfirmed ?? this.isConfirmed,
      isPotentialDuplicate: isPotentialDuplicate ?? this.isPotentialDuplicate,
      classificationConfidence:
          classificationConfidence ?? this.classificationConfidence,
      originalCategoryId: originalCategoryId ?? this.originalCategoryId,
      tags: tags ?? this.tags,
    );
  }
}

class BudgetCategory {
  const BudgetCategory({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.colorValue,
    this.shortName,
    this.subcategories = const [],
  });

  final String id;
  final String name;
  final String iconKey;
  final int colorValue;
  final String? shortName;
  final List<String> subcategories;
}

class CategoryBudget {
  const CategoryBudget({
    required this.id,
    required this.budgetPeriodId,
    required this.categoryId,
    required this.plannedAmount,
  });

  final String id;
  final String budgetPeriodId;
  final String categoryId;
  final int plannedAmount;
}

class BudgetPlanPoint {
  const BudgetPlanPoint({
    required this.budgetPeriodId,
    required this.date,
    required this.cumulativePlannedAmount,
  });

  final String budgetPeriodId;
  final DateTime date;
  final int cumulativePlannedAmount;
}

class UpcomingExpense {
  const UpcomingExpense({
    required this.id,
    required this.userId,
    required this.budgetPeriodId,
    required this.title,
    required this.amount,
    required this.currency,
    required this.plannedDate,
    required this.source,
    this.categoryId,
    this.accountId,
    this.isRecurring = false,
    this.recurrenceRule,
    this.isCancelled = false,
  });

  final String id;
  final String userId;
  final String budgetPeriodId;
  final String title;
  final int amount;
  final String currency;
  final DateTime plannedDate;
  final String? categoryId;
  final String? accountId;
  final bool isRecurring;
  final String? recurrenceRule;
  final UpcomingExpenseSource source;
  final bool isCancelled;

  UpcomingExpense copyWith({
    String? title,
    int? amount,
    DateTime? plannedDate,
    String? categoryId,
    String? accountId,
    bool? isRecurring,
    String? recurrenceRule,
    UpcomingExpenseSource? source,
    bool? isCancelled,
  }) {
    return UpcomingExpense(
      id: id,
      userId: userId,
      budgetPeriodId: budgetPeriodId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      currency: currency,
      plannedDate: plannedDate ?? this.plannedDate,
      categoryId: categoryId ?? this.categoryId,
      accountId: accountId ?? this.accountId,
      isRecurring: isRecurring ?? this.isRecurring,
      recurrenceRule: recurrenceRule ?? this.recurrenceRule,
      source: source ?? this.source,
      isCancelled: isCancelled ?? this.isCancelled,
    );
  }
}

class BudgetConfiguration {
  const BudgetConfiguration({required this.categories});

  final List<BudgetCategory> categories;
}

class SpendingCategory {
  const SpendingCategory({
    required this.id,
    required this.name,
    required this.amount,
    required this.colorValue,
    this.iconKey,
  });

  final String id;
  final String name;
  final int amount;
  final int colorValue;
  final String? iconKey;
}

class BudgetSummary {
  const BudgetSummary({
    required this.period,
    required this.currentExpense,
    required this.categories,
  });

  final BudgetPeriod period;
  final int currentExpense;
  final List<SpendingCategory> categories;

  double get progress =>
      period.totalPlan == 0 ? 0 : currentExpense / period.totalPlan;
  int get remainingAmount => period.totalPlan - currentExpense;
  bool get isEmpty => currentExpense == 0 && categories.isEmpty;
}

class DailyBudgetPoint {
  const DailyBudgetPoint({required this.date, required this.amount});

  final DateTime date;
  final double amount;
}

enum BudgetForecastState { underPlan, projectedOverLimit, exceeded, noForecast }

class BudgetForecast {
  const BudgetForecast({
    required this.state,
    required this.actualPoints,
    required this.projectedPoints,
    required this.targetPoints,
    required this.totalPlan,
    this.crossingDate,
  });

  final BudgetForecastState state;
  final List<DailyBudgetPoint> actualPoints;
  final List<DailyBudgetPoint> projectedPoints;
  final List<DailyBudgetPoint> targetPoints;
  final int totalPlan;
  final DateTime? crossingDate;
}
