import '../../core/errors.dart';
import '../../core/types.dart';
import 'http.dart';

class CbrAccountPermission {
  const CbrAccountPermission(this.value);

  static const readAccountsBasic = CbrAccountPermission('ReadAccountsBasic');
  static const readAccountsDetail = CbrAccountPermission('ReadAccountsDetail');
  static const readBalances = CbrAccountPermission('ReadBalances');
  static const readTransactionsBasic = CbrAccountPermission(
    'ReadTransactionsBasic',
  );
  static const readTransactionsDetail = CbrAccountPermission(
    'ReadTransactionsDetail',
  );
  static const readTransactionsCredits = CbrAccountPermission(
    'ReadTransactionsCredits',
  );
  static const readTransactionsDebits = CbrAccountPermission(
    'ReadTransactionsDebits',
  );

  static final Set<CbrAccountPermission> known = {
    readAccountsBasic,
    readAccountsDetail,
    readBalances,
    readTransactionsBasic,
    readTransactionsDetail,
    readTransactionsCredits,
    readTransactionsDebits,
  };

  final String value;

  bool get isKnown => known.contains(this);

  @override
  bool operator ==(Object other) =>
      other is CbrAccountPermission && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

class CbrOffsetDateTime {
  CbrOffsetDateTime(this.raw) : value = DateTime.parse(raw);

  final String raw;
  final DateTime value;

  DateTime get utc => value.toUtc();

  @override
  String toString() => raw;
}

class CbrAccountConsent {
  const CbrAccountConsent({
    required this.permissions,
    this.expirationDateTime,
    this.transactionFromDateTime,
    this.transactionToDateTime,
  });

  final Set<CbrAccountPermission> permissions;
  final CbrOffsetDateTime? expirationDateTime;
  final CbrOffsetDateTime? transactionFromDateTime;
  final CbrOffsetDateTime? transactionToDateTime;

  Map<String, Object?> toJson() => {
    'Permissions': permissions.map((permission) => permission.value).toList(),
    if (expirationDateTime != null)
      'ExpirationDateTime': expirationDateTime!.raw,
    if (transactionFromDateTime != null)
      'TransactionFromDateTime': transactionFromDateTime!.raw,
    if (transactionToDateTime != null)
      'TransactionToDateTime': transactionToDateTime!.raw,
  };
}

class CbrConsentStatus {
  const CbrConsentStatus(this.value);

  static const awaitingAuthorisation = CbrConsentStatus(
    'AwaitingAuthorisation',
  );
  static const rejected = CbrConsentStatus('Rejected');
  static const authorised = CbrConsentStatus('Authorised');
  static const revoked = CbrConsentStatus('Revoked');

  static final Set<CbrConsentStatus> known = {
    awaitingAuthorisation,
    rejected,
    authorised,
    revoked,
  };

  final String value;

  bool get isKnown => known.contains(this);

  @override
  bool operator ==(Object other) =>
      other is CbrConsentStatus && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

class CbrAccountConsentResource extends CbrAccountConsent {
  const CbrAccountConsentResource({
    required super.permissions,
    required this.consentId,
    required this.creationDateTime,
    required this.status,
    required this.statusUpdateDateTime,
    super.expirationDateTime,
    super.transactionFromDateTime,
    super.transactionToDateTime,
    this.extensions = const {},
  });

  final ConsentId consentId;
  final CbrOffsetDateTime creationDateTime;
  final CbrConsentStatus status;
  final CbrOffsetDateTime statusUpdateDateTime;
  final Map<String, Object?> extensions;

