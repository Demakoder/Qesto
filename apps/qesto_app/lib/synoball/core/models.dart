enum SynoballEntityType { person, business }

enum SynoballAccountType {
  checking,
  card,
  savings,
  deposit,
  credit,
  loan,
  brokerage,
  investment,
  cash,
  wallet,
  other,
}

enum FinancialDirection { inflow, outflow, neutral }

enum FinancialEventType { observed, inferred, expected }

enum CanonicalTransactionStatus { pending, posted, reversed, deleted }

enum IngestionStatus {
  received,
  parsed,
  normalized,
  reconciled,
  completed,
  needsReview,
  failed,
}

enum CandidateStatus { pending, confirmed, merged, rejected }

enum SynoballSourceType {
  legacy,
  manual,
  manualVoice,
  androidNotification,
  receipt,
  statement,
  regulatedApi,
  directApi,
  modelInference,
}

enum SourceTrustLevel {
  modelInference,
  androidNotification,
  receipt,
  bankStatement,
  directApi,
  regulatedApi,
  userConfirmed,
}

enum ConnectionStatus { active, degraded, disconnected, revoked }

enum ConsentStatus { active, expired, revoked }

enum SynoballCapability {
  accounts,
  balances,
  transactions,
  investments,
  loans,
  insurance,
  identity,
}

enum ImportBatchStatus { processing, partial, completed, failed }

enum RecurrenceFrequency { weekly, monthly, quarterly, yearly, irregular }

enum SynoballErrorCode {
  consentExpired,
  sourceUnavailable,
  invalidData,
  syncFailed,
  partialSync,
  unsupportedCapability,
  authRequired,
}

class Money {
  const Money({required this.minorUnits, required this.currency});

  final int minorUnits;
  final String currency;

  String get value {
    final absolute = minorUnits.abs();
    final major = absolute ~/ 100;
    final minor = (absolute % 100).toString().padLeft(2, '0');
    return '${minorUnits < 0 ? '-' : ''}$major.$minor';
  }

  Map<String, dynamic> toJson() => {'value': value, 'currency': currency};

  factory Money.fromJson(Map<String, dynamic> json) {
    final value = json['value'] as String;
    final negative = value.startsWith('-');
    final parts = value.replaceFirst('-', '').split('.');
    final major = int.parse(parts.first);
    final fraction = (parts.length == 1 ? '' : parts[1]).padRight(2, '0');
    final minor = int.parse(fraction.substring(0, 2));
    final units = major * 100 + minor;
    return Money(
      minorUnits: negative ? -units : units,
      currency: json['currency'] as String,
    );
  }
}

class SynoballEntity {
  const SynoballEntity({
    required this.id,
    required this.type,
    required this.displayName,
  });

  final String id;
  final SynoballEntityType type;
  final String displayName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'displayName': displayName,
  };

  factory SynoballEntity.fromJson(Map<String, dynamic> json) => SynoballEntity(
    id: json['id'] as String,
    type: SynoballEntityType.values.byName(json['type'] as String),
    displayName: json['displayName'] as String,
  );
}

class Institution {
  const Institution({
    required this.id,
    required this.name,
    required this.countryCode,
  });

  final String id;
  final String name;
  final String countryCode;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'countryCode': countryCode,
  };

  factory Institution.fromJson(Map<String, dynamic> json) => Institution(
    id: json['id'] as String,
    name: json['name'] as String,
    countryCode: json['countryCode'] as String,
  );
}

class SynoballConsent {
  const SynoballConsent({
    required this.id,
    required this.entityId,
    required this.connectionId,
    required this.status,
    required this.scopes,
    required this.purpose,
    required this.grantedAt,
    required this.jurisdiction,
    this.expiresAt,
    this.revokedAt,
    this.externalConsentId,
  });

  final String id;
  final String entityId;
  final String connectionId;
  final ConsentStatus status;
  final List<String> scopes;
  final String purpose;
  final DateTime grantedAt;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final String jurisdiction;
  final String? externalConsentId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityId': entityId,
    'connectionId': connectionId,
    'status': status.name,
    'scopes': scopes,
    'purpose': purpose,
    'grantedAt': grantedAt.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'revokedAt': revokedAt?.toIso8601String(),
    'jurisdiction': jurisdiction,
    'externalConsentId': externalConsentId,
  };

  factory SynoballConsent.fromJson(Map<String, dynamic> json) =>
      SynoballConsent(
        id: json['id'] as String,
        entityId: json['entityId'] as String,
        connectionId: json['connectionId'] as String,
        status: ConsentStatus.values.byName(json['status'] as String),
        scopes: _strings(json['scopes']),
        purpose: json['purpose'] as String,
        grantedAt: DateTime.parse(json['grantedAt'] as String),
        expiresAt: _date(json['expiresAt']),
        revokedAt: _date(json['revokedAt']),
        jurisdiction: json['jurisdiction'] as String,
        externalConsentId: json['externalConsentId'] as String?,
      );
}

