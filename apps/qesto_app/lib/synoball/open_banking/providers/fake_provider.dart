import '../api/cbr_2025_12_v2/accounts.dart';
import '../api/cbr_2025_12_v2/consent.dart';
import '../core/clock.dart';
import '../core/errors.dart';
import '../core/types.dart';
import 'provider.dart';

enum FakeBankScenario {
  happyPath,
  userRejectsConsent,
  consentRevoked,
  consentExpired,
  providerError,
}

class InMemoryFakeOpenBankingProvider implements OpenBankingProvider {
  InMemoryFakeOpenBankingProvider({
    required this.profile,
    required this.clock,
    this.scenario = FakeBankScenario.happyPath,
  }) : assert(profile.environment == ProviderEnvironment.mock);

  @override
  final OpenBankingProviderProfile profile;
  final OpenBankingClock clock;
  final FakeBankScenario scenario;
  CbrAccountConsentResource? _consent;

  @override
  Future<CbrAccountConsentResource> createConsent(
    CbrAccountConsent consent,
  ) async {
    _maybeFail();
    const validator = CbrConsentPermissionValidator();
    validator.validate(
      consent.permissions,
      providerPermissions: profile.capabilities.consentPermissions,
    );
    final now = clock.now();
    final status = switch (scenario) {
      FakeBankScenario.userRejectsConsent => CbrConsentStatus.rejected,
      FakeBankScenario.consentRevoked => CbrConsentStatus.revoked,
      _ => CbrConsentStatus.awaitingAuthorisation,
    };
    _consent = CbrAccountConsentResource(
      permissions: consent.permissions,
      consentId: const ConsentId('fixture-consent-1'),
      creationDateTime: CbrOffsetDateTime(now.toIso8601String()),
      status: status,
      statusUpdateDateTime: CbrOffsetDateTime(now.toIso8601String()),
      expirationDateTime: scenario == FakeBankScenario.consentExpired
          ? CbrOffsetDateTime(
              now.subtract(const Duration(minutes: 1)).toIso8601String(),
            )
          : consent.expirationDateTime,
      transactionFromDateTime: consent.transactionFromDateTime,
      transactionToDateTime: consent.transactionToDateTime,
    );
    return _consent!;
  }

  void authoriseConsent() {
    final consent = _requireConsent();
    const CbrConsentStateMachine().requireTransition(
      consent.status,
      CbrConsentStatus.authorised,
    );
    _consent = _withStatus(consent, CbrConsentStatus.authorised);
  }

  void rejectConsent() {
    final consent = _requireConsent();
    const CbrConsentStateMachine().requireTransition(
      consent.status,
      CbrConsentStatus.rejected,
    );
    _consent = _withStatus(consent, CbrConsentStatus.rejected);
  }

  @override
  Future<CbrAccountConsentResource> getConsent(ConsentId id) async {
    _maybeFail();
    final consent = _requireConsent();
    if (consent.consentId != id) {
      throw const OpenBankingValidationError(
        'consent_not_found',
        'The fixture consent does not exist.',
      );
    }
    return consent;
  }

  @override
  Future<void> revokeConsent(ConsentId id) async {
    final consent = await getConsent(id);
    const CbrConsentStateMachine().requireTransition(
      consent.status,
      CbrConsentStatus.revoked,
    );
    _consent = _withStatus(consent, CbrConsentStatus.revoked);
  }

  @override
  Future<CbrProviderAuthorizationSession> prepareAuthorization({
    required ConsentId consentId,
    required String stateHash,
    required String nonceHash,
  }) async {
    final consent = await getConsent(consentId);
    if (consent.status != CbrConsentStatus.awaitingAuthorisation) {
      throw const OpenBankingValidationError(
        'consent_not_awaiting_authorisation',
        'Only an awaiting consent may start authorization.',
      );
    }
    final now = clock.now();
    return CbrProviderAuthorizationSession(
      consentId: consentId,
      session: AuthorizationSession(
        id: const AuthorizationSessionId('fixture-auth-session-1'),
        providerId: profile.providerId,
        status: AuthorizationSessionStatus.authorizationPending,
        stateHash: stateHash,
        nonceHash: nonceHash,
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 10)),
        consentId: consentId,
      ),
    );
  }

  @override
  Future<List<CbrRawAccount>> getAccounts(ConsentId consentId) async {
    _requireDataAccess(consentId);
    return const [
      CbrRawAccount({'fixtureId': 'account-1', 'schema': 'generated-boundary'}),
    ];
  }

  @override
  Future<List<CbrRawBalance>> getBalances(
    ConsentId consentId, {
    String? accountId,
  }) async {
    _requireDataAccess(consentId);
    return const [
      CbrRawBalance({'fixtureId': 'balance-1', 'schema': 'generated-boundary'}),
    ];
  }

  @override
  Future<List<CbrRawStatement>> getStatements(
    ConsentId consentId, {
    String? accountId,
  }) async {
    _requireDataAccess(consentId);
    return const [
      CbrRawStatement({
        'fixtureId': 'statement-1',
        'schema': 'generated-boundary',
      }),
    ];
  }

  @override
  Future<List<CbrRawEntry>> getEntries(
    ConsentId consentId, {
    required String statementId,
  }) async {
    _requireDataAccess(consentId);
    return const [
      CbrRawEntry({'fixtureId': 'entry-1', 'schema': 'generated-boundary'}),
    ];
  }

  void _requireDataAccess(ConsentId consentId) {
    _maybeFail();
    final consent = _requireConsent();
    if (consent.consentId != consentId ||
        consent.status != CbrConsentStatus.authorised) {
      throw const OpenBankingValidationError(
        'invalid_consent',
        'An authorised matching consent is required for account data.',
      );
    }
    final expiration = consent.expirationDateTime;
    if (expiration != null && !expiration.utc.isAfter(clock.now())) {
      throw const OpenBankingValidationError(
        'expired_consent',
        'The fixture consent has expired.',
      );
    }
  }

  void _maybeFail() {
    if (scenario == FakeBankScenario.providerError) {
      throw const OpenBankingValidationError(
        'fixture_provider_error',
        'Deterministic fake bank failure.',
      );
    }
  }

  CbrAccountConsentResource _requireConsent() {
    final consent = _consent;
    if (consent == null) {
      throw const OpenBankingValidationError(
        'consent_not_found',
        'Create the fixture consent first.',
      );
    }
    return consent;
  }

  CbrAccountConsentResource _withStatus(
    CbrAccountConsentResource source,
    CbrConsentStatus status,
  ) => CbrAccountConsentResource(
    permissions: source.permissions,
    consentId: source.consentId,
    creationDateTime: source.creationDateTime,
    status: status,
    statusUpdateDateTime: CbrOffsetDateTime(clock.now().toIso8601String()),
    expirationDateTime: source.expirationDateTime,
    transactionFromDateTime: source.transactionFromDateTime,
    transactionToDateTime: source.transactionToDateTime,
    extensions: source.extensions,
  );
}
