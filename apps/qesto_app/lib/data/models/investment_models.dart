enum InvestmentAccountType { brokerage, iis, pension, crypto, other }

enum InvestmentAccountStatus { active, closed, archived }

enum InvestmentDataSource {
  manual,
  api,
  brokerStatement,
  calculated,
  transaction,
}

enum InvestmentContributionType { contribution, withdrawal }

enum InvestmentPlanFrequency { monthly }

class InvestmentPlan {
  const InvestmentPlan({
    required this.amount,
    this.frequency = InvestmentPlanFrequency.monthly,
    this.preferredDay,
    this.enabled = true,
    this.reminderEnabled = false,
  });

  final int amount;
  final InvestmentPlanFrequency frequency;
  final int? preferredDay;
  final bool enabled;
  final bool reminderEnabled;
}

/// Qesto-owned metadata layered over a canonical Synoball account.
///
/// The canonical account remains the source of truth for the current balance;
/// this model adds investment-specific lifecycle, provenance and freshness.
class InvestmentAccount {
  const InvestmentAccount({
    required this.id,
    required this.userId,
    required this.linkedAccountId,
    required this.name,
    required this.type,
    required this.currency,
    required this.currentBalance,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.lastBalanceUpdateAt,
    this.brokerName,
    this.openedAt,
    this.comment,
    this.includeInTotal = true,
    this.externalAccountId,
    this.institutionId,
    this.lastSyncAt,
    this.plan,
  });

  final String id;
  final String userId;
  final String linkedAccountId;
  final String name;
  final String? brokerName;
  final InvestmentAccountType type;
  final String currency;
  final int currentBalance;
  final DateTime? openedAt;
  final String? comment;
  final bool includeInTotal;
  final InvestmentAccountStatus status;
  final InvestmentDataSource source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastBalanceUpdateAt;
  final String? externalAccountId;
  final String? institutionId;
  final DateTime? lastSyncAt;
  final InvestmentPlan? plan;

  bool get isActive => status == InvestmentAccountStatus.active;

  InvestmentAccount copyWith({
    String? name,
    String? brokerName,
    InvestmentAccountType? type,
    String? currency,
    int? currentBalance,
    DateTime? openedAt,
    String? comment,
    bool? includeInTotal,
    InvestmentAccountStatus? status,
    InvestmentDataSource? source,
    DateTime? updatedAt,
    DateTime? lastBalanceUpdateAt,
    String? externalAccountId,
    String? institutionId,
    DateTime? lastSyncAt,
    InvestmentPlan? plan,
    bool clearBrokerName = false,
    bool clearOpenedAt = false,
    bool clearComment = false,
    bool clearExternalAccountId = false,
    bool clearInstitutionId = false,
    bool clearLastSyncAt = false,
    bool clearPlan = false,
  }) => InvestmentAccount(
    id: id,
    userId: userId,
    linkedAccountId: linkedAccountId,
    name: name ?? this.name,
    brokerName: clearBrokerName ? null : brokerName ?? this.brokerName,
    type: type ?? this.type,
    currency: currency ?? this.currency,
    currentBalance: currentBalance ?? this.currentBalance,
    openedAt: clearOpenedAt ? null : openedAt ?? this.openedAt,
    comment: clearComment ? null : comment ?? this.comment,
    includeInTotal: includeInTotal ?? this.includeInTotal,
    status: status ?? this.status,
    source: source ?? this.source,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastBalanceUpdateAt: lastBalanceUpdateAt ?? this.lastBalanceUpdateAt,
    externalAccountId: clearExternalAccountId
        ? null
        : externalAccountId ?? this.externalAccountId,
    institutionId: clearInstitutionId
        ? null
        : institutionId ?? this.institutionId,
    lastSyncAt: clearLastSyncAt ? null : lastSyncAt ?? this.lastSyncAt,
    plan: clearPlan ? null : plan ?? this.plan,
  );
}

class InvestmentBalanceSnapshot {
  const InvestmentBalanceSnapshot({
    required this.id,
    required this.investmentAccountId,
    required this.date,
    required this.balance,
    required this.currency,
    required this.source,
    required this.createdAt,
    this.balanceBaseCurrency,
  });

  final String id;
  final String investmentAccountId;
  final DateTime date;
  final int balance;
  final String currency;
  final int? balanceBaseCurrency;
  final InvestmentDataSource source;
  final DateTime createdAt;
}

class InvestmentContribution {
  const InvestmentContribution({
    required this.id,
    required this.investmentAccountId,
    required this.date,
    required this.amount,
    required this.currency,
    required this.type,
    required this.source,
    required this.createdAt,
    this.transactionId,
    this.comment,
  });

  final String id;
  final String investmentAccountId;
  final String? transactionId;
  final DateTime date;
  final int amount;
  final String currency;
  final InvestmentContributionType type;
  final InvestmentDataSource source;
  final DateTime createdAt;
  final String? comment;
}