class SynoballConnection {
  const SynoballConnection({
    required this.id,
    required this.entityId,
    required this.status,
    required this.method,
    required this.capabilities,
    required this.adapterId,
    required this.adapterVersion,
    this.institutionId,
    this.consentId,
    this.lastSyncedAt,
    this.syncCursor,
    this.lastErrorCode,
    this.providerError,
  });

  final String id;
  final String entityId;
  final ConnectionStatus status;
  final String method;
  final String? institutionId;
  final List<SynoballCapability> capabilities;
  final String? consentId;
  final String adapterId;
  final String adapterVersion;
  final DateTime? lastSyncedAt;
  final String? syncCursor;
  final SynoballErrorCode? lastErrorCode;
  final String? providerError;

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityId': entityId,
    'status': status.name,
    'method': method,
    'institutionId': institutionId,
    'capabilities': capabilities.map((value) => value.name).toList(),
    'consentId': consentId,
    'adapterId': adapterId,
    'adapterVersion': adapterVersion,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    'syncCursor': syncCursor,
    'lastErrorCode': lastErrorCode?.name,
    'providerError': providerError,
  };

  factory SynoballConnection.fromJson(Map<String, dynamic> json) =>
      SynoballConnection(
        id: json['id'] as String,
        entityId: json['entityId'] as String,
        status: ConnectionStatus.values.byName(json['status'] as String),
        method: json['method'] as String,
        institutionId: json['institutionId'] as String?,
        capabilities: _strings(
          json['capabilities'],
        ).map(SynoballCapability.values.byName).toList(),
        consentId: json['consentId'] as String?,
        adapterId: json['adapterId'] as String,
        adapterVersion: json['adapterVersion'] as String,
        lastSyncedAt: _date(json['lastSyncedAt']),
        syncCursor: json['syncCursor'] as String?,
        lastErrorCode: json['lastErrorCode'] == null
            ? null
            : SynoballErrorCode.values.byName(json['lastErrorCode'] as String),
        providerError: json['providerError'] as String?,
      );
}

class SynoballAccount {
  const SynoballAccount({
    required this.id,
    required this.entityId,
    required this.name,
    required this.type,
    required this.currency,
    required this.balance,
    this.connectionId,
    this.institutionId,
    this.externalId,
    this.isVirtual = false,
  });

  final String id;
  final String entityId;
  final String name;
  final SynoballAccountType type;
  final String currency;
  final Money balance;
  final String? connectionId;
  final String? institutionId;
  final String? externalId;
  final bool isVirtual;

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityId': entityId,
    'name': name,
    'type': type.name,
    'currency': currency,
    'balance': balance.toJson(),
    'connectionId': connectionId,
    'institutionId': institutionId,
    'externalId': externalId,
    'isVirtual': isVirtual,
  };

  factory SynoballAccount.fromJson(Map<String, dynamic> json) =>
      SynoballAccount(
        id: json['id'] as String,
        entityId: json['entityId'] as String,
        name: json['name'] as String,
        type: SynoballAccountType.values.byName(json['type'] as String),
        currency: json['currency'] as String,
        balance: Money.fromJson(_map(json['balance'])),
        connectionId: json['connectionId'] as String?,
        institutionId: json['institutionId'] as String?,
        externalId: json['externalId'] as String?,
        isVirtual: json['isVirtual'] as bool? ?? false,
      );
}

class RawPayload {
  const RawPayload({
    required this.id,
    required this.contentType,
    required this.body,
    required this.createdAt,
    this.redacted = false,
  });

  final String id;
  final String contentType;
  final String body;
  final DateTime createdAt;
  final bool redacted;

  Map<String, dynamic> toJson() => {
    'id': id,
    'contentType': contentType,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    'redacted': redacted,
  };

  factory RawPayload.fromJson(Map<String, dynamic> json) => RawPayload(
    id: json['id'] as String,
    contentType: json['contentType'] as String,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    redacted: json['redacted'] as bool? ?? false,
  );
}

class IngestionRecord {
  const IngestionRecord({
    required this.id,
    required this.entityId,
    required this.sourceType,
    required this.receivedAt,
    required this.rawPayloadId,
    required this.status,
    required this.adapterId,
    required this.adapterVersion,
    this.connectionId,
    this.institutionId,
    this.importBatchId,
    this.errorCode,
    this.errorMessage,
  });

