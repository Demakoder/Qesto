import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  final allPermissions = Set<CbrAccountPermission>.from(
    CbrAccountPermission.known,
  );
  const validator = CbrConsentPermissionValidator();

  void expectValid(Set<CbrAccountPermission> permissions) {
    validator.validate(permissions, providerPermissions: allPermissions);
  }

  void expectInvalid(Set<CbrAccountPermission> permissions) {
    expect(
      () =>
          validator.validate(permissions, providerPermissions: allPermissions),
      throwsA(isA<OpenBankingValidationError>()),
    );
  }

  group('CBR consent permission combinations', () {
    test('empty is invalid', () => expectInvalid({}));

    test('ReadAccountsBasic is valid', () {
      expectValid({CbrAccountPermission.readAccountsBasic});
    });

    test('ReadAccountsDetail is valid and includes basic logically', () {
      expectValid({CbrAccountPermission.readAccountsDetail});
    });

    test('accounts plus balances is valid', () {
      expectValid({
        CbrAccountPermission.readAccountsBasic,
        CbrAccountPermission.readBalances,
      });
    });

    test('transaction level without direction is invalid', () {
      expectInvalid({
        CbrAccountPermission.readAccountsBasic,
        CbrAccountPermission.readTransactionsBasic,
      });
    });

    test('basic debit transactions are valid', () {
      expectValid({
        CbrAccountPermission.readAccountsBasic,
        CbrAccountPermission.readTransactionsBasic,
        CbrAccountPermission.readTransactionsDebits,
      });
    });

    test('transaction direction without level is invalid', () {
      expectInvalid({
        CbrAccountPermission.readAccountsBasic,
        CbrAccountPermission.readTransactionsCredits,
      });
    });

    test('detail with both directions is valid', () {
      expectValid({
        CbrAccountPermission.readAccountsBasic,
        CbrAccountPermission.readTransactionsDetail,
        CbrAccountPermission.readTransactionsCredits,
        CbrAccountPermission.readTransactionsDebits,
      });
    });

    test('provider capability mismatch is invalid', () {
      expect(
        () => validator.validate(
          {CbrAccountPermission.readAccountsDetail},
          providerPermissions: {CbrAccountPermission.readAccountsBasic},
        ),
        throwsA(
          isA<OpenBankingValidationError>().having(
            (error) => error.code,
            'code',
            'unsupported_consent_permission',
          ),
        ),
      );
    });
  });

  group('CBR consent lifecycle and raw DTO', () {
    const machine = CbrConsentStateMachine();

    test('awaiting may become authorised or rejected', () {
      expect(
        machine.canTransition(
          CbrConsentStatus.awaitingAuthorisation,
          CbrConsentStatus.authorised,
        ),
        isTrue,
      );
      expect(
        machine.canTransition(
          CbrConsentStatus.awaitingAuthorisation,
          CbrConsentStatus.rejected,
        ),
        isTrue,
      );
    });

    test('authorised may become revoked', () {
      expect(
        machine.canTransition(
          CbrConsentStatus.authorised,
          CbrConsentStatus.revoked,
        ),
        isTrue,
      );
    });

    test('terminal consent cannot return to authorised', () {
      expect(
        machine.canTransition(
          CbrConsentStatus.revoked,
          CbrConsentStatus.authorised,
        ),
        isFalse,
      );
      expect(
        machine.canTransition(
          CbrConsentStatus.rejected,
          CbrConsentStatus.authorised,
        ),
        isFalse,
      );
    });

    test('raw time preserves original offset', () {
      final consent = CbrAccountConsentResource.fromJson({
        'Permissions': ['ReadAccountsBasic'],
        'ConsentId': 'consent-1',
        'CreationDateTime': '2026-08-13T10:00:00+03:00',
        'Status': 'BankExtensionStatus',
        'StatusUpdateDateTime': '2026-08-13T10:05:00+03:00',
        'participant': true,
      });
      expect(consent.creationDateTime.raw, '2026-08-13T10:00:00+03:00');
      expect(consent.creationDateTime.utc.hour, 7);
      expect(consent.status.isKnown, isFalse);
      expect(consent.extensions['participant'], isTrue);
    });

    test('consent JSON uses original offset strings', () {
      final consent = CbrAccountConsent(
        permissions: {CbrAccountPermission.readAccountsBasic},
        expirationDateTime: CbrOffsetDateTime('2026-09-01T00:00:00+03:00'),
      );
      expect(
        consent.toJson()['ExpirationDateTime'],
        '2026-09-01T00:00:00+03:00',
      );
    });
  });

  group('CBR endpoint and envelope boundary', () {
    test('consent endpoints expose POST/GET/DELETE resource paths', () {
      const endpoints = CbrConsentEndpoints(
        participantPathPrefix: '/participant',
        version: 'v2.0',
      );
      expect(
        endpoints.create().build(),
        '/participant/open-banking/v2.0/acis-pe/account-consents',
      );
      expect(
        endpoints.get(const ConsentId('c1')).build(),
        endsWith('/account-consents/c1'),
      );
      expect(endpoints.delete(const ConsentId('c1')).build(), endsWith('/c1'));
    });

    test('account families do not invent a transactions endpoint', () {
      const endpoints = CbrAccountInformationEndpoints(
        participantPathPrefix: '',
        version: 'v2.0',
      );
      final paths = [
        endpoints.accounts().build(),
        endpoints.accounts('a1').build(),
        endpoints.balances().build(),
        endpoints.balances('a1').build(),
        endpoints.statements().build(),
        endpoints.statements(accountId: 'a1').build(),
        endpoints.statements(statementId: 's1').build(),
      ];
      expect(paths.every((path) => !path.contains('/transactions')), isTrue);
      expect(paths, contains(endsWith('/accounts/a1/balances')));
      expect(paths, contains(endsWith('/statements/s1')));
    });

    test('response envelope supports links, pagination and extensions', () {
      final response = CbrApiResponse<List<Object?>>.fromJson({
        'Data': [1, 2],
        'Links': {
          'self': 'https://bank.invalid/accounts?page=1',
          'next': 'https://bank.invalid/accounts?page=2',
        },
        'Meta': {'totalPages': 2, 'bankHint': 'x'},
      }, (raw) => raw! as List<Object?>);
      expect(response.data, [1, 2]);
      expect(response.links?.next?.queryParameters['page'], '2');
      expect(response.meta?.totalPages, 2);
      expect(response.meta?.extensions['bankHint'], 'x');
    });

    test('raw DTO boundary preserves generated schema payload unchanged', () {
      const payload = {'OfficialFutureField': 'untouched'};
      const account = CbrRawAccount(payload);
      expect(account.raw, same(payload));
    });
  });
}
