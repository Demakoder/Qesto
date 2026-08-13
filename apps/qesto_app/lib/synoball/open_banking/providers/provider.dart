import '../api/cbr_2025_12_v2/accounts.dart';
import '../api/cbr_2025_12_v2/consent.dart';
import '../core/errors.dart';
import '../core/types.dart';
import '../core/versions.dart';

class OpenBankingProviderCapabilities {
  const OpenBankingProviderCapabilities({
    required this.accounts,
    required this.balances,
    required this.statements,
    required this.transactionDetails,
    required this.debitTransactions,
    required this.creditTransactions,
    required this.ciba,
    required this.jarm,
    required this.mtls,
    required this.consentPermissions,
    required this.apiVersions,
    required this.securityProfiles,
  });

  final bool accounts;
  final bool balances;
  final bool statements;
  final bool transactionDetails;
  final bool debitTransactions;
  final bool creditTransactions;
  final bool ciba;
  final bool jarm;
  final bool mtls;
  final Set<CbrAccountPermission> consentPermissions;
  final List<String> apiVersions;
  final List<String> securityProfiles;
}

class OpenBankingProviderProfile {
  const OpenBankingProviderProfile._({
    required this.providerId,
    required this.institutionId,
    required this.environment,
    required this.capabilities,
    required this.apiVersion,
    required this.fapiSecVersion,
    this.fapiPaokVersion,
    this.issuer,
    this.discoveryUrl,
    this.jwksUri,
    this.authorizationEndpoint,
    this.tokenEndpoint,
    this.backchannelAuthenticationEndpoint,
    this.apiBaseUrl,
    this.clientAuthenticationMethod,
  });

  factory OpenBankingProviderProfile.disabled({
    required ProviderId providerId,
    required InstitutionId institutionId,
    required OpenBankingProviderCapabilities capabilities,
  }) => OpenBankingProviderProfile._(
    providerId: providerId,
    institutionId: institutionId,
    environment: ProviderEnvironment.disabled,
    capabilities: capabilities,
    apiVersion: ApiStandardVersion.cbrOpenApi2025_12V2.wireName,
    fapiSecVersion: SecurityStandardVersion.fapiSec1_6_2024.wireName,
    fapiPaokVersion: SecurityStandardVersion.fapiPaok1_0_2024.wireName,
  );

  /// Fixture-only profile. URLs, when present, are identifiers and are not used
  /// by the in-memory provider to perform network I/O.
  factory OpenBankingProviderProfile.mock({
    required ProviderId providerId,
    required InstitutionId institutionId,
    required OpenBankingProviderCapabilities capabilities,
    Uri? issuer,
    Uri? discoveryUrl,
    Uri? jwksUri,
    Uri? authorizationEndpoint,
    Uri? tokenEndpoint,
    Uri? backchannelAuthenticationEndpoint,
    Uri? apiBaseUrl,
    String? clientAuthenticationMethod,
  }) => OpenBankingProviderProfile._(
    providerId: providerId,
    institutionId: institutionId,
    environment: ProviderEnvironment.mock,
    capabilities: capabilities,
    apiVersion: ApiStandardVersion.cbrOpenApi2025_12V2.wireName,
    fapiSecVersion: SecurityStandardVersion.fapiSec1_6_2024.wireName,
    fapiPaokVersion: SecurityStandardVersion.fapiPaok1_0_2024.wireName,
    issuer: issuer,
    discoveryUrl: discoveryUrl,
    jwksUri: jwksUri,
    authorizationEndpoint: authorizationEndpoint,
    tokenEndpoint: tokenEndpoint,
    backchannelAuthenticationEndpoint: backchannelAuthenticationEndpoint,
    apiBaseUrl: apiBaseUrl,
    clientAuthenticationMethod: clientAuthenticationMethod,
  );

  factory OpenBankingProviderProfile.external({
    required ProviderEnvironment environment,
  }) => throw OpenBankingNotEnabledError(
    'Provider profiles for ${environment.name} cannot be instantiated.',
  );

  static const standard = 'CBR_OPEN_API';

  final ProviderId providerId;
  final InstitutionId institutionId;
  final ProviderEnvironment environment;
  final OpenBankingProviderCapabilities capabilities;
  final String apiVersion;
  final String fapiSecVersion;
  final String? fapiPaokVersion;
  final Uri? issuer;
  final Uri? discoveryUrl;
  final Uri? jwksUri;
  final Uri? authorizationEndpoint;
  final Uri? tokenEndpoint;
  final Uri? backchannelAuthenticationEndpoint;
  final Uri? apiBaseUrl;
  final String? clientAuthenticationMethod;
}

class CbrProviderAuthorizationSession {
  const CbrProviderAuthorizationSession({
    required this.session,
    required this.consentId,
    this.authorizationUri,
  });

  final AuthorizationSession session;
  final ConsentId consentId;
  final Uri? authorizationUri;
}

abstract interface class OpenBankingProvider {
  OpenBankingProviderProfile get profile;

  Future<CbrAccountConsentResource> createConsent(CbrAccountConsent consent);

  Future<CbrAccountConsentResource> getConsent(ConsentId id);

  Future<void> revokeConsent(ConsentId id);

  Future<CbrProviderAuthorizationSession> prepareAuthorization({
    required ConsentId consentId,
    required String stateHash,
    required String nonceHash,
  });

  Future<List<CbrRawAccount>> getAccounts(ConsentId consentId);

  Future<List<CbrRawBalance>> getBalances(
    ConsentId consentId, {
    String? accountId,
  });

  Future<List<CbrRawStatement>> getStatements(
    ConsentId consentId, {
    String? accountId,
  });

  Future<List<CbrRawEntry>> getEntries(
    ConsentId consentId, {
    required String statementId,
  });
}