  final String id;
  final String entityId;
  final SynoballSourceType sourceType;
  final String? connectionId;
  final String? institutionId;
  final DateTime receivedAt;
  final String rawPayloadId;
  final IngestionStatus status;
  final String adapterId;
  final String adapterVersion;
  final String? importBatchId;
  final SynoballErrorCode? errorCode;
  final String? errorMessage;

  IngestionRecord copyWith({
    IngestionStatus? status,
    SynoballErrorCode? errorCode,
    String? errorMessage,
  }) => IngestionRecord(
    id: id,
    entityId: entityId,
    sourceType: sourceType,
    connectionId: connectionId,
    institutionId: institutionId,
    receivedAt: receivedAt,
    rawPayloadId: rawPayloadId,
    status: status ?? this.status,
    adapterId: adapterId,
    adapterVersion: adapterVersion,
    importBatchId: importBatchId,
    errorCode: errorCode ?? this.errorCode,
    errorMessage: errorMessage ?? this.errorMessage,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityId': entityId,
    'sourceType': sourceType.name,
    'connectionId': connectionId,
    'institutionId': institutionId,
    'receivedAt': receivedAt.toIso8601String(),
    'rawPayloadId': rawPayloadId,
    'status': status.name,
    'adapterId': adapterId,
    'adapterVersion': adapterVersion,
    'importBatchId': importBatchId,
    'errorCode': errorCode?.name,
    'errorMessage': errorMessage,
  };

  factory IngestionRecord.fromJson(Map<String, dynamic> json) =>
      IngestionRecord(
        id: json['id'] as String,
        entityId: json['entityId'] as String,
        sourceType: SynoballSourceType.values.byName(
          json['sourceType'] as String,
        ),
        connectionId: json['connectionId'] as String?,
        institutionId: json['institutionId'] as String?,
        receivedAt: DateTime.parse(json['receivedAt'] as String),
        rawPayloadId: json['rawPayloadId'] as String,
        status: IngestionStatus.values.byName(json['status'] as String),
        adapterId: json['adapterId'] as String,
        adapterVersion: json['adapterVersion'] as String,
        importBatchId: json['importBatchId'] as String?,
        errorCode: json['errorCode'] == null
            ? null
            : SynoballErrorCode.values.byName(json['errorCode'] as String),
        errorMessage: json['errorMessage'] as String?,
      );
}

class TransactionCandidate {
  const TransactionCandidate({
    required this.id,
    required this.ingestionRecordId,
    required this.entityId,
    required this.accountId,
    required this.amount,
    required this.direction,
    required this.occurredAt,
    required this.rawDescription,
    required this.confidence,
    required this.sourceTrust,
    required this.status,
    this.canonicalId,
    this.normalizedDescription,
    this.merchantGuess,
    this.providerCategory,
    this.categoryGuess,
    this.userCategoryOverride,
    this.subcategoryId,
    this.providerTransactionId,
    this.receiptId,
    this.transferDirection,
    this.tags = const [],
    this.requiresConfirmation = false,
  });

  final String id;
  final String ingestionRecordId;
  final String entityId;
  final String accountId;
  final Money amount;
  final FinancialDirection direction;
  final DateTime occurredAt;
  final String rawDescription;
  final String? normalizedDescription;
  final String? merchantGuess;
  final String? providerCategory;
  final String? categoryGuess;
  final String? userCategoryOverride;
  final String? subcategoryId;
  final String? providerTransactionId;
  final String? receiptId;
  final String? transferDirection;
  final double confidence;
  final SourceTrustLevel sourceTrust;
  final CandidateStatus status;
  final List<String> tags;
  final bool requiresConfirmation;
  final String? canonicalId;

