import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  group('Open Banking runtime boundary', () {
    test('the shipped configuration is disabled', () {
      expect(OpenBankingFeatureConfig.disabled.enabled, isFalse);
      expect(
        OpenBankingFeatureConfig.disabled.mode,
        OpenBankingRuntimeMode.disabled,
      );
    });

    test('environment configuration cannot enable a live mode', () {
      expect(
        () => OpenBankingFeatureConfig.fromEnvironment(
          enabled: true,
          mode: OpenBankingRuntimeMode.production,
        ),
        throwsA(isA<OpenBankingNotEnabledError>()),
      );
    });

    test('central external IO guard always denies access', () {
      expect(
        assertExternalIoAllowed,
        throwsA(isA<OpenBankingNotEnabledError>()),
      );
    });

    test('disabled transport cannot perform a request', () async {
      const transport = DisabledOpenBankingTransport();
      await expectLater(
        transport.send(
          OpenBankingTransportRequest(
            method: 'GET',
            uri: Uri.parse('https://bank.invalid/open-banking'),
          ),
        ),
        throwsA(isA<OpenBankingNotEnabledError>()),
      );
    });

    test('fixture transport is deterministic and in-memory', () async {
      final transport = FixtureOpenBankingTransport(
        (request) => OpenBankingTransportResponse(
          statusCode: 200,
          body: {'path': request.uri.path},
        ),
      );
      final response = await transport.send(
        OpenBankingTransportRequest(
          method: 'GET',
          uri: Uri.parse('https://fixture.invalid/accounts'),
        ),
      );
      expect(response.statusCode, 200);
      expect(response.body, {'path': '/accounts'});
    });
  });

  group('Secrets and sanitization', () {
    test('SecretValue never renders its payload', () {
      const secret = SecretValue('super-secret-token');
      expect(secret.toString(), SecretValue.redacted);
      expect(
        jsonEncode({'token': secret}),
        isNot(contains('super-secret-token')),
      );
      expect(secret.matches('super-secret-token'), isTrue);
      expect(secret.matches('other'), isFalse);
    });

    test('sanitizer removes tokens and whole banking payloads', () {
      const sanitizer = OpenBankingLogSanitizer();
      final sanitized =
          sanitizer.sanitize({
                'access_token': 'token-value',
                'Data': {'account': '40817810'},
                'interactionId': 'safe-id',
              })
              as Map<String, Object?>;
      expect(sanitized['access_token'], SecretValue.redacted);
      expect(sanitized['Data'], '[REDACTED BANK PAYLOAD]');
      expect(sanitized['interactionId'], 'safe-id');
    });

    test('every OAuth secret class is redacted by key', () {
      const sanitizer = OpenBankingLogSanitizer();
      final sanitized =
          sanitizer.sanitize({
                'refresh_token': 'refresh',
                'id_token': 'id',
                'authorization_code': 'code',
                'client_assertion': 'assertion',
                'state': 'state',
                'nonce': 'nonce',
                'code_verifier': 'verifier',
              })
              as Map<String, Object?>;
      expect(sanitized.values, everyElement(equals(SecretValue.redacted)));
    });

    test('audit contains identifiers but no payload field', () {
      final clock = FixedOpenBankingClock(DateTime.utc(2026, 8, 13));
      final sink = InMemoryOpenBankingAuditSink();
      OpenBankingAuditor(clock, sink).record(
        eventType: 'consent.created',
        outcome: 'fixture',
        providerId: 'fake',
        interactionId: 'trace',
      );
      expect(sink.events.single.toJson()['providerId'], 'fake');
      expect(sink.events.single.toJson().containsKey('payload'), isFalse);
    });
  });

  group('Version and CBR HTTP primitives', () {
    test('security and API versions are independent', () {
      const profile = OpenBankingVersionProfile();
      expect(profile.security.wireName, 'FAPI.SEC-1.6-2024');
      expect(profile.backchannelAuthentication.wireName, 'FAPI.PAOK-1.0-2024');
      expect(profile.api.wireName, 'CBR-OAPI-2025-12-v2');
    });

    test('CBR path builder applies the standard route shape', () {
      const path = CbrResourcePath(
        participantPathPrefix: '/participant/api',
        version: 'v2.0',
        resourceGroup: 'acis-pe',
        resource: 'account-consents',
        resourceId: 'consent 1',
      );
      expect(
        path.build(),
        '/participant/api/open-banking/v2.0/acis-pe/account-consents/consent%201',
      );
    });

    test('typed headers are case-insensitive', () {
      final headers = CbrHeaders({
        'X-FAPI-INTERACTION-ID': '123e4567-e89b-12d3-a456-426614174000',
        'Retry-After': '60',
      });
      expect(
        headers.interactionId.toString(),
        '123e4567-e89b-12d3-a456-426614174000',
      );
      expect(RetryPolicyHint.fromHeaders(429, headers)?.delay?.inSeconds, 60);
    });

    test('Retry-After supports an HTTP date without starting a retry', () {
      final headers = CbrHeaders({
        'retry-after': 'Thu, 13 Aug 2026 10:05:00 GMT',
      });
      final hint = RetryPolicyHint.fromHeaders(503, headers);
      expect(hint?.at, DateTime.utc(2026, 8, 13, 10, 5));
      expect(CbrHttpStatus.serviceUnavailable.isRetryHintRelevant, isTrue);
    });

    test('unknown CBR error codes and extensions survive parsing', () {
      final error = CbrErrorResponse.fromJson({
        'code': 'RU.SBER.SOME_FUTURE_ERROR',
        'message': 'fixture',
        'participantField': 42,
        'Errors': [
          {
            'errorCode': 'RU.CBR.Field.Invalid',
            'message': 'bad field',
            'participantHint': 'x',
          },
        ],
      });
      expect(error.code.isKnown, isFalse);
      expect(error.extensions['participantField'], 42);
      expect(error.errors.single.errorCode.isKnown, isTrue);
      expect(error.errors.single.extensions['participantHint'], 'x');
    });
  });
}
