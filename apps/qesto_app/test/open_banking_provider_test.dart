import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/synoball/synoball.dart';

OpenBankingProviderCapabilities capabilities() =>
    OpenBankingProviderCapabilities(
      accounts: true,
      balances: true,
      statements: true,
      transactionDetails: true,
      debitTransactions: true,
      creditTransactions: true,
      ciba: true,
      jarm: true,
      mtls: true,
      consentPermissions: Set.from(CbrAccountPermission.known),
      apiVersions: const ['CBR-OAPI-2025-12-v2'],
      securityProfiles: const ['FAPI.SEC-1.6-2024', 'FAPI.PAOK-1.0-2024'],
    );

OpenBankingProviderProfile mockProfile() => OpenBankingProviderProfile.mock(
  providerId: const ProviderId('fake-bank'),
  institutionId: const InstitutionId('fake-institution'),
  capabilities: capabilities(),
  issuer: Uri.parse('https://fixture.invalid'),
);

CbrAccountConsent consent({DateTime? expiresAt}) => CbrAccountConsent(
  permissions: {CbrAccountPermission.readAccountsBasic},
  expirationDateTime: expiresAt == null
      ? null
      : CbrOffsetDateTime(expiresAt.toIso8601String()),
);

void main() {
  group('provider safety boundary', () {
    test('sandbox and production profiles are impossible to instantiate', () {
      for (final environment in [
        ProviderEnvironment.sandbox,
        ProviderEnvironment.production,
      ]) {
        expect(
          () => OpenBankingProviderProfile.external(environment: environment),
          throwsA(isA<OpenBankingNotEnabledError>()),
        );
      }
    });

    test('disabled provider rejects every operation', () async {
      final disabledProfile = OpenBankingProviderProfile.disabled(
        providerId: const ProviderId('disabled'),
        institutionId: const InstitutionId('none'),
        capabilities: capabilities(),
      );
      final provider = DisabledOpenBankingProvider(disabledProfile);
      await expectLater(
        provider.createConsent(consent()),
        throwsA(isA<OpenBankingNotEnabledError>()),
      );
      await expectLater(
        provider.getAccounts(const ConsentId('any')),
        throwsA(isA<OpenBankingNotEnabledError>()),
      );
    });

    test('disabled crypto, certificates and signer fail closed', () async {
      await expectLater(
        const DisabledCertificateStore().load('bank'),
        throwsA(isA<OpenBankingNotEnabledError>()),
      );
      await expectLater(
        const DisabledDetachedPayloadSigner().signPayload(
          [1, 2, 3],
          const DetachedPayloadSigningContext(
            interactionId: 'trace',
            method: 'POST',
            path: '/account-consents',
          ),
        ),
        throwsA(isA<OpenBankingNotEnabledError>()),
      );
    });
  });

  group('deterministic fake bank', () {
    late FixedOpenBankingClock clock;

    setUp(() {
      clock = FixedOpenBankingClock(DateTime.utc(2026, 8, 13, 10));
    });

    test(
      'happy path preserves consent/authorization/data separation',
      () async {
        final provider = InMemoryFakeOpenBankingProvider(
          profile: mockProfile(),
          clock: clock,
        );
        final created = await provider.createConsent(consent());
        expect(created.status, CbrConsentStatus.awaitingAuthorisation);

        final authorization = await provider.prepareAuthorization(
          consentId: created.consentId,
          stateHash: 'state-hash-only',
          nonceHash: 'nonce-hash-only',
        );
        expect(
          authorization.session.status,
          AuthorizationSessionStatus.authorizationPending,
        );
        expect(authorization.session.stateHash, 'state-hash-only');

        provider.authoriseConsent();
        final accounts = await provider.getAccounts(created.consentId);
        final balances = await provider.getBalances(created.consentId);
        final statements = await provider.getStatements(created.consentId);
        expect(accounts, hasLength(1));
        expect(balances, hasLength(1));
        expect(statements, hasLength(1));
      },
    );

    test('rejected consent never exposes account data', () async {
      final provider = InMemoryFakeOpenBankingProvider(
        profile: mockProfile(),
        clock: clock,
        scenario: FakeBankScenario.userRejectsConsent,
      );
      final created = await provider.createConsent(consent());
      expect(created.status, CbrConsentStatus.rejected);
      await expectLater(
        provider.getAccounts(created.consentId),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('revoked consent never exposes account data', () async {
      final provider = InMemoryFakeOpenBankingProvider(
        profile: mockProfile(),
        clock: clock,
      );
      final created = await provider.createConsent(consent());
      provider.authoriseConsent();
      await provider.revokeConsent(created.consentId);
      await expectLater(
        provider.getAccounts(created.consentId),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('expired consent never exposes account data', () async {
      final provider = InMemoryFakeOpenBankingProvider(
        profile: mockProfile(),
        clock: clock,
        scenario: FakeBankScenario.consentExpired,
      );
      final created = await provider.createConsent(consent());
      provider.authoriseConsent();
      await expectLater(
        provider.getAccounts(created.consentId),
        throwsA(
          isA<OpenBankingValidationError>().having(
            (error) => error.code,
            'code',
            'expired_consent',
          ),
        ),
      );
    });

    test('provider error scenario is deterministic', () async {
      final provider = InMemoryFakeOpenBankingProvider(
        profile: mockProfile(),
        clock: clock,
        scenario: FakeBankScenario.providerError,
      );
      await expectLater(
        provider.createConsent(consent()),
        throwsA(
          isA<OpenBankingValidationError>().having(
            (error) => error.code,
            'code',
            'fixture_provider_error',
          ),
        ),
      );
    });
  });

  group('Synoball boundary', () {
    test('CBR is registered as disabled regulated data source', () {
      expect(FinancialDataSourceCatalog.cbrOpenApi.enabled, isFalse);
      expect(
        FinancialDataSourceCatalog.cbrOpenApi.type,
        FinancialDataSourceType.cbrOpenApi,
      );
      expect(FinancialDataSourceCatalog.statementFile.enabled, isTrue);
      expect(FinancialDataSourceCatalog.receipt.enabled, isTrue);
    });

    test('provenance identifies CBR without changing Synoball schema', () {
      final provenance = DataProvenance(
        source: DataProvenance.cbrOpenApiSource,
        providerId: const ProviderId('fake'),
        institutionId: const InstitutionId('institution'),
        connectionId: const BankConnectionId('connection'),
        consentId: const ConsentId('consent'),
        retrievedAt: DateTime.utc(2026, 8, 13),
        apiVersion: 'CBR-OAPI-2025-12-v2',
      );
      expect(provenance.source, 'CBR_OPEN_API');
      expect(SynoballSourceType.regulatedApi, isNotNull);
    });

    test('raw mappers fail instead of guessing official fields', () {
      final context = CbrMappingContext(
        entityId: 'entity',
        provenance: DataProvenance(
          source: DataProvenance.cbrOpenApiSource,
          providerId: const ProviderId('fake'),
          institutionId: const InstitutionId('institution'),
          connectionId: const BankConnectionId('connection'),
          consentId: const ConsentId('consent'),
          retrievedAt: DateTime.utc(2026, 8, 13),
          apiVersion: 'CBR-OAPI-2025-12-v2',
        ),
      );
      expect(
        () => const DisabledCbrAccountMapper().mapAccount(
          const CbrRawAccount({'unknown': 'schema'}),
          context,
        ),
        throwsA(isA<OpenBankingNotImplementedError>()),
      );
    });
  });
}