  TransactionCandidate copyWith({
    double? confidence,
    SourceTrustLevel? sourceTrust,
    CandidateStatus? status,
    bool? requiresConfirmation,
  }) => TransactionCandidate(
    id: id,
    ingestionRecordId: ingestionRecordId,
    entityId: entityId,
    accountId: accountId,
    amount: amount,
    direction: direction,
    occurredAt: occurredAt,
    rawDescription: rawDescription,
    normalizedDescription: normalizedDescription,
    merchantGuess: merchantGuess,
    providerCategory: providerCategory,
    categoryGuess: categoryGuess,
    userCategoryOverride: userCategoryOverride,
    subcategoryId: subcategoryId,
    providerTransactionId: providerTransactionId,
    receiptId: receiptId,
    transferDirection: transferDirection,
    confidence: confidence ?? this.confidence,
    sourceTrust: sourceTrust ?? this.sourceTrust,
    status: status ?? this.status,
    tags: tags,
    requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
    canonicalId: canonicalId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'ingestionRecordId': ingestionRecordId,
    'entityId': entityId,
    'accountId': accountId,
    'amount': amount.toJson(),
    'direction': direction.name,
    'occurredAt': occurredAt.toIso8601String(),
    'rawDescription': rawDescription,
    'normalizedDescription': normalizedDescription,
    'merchantGuess': merchantGuess,
    'providerCategory': providerCategory,
    'categoryGuess': categoryGuess,
    'userCategoryOverride': userCategoryOverride,
    'subcategoryId': subcategoryId,
    'providerTransactionId': providerTransactionId,
    'receiptId': receiptId,
    'transferDirection': transferDirection,
    'confidence': confidence,
    'sourceTrust': sourceTrust.name,
    'status': status.name,
    'tags': tags,
    'requiresConfirmation': requiresConfirmation,
    'canonicalId': canonicalId,
  };

  factory TransactionCandidate.fromJson(
    Map<String, dynamic> json,
  ) => TransactionCandidate(
    id: json['id'] as String,
    ingestionRecordId: json['ingestionRecordId'] as String,
    entityId: json['entityId'] as String,
    accountId: json['accountId'] as String,
    amount: Money.fromJson(_map(json['amount'])),
    direction: FinancialDirection.values.byName(json['direction'] as String),
    occurredAt: DateTime.parse(json['occurredAt'] as String),
    rawDescription: json['rawDescription'] as String,
    normalizedDescription: json['normalizedDescription'] as String?,
    merchantGuess: json['merchantGuess'] as String?,
    providerCategory: json['providerCategory'] as String?,
    categoryGuess: json['categoryGuess'] as String?,
    userCategoryOverride: json['userCategoryOverride'] as String?,
    subcategoryId: json['subcategoryId'] as String?,
    providerTransactionId: json['providerTransactionId'] as String?,
    receiptId: json['receiptId'] as String?,
    transferDirection: json['transferDirection'] as String?,
    confidence: (json['confidence'] as num).toDouble(),
    sourceTrust: SourceTrustLevel.values.byName(json['sourceTrust'] as String),
    status: CandidateStatus.values.byName(json['status'] as String),
    tags: _strings(json['tags']),
    requiresConfirmation: json['requiresConfirmation'] as bool? ?? false,
    canonicalId: json['canonicalId'] as String?,
  );
}

class FieldConfidence {
  const FieldConfidence({required this.value, required this.confidence});

  final String value;
  final double confidence;

  Map<String, dynamic> toJson() => {'value': value, 'confidence': confidence};

  factory FieldConfidence.fromJson(Map<String, dynamic> json) =>
      FieldConfidence(
        value: json['value'] as String,
        confidence: (json['confidence'] as num).toDouble(),
      );
}

class CanonicalTransaction {
  const CanonicalTransaction({
    required this.id,
    required this.entityId,
    required this.accountId,
    required this.status,
    required this.amount,
    required this.direction,
    required this.occurredAt,
    required this.rawDescription,
    required this.normalizedDescription,
    required this.eventType,
    required this.createdAt,
    required this.updatedAt,
    required this.fieldTrust,
    this.merchantId,
    this.merchantName,
    this.merchantConfidence,
    this.providerCategory,
    this.synoballCategory,
    this.userCategoryOverride,
    this.categoryConfidence,
    this.subcategoryId,
    this.transferDirection,
    this.isRecurring = false,
    this.recurringStreamId,
    this.receiptId,
    this.tags = const [],
  });

  final String id;
  final String entityId;
  final String accountId;
  final CanonicalTransactionStatus status;
  final Money amount;
  final FinancialDirection direction;
  final DateTime occurredAt;
  final String rawDescription;
  final String normalizedDescription;
  final String? merchantId;
  final String? merchantName;
  final double? merchantConfidence;
  final String? providerCategory;
  final String? synoballCategory;
  final String? userCategoryOverride;
  final double? categoryConfidence;
  final String? subcategoryId;
  final String? transferDirection;
  final FinancialEventType eventType;
  final bool isRecurring;
  final String? recurringStreamId;
  final String? receiptId;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SourceTrustLevel fieldTrust;

  String? get effectiveCategory =>
      userCategoryOverride ?? synoballCategory ?? providerCategory;

