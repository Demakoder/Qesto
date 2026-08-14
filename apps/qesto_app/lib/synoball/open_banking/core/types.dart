abstract class OpenBankingStringValue {
  const OpenBankingStringValue(this.value) : assert(value != '');

  final String value;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is OpenBankingStringValue &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => value;
}

class ProviderId extends OpenBankingStringValue {
  const ProviderId(super.value);
}

class InstitutionId extends OpenBankingStringValue {
  const InstitutionId(super.value);
}

class ConsentId extends OpenBankingStringValue {
  const ConsentId(super.value);
}

class BankConnectionId extends OpenBankingStringValue {
  const BankConnectionId(super.value);
}

class AuthorizationSessionId extends OpenBankingStringValue {
  const AuthorizationSessionId(super.value);
}

class OAuthClientId extends OpenBankingStringValue {
  const OAuthClientId(super.value);
}

enum OpenBankingRuntimeMode { disabled, mock, sandbox, production }

enum ProviderEnvironment { disabled, mock, sandbox, production }

enum BankConnectionStatus {
  planned,
  disabled,
  connecting,
  active,
  degraded,
  disconnected,
  revoked,
  failed,
}

enum AuthorizationSessionStatus {
  created,
  authorizationPending,
  authorized,
  tokenPending,
  completed,
  denied,
  expired,
  failed,
}

class AuthorizationSession {
  const AuthorizationSession({
    required this.id,
    required this.providerId,
    required this.status,
    required this.stateHash,
    required this.nonceHash,
    required this.createdAt,
    required this.expiresAt,
    this.consentId,
    this.authorizationCodeHash,
    this.lastErrorCode,
  });

  final AuthorizationSessionId id;
  final ProviderId providerId;
  final AuthorizationSessionStatus status;
  final String stateHash;
  final String nonceHash;
  final DateTime createdAt;
  final DateTime expiresAt;
  final ConsentId? consentId;
  final String? authorizationCodeHash;
  final String? lastErrorCode;
}

enum CredentialBindingMethod { mtls, privateKeyJwt }

class CredentialBinding {
  const CredentialBinding({
    required this.connectionId,
    required this.method,
    required this.keyOrCertificateReference,
    required this.createdAt,
    this.expiresAt,
  });

  final BankConnectionId connectionId;
  final CredentialBindingMethod method;
  final String keyOrCertificateReference;
  final DateTime createdAt;
  final DateTime? expiresAt;
}

class DataProvenance {
  const DataProvenance({
    required this.source,
    required this.providerId,
    required this.institutionId,
    required this.connectionId,
    required this.consentId,
    required this.retrievedAt,
    required this.apiVersion,
  });

  static const cbrOpenApiSource = 'CBR_OPEN_API';

  final String source;
  final ProviderId providerId;
  final InstitutionId institutionId;
  final BankConnectionId connectionId;
  final ConsentId consentId;
  final DateTime retrievedAt;
  final String apiVersion;
}
