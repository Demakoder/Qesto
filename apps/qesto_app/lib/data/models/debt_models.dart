enum DebtType {
  mortgage,
  personalLoan,
  creditCard,
  autoLoan,
  installment,
  other,
}

enum DebtPaymentType { annuity, differentiated, unknown }

enum DebtStatus { active, paidOff, closed, archived }

enum DebtSource { bank, statement, manual, calculated, api }

enum DebtDataQuality { verified, estimated, manual, stale, incomplete }

class CreditCardDebtDetails {
  const CreditCardDebtDetails({
    this.creditLimit,
    this.minimumPayment,
    this.gracePaymentAmount,
    this.graceDeadline,
    this.gracePeriodEnd,
    this.interestRateAfterGrace,
  });

  final int? creditLimit;
  final int? minimumPayment;
  final int? gracePaymentAmount;
  final DateTime? graceDeadline;
  final DateTime? gracePeriodEnd;
  final double? interestRateAfterGrace;

  int? availableCredit(int currentDebt) => creditLimit == null
      ? null
      : (creditLimit! - currentDebt).clamp(0, creditLimit!).toInt();

  double? utilization(int currentDebt) =>
      creditLimit == null || creditLimit == 0
      ? null
      : currentDebt / creditLimit!;
}

class DebtAccount {
  const DebtAccount({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.currency,
    required this.currentBalance,
    required this.status,
    required this.source,
    required this.dataQuality,
    required this.confidence,
    required this.createdAt,
    required this.updatedAt,
    this.institutionId,
    this.institutionName,
    this.linkedAccountId,
    this.originalPrincipal,
    this.currentPrincipal,
    this.accruedInterest,
    this.interestRate,
    this.effectiveRate,
    this.monthlyPayment,
    this.paymentDay,
    this.nextPaymentDate,
    this.startDate,
    this.plannedEndDate,
    this.paymentType = DebtPaymentType.unknown,
    this.creditCardDetails,
  });

  final String id;
  final String userId;
  final String name;
  final DebtType type;
  final String currency;
  final int currentBalance;
  final DebtStatus status;
  final DebtSource source;
  final DebtDataQuality dataQuality;
  final double confidence;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? institutionId;
  final String? institutionName;
  final String? linkedAccountId;
  final int? originalPrincipal;
  final int? currentPrincipal;
  final int? accruedInterest;
  final double? interestRate;
  final double? effectiveRate;
  final int? monthlyPayment;
  final int? paymentDay;
  final DateTime? nextPaymentDate;
  final DateTime? startDate;
  final DateTime? plannedEndDate;
  final DebtPaymentType paymentType;
  final CreditCardDebtDetails? creditCardDetails;

  bool get isOpen => status == DebtStatus.active;

  DebtAccount copyWith({
    String? name,
    DebtType? type,
    String? currency,
    int? currentBalance,
    DebtStatus? status,
    DebtSource? source,
    DebtDataQuality? dataQuality,
    double? confidence,
    DateTime? updatedAt,
    String? institutionId,
    String? institutionName,
    String? linkedAccountId,
    int? originalPrincipal,
    int? currentPrincipal,
    int? accruedInterest,
    double? interestRate,
    double? effectiveRate,
    int? monthlyPayment,
    int? paymentDay,
    DateTime? nextPaymentDate,
    DateTime? startDate,
    DateTime? plannedEndDate,
    DebtPaymentType? paymentType,
    CreditCardDebtDetails? creditCardDetails,
  }) => DebtAccount(
    id: id,
    userId: userId,
    name: name ?? this.name,
    type: type ?? this.type,
    currency: currency ?? this.currency,
    currentBalance: currentBalance ?? this.currentBalance,
    status: status ?? this.status,
    source: source ?? this.source,
    dataQuality: dataQuality ?? this.dataQuality,
    confidence: confidence ?? this.confidence,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    institutionId: institutionId ?? this.institutionId,
    institutionName: institutionName ?? this.institutionName,
    linkedAccountId: linkedAccountId ?? this.linkedAccountId,
    originalPrincipal: originalPrincipal ?? this.originalPrincipal,
    currentPrincipal: currentPrincipal ?? this.currentPrincipal,
    accruedInterest: accruedInterest ?? this.accruedInterest,
    interestRate: interestRate ?? this.interestRate,
    effectiveRate: effectiveRate ?? this.effectiveRate,
    monthlyPayment: monthlyPayment ?? this.monthlyPayment,
    paymentDay: paymentDay ?? this.paymentDay,
    nextPaymentDate: nextPaymentDate ?? this.nextPaymentDate,
    startDate: startDate ?? this.startDate,
    plannedEndDate: plannedEndDate ?? this.plannedEndDate,
    paymentType: paymentType ?? this.paymentType,
    creditCardDetails: creditCardDetails ?? this.creditCardDetails,
  );
}

class DebtBalanceSnapshot {
  const DebtBalanceSnapshot({
    required this.id,
    required this.debtId,
    required this.date,
    required this.totalBalance,
    required this.source,
    required this.confidence,
    this.principalBalance,
    this.accruedInterest,
  });

  final String id;
  final String debtId;
  final DateTime date;
  final int totalBalance;
  final int? principalBalance;
  final int? accruedInterest;
  final DebtSource source;
  final double confidence;
}

class DebtPayment {
  const DebtPayment({
    required this.id,
    required this.debtId,
    required this.date,
    required this.amount,
    required this.currency,
    required this.source,
    required this.confidence,
    this.transactionId,
    this.principalAmount,
    this.interestAmount,
    this.feeAmount,
  });

  final String id;
  final String debtId;
  final String? transactionId;
  final DateTime date;
  final int amount;
  final String currency;
  final int? principalAmount;
  final int? interestAmount;
  final int? feeAmount;
  final DebtSource source;
  final double confidence;
}