  CanonicalTransaction copyWith({
    String? accountId,
    CanonicalTransactionStatus? status,
    Money? amount,
    FinancialDirection? direction,
    DateTime? occurredAt,
    String? rawDescription,
    String? normalizedDescription,
    String? merchantId,
    String? merchantName,
    double? merchantConfidence,
    String? providerCategory,
    String? synoballCategory,
    String? userCategoryOverride,
    double? categoryConfidence,
    String? subcategoryId,
    String? transferDirection,
    bool? isRecurring,
    String? recurringStreamId,
    bool clearRecurringStreamId = false,
    String? receiptId,
    List<String>? tags,
    DateTime? updatedAt,
    SourceTrustLevel? fieldTrust,
  }) => CanonicalTransaction(
    id: id,
    entityId: entityId,
    accountId: accountId ?? this.accountId,
    status: status ?? this.status,
    amount: amount ?? this.amount,
    direction: direction ?? this.direction,
    occurredAt: occurredAt ?? this.occurredAt,
    rawDescription: rawDescription ?? this.rawDescription,
    normalizedDescription: normalizedDescription ?? this.normalizedDescription,
    merchantId: merchantId ?? this.merchantId,
    merchantName: merchantName ?? this.merchantName,
    merchantConfidence: merchantConfidence ?? this.merchantConfidence,
    providerCategory: providerCategory ?? this.providerCategory,
    synoballCategory: synoballCategory ?? this.synoballCategory,
    userCategoryOverride: userCategoryOverride ?? this.userCategoryOverride,
    categoryConfidence: categoryConfidence ?? this.categoryConfidence,
    subcategoryId: subcategoryId ?? this.subcategoryId,
    transferDirection: transferDirection ?? this.transferDirection,
    eventType: eventType,
    isRecurring: isRecurring ?? this.isRecurring,
    recurringStreamId: clearRecurringStreamId
        ? null
        : recurringStreamId ?? this.recurringStreamId,
    receiptId: receiptId ?? this.receiptId,
    tags: tags ?? this.tags,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    fieldTrust: fieldTrust ?? this.fieldTrust,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityId': entityId,
    'accountId': accountId,
    'status': status.name,
    'amount': amount.toJson(),
    'direction': direction.name,
    'occurredAt': occurredAt.toIso8601String(),
    'rawDescription': rawDescription,
    'normalizedDescription': normalizedDescription,
    'merchantId': merchantId,
    'merchantName': merchantName,
    'merchantConfidence': merchantConfidence,
    'providerCategory': providerCategory,
    'synoballCategory': synoballCategory,
    'userCategoryOverride': userCategoryOverride,
    'categoryConfidence': categoryConfidence,
    'subcategoryId': subcategoryId,
    'transferDirection': transferDirection,
    'eventType': eventType.name,
    'isRecurring': isRecurring,
    'recurringStreamId': recurringStreamId,
    'receiptId': receiptId,
    'tags': tags,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'fieldTrust': fieldTrust.name,
  };

  factory CanonicalTransaction.fromJson(
    Map<String, dynamic> json,
  ) => CanonicalTransaction(
    id: json['id'] as String,
    entityId: json['entityId'] as String,
    accountId: json['accountId'] as String,
    status: CanonicalTransactionStatus.values.byName(json['status'] as String),
    amount: Money.fromJson(_map(json['amount'])),
    direction: FinancialDirection.values.byName(json['direction'] as String),
    occurredAt: DateTime.parse(json['occurredAt'] as String),
    rawDescription: json['rawDescription'] as String,
    normalizedDescription: json['normalizedDescription'] as String,
    merchantId: json['merchantId'] as String?,
    merchantName: json['merchantName'] as String?,
    merchantConfidence: (json['merchantConfidence'] as num?)?.toDouble(),
    providerCategory: json['providerCategory'] as String?,
    synoballCategory: json['synoballCategory'] as String?,
    userCategoryOverride: json['userCategoryOverride'] as String?,
    categoryConfidence: (json['categoryConfidence'] as num?)?.toDouble(),
    subcategoryId: json['subcategoryId'] as String?,
    transferDirection: json['transferDirection'] as String?,
    eventType: FinancialEventType.values.byName(json['eventType'] as String),
    isRecurring: json['isRecurring'] as bool? ?? false,
    recurringStreamId: json['recurringStreamId'] as String?,
    receiptId: json['receiptId'] as String?,
    tags: _strings(json['tags']),
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    fieldTrust: SourceTrustLevel.values.byName(json['fieldTrust'] as String),
  );
}

class SourceEvidence {
  const SourceEvidence({
    required this.id,
    required this.transactionId,
    required this.sourceType,
    required this.ingestionRecordId,
    required this.confidence,
    required this.trust,
    required this.observedAt,
    this.providerTransactionId,
  });