  factory CbrAccountConsentResource.fromJson(Map<String, Object?> json) {
    const known = {
      'Permissions',
      'ConsentId',
      'CreationDateTime',
      'Status',
      'StatusUpdateDateTime',
      'ExpirationDateTime',
      'TransactionFromDateTime',
      'TransactionToDateTime',
    };
    return CbrAccountConsentResource(
      permissions: _permissionSet(json['Permissions']),
      consentId: ConsentId(json['ConsentId'] as String),
      creationDateTime: CbrOffsetDateTime(json['CreationDateTime'] as String),
      status: CbrConsentStatus(json['Status'] as String),
      statusUpdateDateTime: CbrOffsetDateTime(
        json['StatusUpdateDateTime'] as String,
      ),
      expirationDateTime: _optionalDate(json['ExpirationDateTime']),
      transactionFromDateTime: _optionalDate(json['TransactionFromDateTime']),
      transactionToDateTime: _optionalDate(json['TransactionToDateTime']),
      extensions: Map.fromEntries(
        json.entries.where((entry) => !known.contains(entry.key)),
      ),
    );
  }
}

class CbrConsentPermissionValidator {
  const CbrConsentPermissionValidator();

  void validate(
    Set<CbrAccountPermission> permissions, {
    required Set<CbrAccountPermission> providerPermissions,
  }) {
    if (permissions.isEmpty) {
      throw const OpenBankingValidationError(
        'invalid_consent_permissions',
        'The consent permission set must not be empty.',
      );
    }
    final hasAccount =
        permissions.contains(CbrAccountPermission.readAccountsBasic) ||
        permissions.contains(CbrAccountPermission.readAccountsDetail);
    if (!hasAccount) {
      throw const OpenBankingValidationError(
        'invalid_consent_permissions',
        'ReadAccountsBasic or ReadAccountsDetail is required.',
      );
    }
    if (!providerPermissions.containsAll(permissions)) {
      throw const OpenBankingValidationError(
        'unsupported_consent_permission',
        'The provider does not advertise every requested permission.',
      );
    }
    final hasTransactionLevel =
        permissions.contains(CbrAccountPermission.readTransactionsBasic) ||
        permissions.contains(CbrAccountPermission.readTransactionsDetail);
    final hasDirection =
        permissions.contains(CbrAccountPermission.readTransactionsCredits) ||
        permissions.contains(CbrAccountPermission.readTransactionsDebits);
    if (hasTransactionLevel != hasDirection) {
      throw const OpenBankingValidationError(
        'invalid_transaction_permission_combination',
        'Transaction detail/basic and credit/debit direction permissions require each other.',
      );
    }
  }
}

class CbrConsentStateMachine {
  const CbrConsentStateMachine();

  bool canTransition(CbrConsentStatus from, CbrConsentStatus to) {
    if (from == to) return true;
    if (from == CbrConsentStatus.awaitingAuthorisation) {
      return to == CbrConsentStatus.authorised ||
          to == CbrConsentStatus.rejected;
    }
    if (from == CbrConsentStatus.authorised) {
      return to == CbrConsentStatus.revoked;
    }
    return false;
  }

  void requireTransition(CbrConsentStatus from, CbrConsentStatus to) {
    if (!canTransition(from, to)) {
      throw OpenBankingValidationError(
        'invalid_consent_transition',
        'Consent cannot transition from ${from.value} to ${to.value}.',
      );
    }
  }
}

class CbrConsentEndpoints {
  const CbrConsentEndpoints({
    required this.participantPathPrefix,
    required this.version,
  });

  final String participantPathPrefix;
  final String version;

  CbrResourcePath create() => CbrResourcePath(
    participantPathPrefix: participantPathPrefix,
    version: version,
    resourceGroup: CbrResourcePath.individualAccountsResourceGroup,
    resource: 'account-consents',
  );

  CbrResourcePath get(ConsentId id) => CbrResourcePath(
    participantPathPrefix: participantPathPrefix,
    version: version,
    resourceGroup: CbrResourcePath.individualAccountsResourceGroup,
    resource: 'account-consents',
    resourceId: id.value,
  );

  CbrResourcePath delete(ConsentId id) => get(id);
}

Set<CbrAccountPermission> _permissionSet(Object? raw) => raw is List
    ? raw.whereType<String>().map(CbrAccountPermission.new).toSet()
    : const {};

CbrOffsetDateTime? _optionalDate(Object? raw) =>
    raw is String && raw.isNotEmpty ? CbrOffsetDateTime(raw) : null;
