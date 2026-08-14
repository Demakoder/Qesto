import '../core/models.dart';
import '../ingestion/adapter.dart';

class TransactionSeed {
  const TransactionSeed({
    required this.accountId,
    required this.amount,
    required this.direction,
    required this.occurredAt,
    required this.description,
    required this.confidence,
    this.canonicalId,
    this.merchant,
    this.providerCategory,
    this.category,
    this.userCategoryOverride,
    this.subcategoryId,
    this.providerTransactionId,
    this.receiptId,
    this.transferDirection,
    this.tags = const [],
    this.requiresConfirmation = false,
  });

  final String? canonicalId;
  final String accountId;
  final Money amount;
  final FinancialDirection direction;
  final DateTime occurredAt;
  final String description;
  final String? merchant;
  final String? providerCategory;
  final String? category;
  final String? userCategoryOverride;
  final String? subcategoryId;
  final String? providerTransactionId;
  final String? receiptId;
  final String? transferDirection;
  final List<String> tags;
  final double confidence;
  final bool requiresConfirmation;
}

class ManualInput extends AdapterInputBase {
  const ManualInput({
    required super.entityId,
    required super.receivedAt,
    required super.rawPayload,
    required this.transaction,
  });

  final TransactionSeed transaction;
}

class VoiceInput extends AdapterInputBase {
  const VoiceInput({
    required super.entityId,
    required super.receivedAt,
    required super.rawPayload,
    required this.transcript,
    required this.transaction,
    this.userCorrections = const {},
  });

  final String transcript;
  final TransactionSeed transaction;
  final Map<String, String> userCorrections;
}

class AndroidNotificationInput extends AdapterInputBase {
  const AndroidNotificationInput({
    required super.entityId,
    required super.receivedAt,
    required super.rawPayload,
    required this.notificationKey,
    required this.packageName,
    required this.transaction,
    super.connectionId,
    super.institutionId,
  });

  final String notificationKey;
  final String packageName;
  final TransactionSeed transaction;
}

class ReceiptInput extends AdapterInputBase {
  const ReceiptInput({
    required super.entityId,
    required super.receivedAt,
    required super.rawPayload,
    required this.transaction,
    required this.fiscalFingerprint,
    required this.rawText,
    this.merchant,
    this.items = const [],
    this.confidence = 1,
    this.userCorrections = const {},
  });

  final TransactionSeed transaction;
  final String fiscalFingerprint;
  final String rawText;
  final String? merchant;
  final List<ReceiptItem> items;
  final double confidence;
  final Map<String, String> userCorrections;
}

class StatementInput extends AdapterInputBase {
  const StatementInput({
    required super.entityId,
    required super.receivedAt,
    required super.rawPayload,
    required this.batchName,
    required this.transactions,
    required this.account,
    super.institutionId,
  });

  final String batchName;
  final List<TransactionSeed> transactions;
  final SynoballAccount account;
}

class LegacyInput extends AdapterInputBase {
  const LegacyInput({
    required super.entityId,
    required super.receivedAt,
    required super.rawPayload,
    required this.entity,
    required this.accounts,
    required this.transactions,
    this.receipts = const [],
  });

  final SynoballEntity entity;
  final List<SynoballAccount> accounts;
  final List<TransactionSeed> transactions;
  final List<LegacyReceiptSeed> receipts;
}

class LegacyReceiptSeed {
  const LegacyReceiptSeed({
    required this.id,
    required this.purchasedAt,
    required this.total,
    required this.fiscalFingerprint,
    required this.rawText,
    this.merchant,
    this.items = const [],
  });

  final String id;
  final DateTime purchasedAt;
  final Money total;
  final String fiscalFingerprint;
  final String rawText;
  final String? merchant;
  final List<ReceiptItem> items;
}

class CbrOpenFinanceInput extends AdapterInputBase {
  CbrOpenFinanceInput({
    required super.entityId,
    required super.receivedAt,
    required super.rawPayload,
    required this.connection,
    required this.institution,
    required this.consent,
    required this.accounts,
    required this.transactions,
  }) : super(connectionId: connection.id, institutionId: institution.id);

  final SynoballConnection connection;
  final Institution institution;
  final SynoballConsent consent;
  final List<SynoballAccount> accounts;
  final List<TransactionSeed> transactions;
}