  final String id;
  final String transactionId;
  final SynoballSourceType sourceType;
  final String ingestionRecordId;
  final double confidence;
  final SourceTrustLevel trust;
  final DateTime observedAt;
  final String? providerTransactionId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'transactionId': transactionId,
    'sourceType': sourceType.name,
    'ingestionRecordId': ingestionRecordId,
    'confidence': confidence,
    'trust': trust.name,
    'observedAt': observedAt.toIso8601String(),
    'providerTransactionId': providerTransactionId,
  };

  factory SourceEvidence.fromJson(Map<String, dynamic> json) => SourceEvidence(
    id: json['id'] as String,
    transactionId: json['transactionId'] as String,
    sourceType: SynoballSourceType.values.byName(json['sourceType'] as String),
    ingestionRecordId: json['ingestionRecordId'] as String,
    confidence: (json['confidence'] as num).toDouble(),
    trust: SourceTrustLevel.values.byName(json['trust'] as String),
    observedAt: DateTime.parse(json['observedAt'] as String),
    providerTransactionId: json['providerTransactionId'] as String?,
  );
}

class ReceiptItem {
  const ReceiptItem({
    required this.name,
    required this.total,
    this.quantity = 1,
    this.unitPrice,
  });

  final String name;
  final double quantity;
  final Money? unitPrice;
  final Money total;

  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
    'unitPrice': unitPrice?.toJson(),
    'total': total.toJson(),
  };

  factory ReceiptItem.fromJson(Map<String, dynamic> json) => ReceiptItem(
    name: json['name'] as String,
    quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
    unitPrice: json['unitPrice'] == null
        ? null
        : Money.fromJson(_map(json['unitPrice'])),
    total: Money.fromJson(_map(json['total'])),
  );
}

class SynoballReceipt {
  const SynoballReceipt({
    required this.id,
    required this.ingestionRecordId,
    required this.purchasedAt,
    required this.total,
    required this.fiscalFingerprint,
    required this.rawText,
    this.merchant,
    this.items = const [],
    this.confidence = 1,
    this.userCorrections = const {},
  });

  final String id;
  final String ingestionRecordId;
  final DateTime purchasedAt;
  final Money total;
  final String fiscalFingerprint;
  final String rawText;
  final String? merchant;
  final List<ReceiptItem> items;
  final double confidence;
  final Map<String, String> userCorrections;

  Map<String, dynamic> toJson() => {
    'id': id,
    'ingestionRecordId': ingestionRecordId,
    'purchasedAt': purchasedAt.toIso8601String(),
    'total': total.toJson(),
    'fiscalFingerprint': fiscalFingerprint,
    'rawText': rawText,
    'merchant': merchant,
    'items': items.map((value) => value.toJson()).toList(),
    'confidence': confidence,
    'userCorrections': userCorrections,
  };

  factory SynoballReceipt.fromJson(Map<String, dynamic> json) =>
      SynoballReceipt(
        id: json['id'] as String,
        ingestionRecordId: json['ingestionRecordId'] as String,
        purchasedAt: DateTime.parse(json['purchasedAt'] as String),
        total: Money.fromJson(_map(json['total'])),
        fiscalFingerprint: json['fiscalFingerprint'] as String,
        rawText: json['rawText'] as String,
        merchant: json['merchant'] as String?,
        items: _maps(
          json['items'],
        ).map(ReceiptItem.fromJson).toList(growable: false),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1,
        userCorrections: Map<String, String>.from(
          json['userCorrections'] as Map? ?? const {},
        ),
      );
}

class ImportBatch {
  const ImportBatch({
    required this.id,
    required this.entityId,
    required this.name,
    required this.sourceType,
    required this.createdAt,
    required this.status,
    required this.totalRecords,
    required this.createdTransactions,
    required this.matchedTransactions,
    required this.failedRecords,
    this.warnings = const [],
  });

  final String id;
  final String entityId;
  final String name;
  final SynoballSourceType sourceType;
  final DateTime createdAt;
  final ImportBatchStatus status;
  final int totalRecords;
  final int createdTransactions;
  final int matchedTransactions;
  final int failedRecords;
  final List<String> warnings;

  ImportBatch copyWith({
    ImportBatchStatus? status,
    int? createdTransactions,
    int? matchedTransactions,
    int? failedRecords,
    List<String>? warnings,
  }) => ImportBatch(
    id: id,
    entityId: entityId,
    name: name,
    sourceType: sourceType,
    createdAt: createdAt,
    status: status ?? this.status,
    totalRecords: totalRecords,
    createdTransactions: createdTransactions ?? this.createdTransactions,
    matchedTransactions: matchedTransactions ?? this.matchedTransactions,
    failedRecords: failedRecords ?? this.failedRecords,
    warnings: warnings ?? this.warnings,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityId': entityId,
    'name': name,
    'sourceType': sourceType.name,
    'createdAt': createdAt.toIso8601String(),
    'status': status.name,
    'totalRecords': totalRecords,
    'createdTransactions': createdTransactions,
    'matchedTransactions': matchedTransactions,
    'failedRecords': failedRecords,
    'warnings': warnings,
  };

  factory ImportBatch.fromJson(Map<String, dynamic> json) => ImportBatch(
    id: json['id'] as String,
    entityId: json['entityId'] as String,
    name: json['name'] as String,
    sourceType: SynoballSourceType.values.byName(json['sourceType'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String),
    status: ImportBatchStatus.values.byName(json['status'] as String),
    totalRecords: json['totalRecords'] as int,
    createdTransactions: json['createdTransactions'] as int,
    matchedTransactions: json['matchedTransactions'] as int,
    failedRecords: json['failedRecords'] as int,
    warnings: _strings(json['warnings']),
  );
}

class RecurringStream {
  const RecurringStream({
    required this.id,
    required this.entityId,
    required this.merchantKey,
    required this.title,
    required this.typicalAmount,
    required this.frequency,
    required this.nextExpectedAt,
    required this.confidence,
    required this.transactionIds,
  });

  final String id;
  final String entityId;
  final String merchantKey;
  final String title;
  final Money typicalAmount;
  final RecurrenceFrequency frequency;
  final DateTime nextExpectedAt;
  final double confidence;
  final List<String> transactionIds;

  Map<String, dynamic> toJson() => {
    'id': id,
    'entityId': entityId,
    'merchantKey': merchantKey,
    'title': title,
    'typicalAmount': typicalAmount.toJson(),
    'frequency': frequency.name,
    'nextExpectedAt': nextExpectedAt.toIso8601String(),
    'confidence': confidence,
    'transactionIds': transactionIds,
  };

  factory RecurringStream.fromJson(Map<String, dynamic> json) =>
      RecurringStream(
        id: json['id'] as String,
        entityId: json['entityId'] as String,
        merchantKey: json['merchantKey'] as String,
        title: json['title'] as String,
        typicalAmount: Money.fromJson(_map(json['typicalAmount'])),
        frequency: RecurrenceFrequency.values.byName(
          json['frequency'] as String,
        ),
        nextExpectedAt: DateTime.parse(json['nextExpectedAt'] as String),
        confidence: (json['confidence'] as num).toDouble(),
        transactionIds: _strings(json['transactionIds']),
      );
}

class SynoballEvent {
  const SynoballEvent({
    required this.id,
    required this.type,
    required this.entityId,
    required this.occurredAt,
    this.subjectId,
    this.payload = const {},
  });

  final String id;
  final String type;
  final String entityId;
  final String? subjectId;
  final DateTime occurredAt;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'entityId': entityId,
    'subjectId': subjectId,
    'occurredAt': occurredAt.toIso8601String(),
    'payload': payload,
  };

  factory SynoballEvent.fromJson(Map<String, dynamic> json) => SynoballEvent(
    id: json['id'] as String,
    type: json['type'] as String,
    entityId: json['entityId'] as String,
    subjectId: json['subjectId'] as String?,
    occurredAt: DateTime.parse(json['occurredAt'] as String),
    payload: _map(json['payload']),
  );
}

class SynoballAuditEntry {
  const SynoballAuditEntry({
    required this.id,
    required this.actorId,
    required this.action,
    required this.entityId,
    required this.purpose,
    required this.occurredAt,
    this.subjectId,
  });

  final String id;
  final String actorId;
  final String action;
  final String entityId;
  final String purpose;
  final DateTime occurredAt;
  final String? subjectId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'actorId': actorId,
    'action': action,
    'entityId': entityId,
    'purpose': purpose,
    'occurredAt': occurredAt.toIso8601String(),
    'subjectId': subjectId,
  };

  factory SynoballAuditEntry.fromJson(Map<String, dynamic> json) =>
      SynoballAuditEntry(
        id: json['id'] as String,
        actorId: json['actorId'] as String,
        action: json['action'] as String,
        entityId: json['entityId'] as String,
        purpose: json['purpose'] as String,
        occurredAt: DateTime.parse(json['occurredAt'] as String),
        subjectId: json['subjectId'] as String?,
      );
}

class SynoballState {
  const SynoballState({
    this.schemaVersion = currentSchemaVersion,
    this.modelVersion = currentModelVersion,
    this.entities = const [],
    this.institutions = const [],
    this.connections = const [],
    this.consents = const [],
    this.accounts = const [],
    this.rawPayloads = const [],
    this.ingestionRecords = const [],
    this.candidates = const [],
    this.transactions = const [],
    this.evidence = const [],
    this.receipts = const [],
    this.importBatches = const [],
    this.recurringStreams = const [],
    this.events = const [],
    this.auditEntries = const [],
  });

  static const currentSchemaVersion = 1;
  static const currentModelVersion = '1.0.0';

  final int schemaVersion;
  final String modelVersion;
  final List<SynoballEntity> entities;
  final List<Institution> institutions;
  final List<SynoballConnection> connections;
  final List<SynoballConsent> consents;
  final List<SynoballAccount> accounts;
  final List<RawPayload> rawPayloads;
  final List<IngestionRecord> ingestionRecords;
  final List<TransactionCandidate> candidates;
  final List<CanonicalTransaction> transactions;
  final List<SourceEvidence> evidence;
  final List<SynoballReceipt> receipts;
  final List<ImportBatch> importBatches;
  final List<RecurringStream> recurringStreams;
  final List<SynoballEvent> events;
  final List<SynoballAuditEntry> auditEntries;

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'modelVersion': modelVersion,
    'entities': entities.map((value) => value.toJson()).toList(),
    'institutions': institutions.map((value) => value.toJson()).toList(),
    'connections': connections.map((value) => value.toJson()).toList(),
    'consents': consents.map((value) => value.toJson()).toList(),
    'accounts': accounts.map((value) => value.toJson()).toList(),
    'rawPayloads': rawPayloads.map((value) => value.toJson()).toList(),
    'ingestionRecords': ingestionRecords
        .map((value) => value.toJson())
        .toList(),
    'candidates': candidates.map((value) => value.toJson()).toList(),
    'transactions': transactions.map((value) => value.toJson()).toList(),
    'evidence': evidence.map((value) => value.toJson()).toList(),
    'receipts': receipts.map((value) => value.toJson()).toList(),
    'importBatches': importBatches.map((value) => value.toJson()).toList(),
    'recurringStreams': recurringStreams
        .map((value) => value.toJson())
        .toList(),
    'events': events.map((value) => value.toJson()).toList(),
    'auditEntries': auditEntries.map((value) => value.toJson()).toList(),
  };

  factory SynoballState.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'] as int? ?? 0;
    if (version != currentSchemaVersion) {
      throw FormatException('Unsupported Synoball schema version: $version');
    }
    return SynoballState(
      schemaVersion: version,
      modelVersion: json['modelVersion'] as String? ?? currentModelVersion,
      entities: _maps(json['entities']).map(SynoballEntity.fromJson).toList(),
      institutions: _maps(
        json['institutions'],
      ).map(Institution.fromJson).toList(),
      connections: _maps(
        json['connections'],
      ).map(SynoballConnection.fromJson).toList(),
      consents: _maps(json['consents']).map(SynoballConsent.fromJson).toList(),
      accounts: _maps(json['accounts']).map(SynoballAccount.fromJson).toList(),
      rawPayloads: _maps(json['rawPayloads']).map(RawPayload.fromJson).toList(),
      ingestionRecords: _maps(
        json['ingestionRecords'],
      ).map(IngestionRecord.fromJson).toList(),
      candidates: _maps(
        json['candidates'],
      ).map(TransactionCandidate.fromJson).toList(),
      transactions: _maps(
        json['transactions'],
      ).map(CanonicalTransaction.fromJson).toList(),
      evidence: _maps(json['evidence']).map(SourceEvidence.fromJson).toList(),
      receipts: _maps(json['receipts']).map(SynoballReceipt.fromJson).toList(),
      importBatches: _maps(
        json['importBatches'],
      ).map(ImportBatch.fromJson).toList(),
      recurringStreams: _maps(
        json['recurringStreams'],
      ).map(RecurringStream.fromJson).toList(),
      events: _maps(json['events']).map(SynoballEvent.fromJson).toList(),
      auditEntries: _maps(
        json['auditEntries'],
      ).map(SynoballAuditEntry.fromJson).toList(),
    );
  }
}

Map<String, dynamic> _map(Object? value) =>
    Map<String, dynamic>.from(value as Map? ?? const {});

List<Map<String, dynamic>> _maps(Object? value) => (value as List? ?? const [])
    .map((item) => Map<String, dynamic>.from(item as Map))
    .toList(growable: false);

List<String> _strings(Object? value) =>
    (value as List? ?? const []).cast<String>();

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
