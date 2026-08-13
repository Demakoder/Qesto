import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  const validator = CibaValidator();

  CibaAuthenticationRequest request({
    String? loginHint = 'user@example.invalid',
    SecretValue? idTokenHint,
    CibaDeliveryMode mode = CibaDeliveryMode.poll,
    SecretValue? notificationToken,
    String? bindingMessage,
    Duration? requestedExpiry,
  }) => CibaAuthenticationRequest(
    clientId: const OAuthClientId('qesto-client'),
    scopes: const {'openid', 'accounts'},
    deliveryMode: mode,
    loginHint: loginHint,
    idTokenHint: idTokenHint,
    clientNotificationToken: notificationToken,
    bindingMessage: bindingMessage,
    requestedExpiry: requestedExpiry,
  );

  group('CIBA validation', () {
    test('exactly one user hint is accepted', () {
      validator.validateRequest(request());
      expect(
        () => validator.validateRequest(
          request(idTokenHint: const SecretValue('id-token')),
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
      expect(
        () => validator.validateRequest(request(loginHint: null)),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('binding message is limited to 100 characters', () {
      expect(
        () => validator.validateRequest(
          request(bindingMessage: List.filled(101, 'x').join()),
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('requested expiry must be positive', () {
      expect(
        () => validator.validateRequest(
          request(requestedExpiry: const Duration(seconds: -1)),
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('ping and push require a high entropy notification token', () {
      expect(
        () => validator.validateRequest(request(mode: CibaDeliveryMode.ping)),
        throwsA(isA<OpenBankingValidationError>()),
      );
      validator.validateRequest(
        request(
          mode: CibaDeliveryMode.push,
          notificationToken: const SecretValue('01234567890123456789'),
        ),
      );
    });

    test('metadata parser preserves extensions', () {
      final metadata = const CibaMetadataParser().parse({
        'backchannel_authentication_endpoint': 'https://bank.invalid/ciba',
        'backchannel_token_delivery_modes_supported': ['poll', 'ping'],
        'backchannel_user_code_parameter_supported': true,
        'backchannel_authentication_request_signing_alg_values_supported': [
          'PS256',
        ],
        'bank_extension': 'value',
      });
      expect(metadata.deliveryModesSupported, contains(CibaDeliveryMode.poll));
      expect(metadata.extensions['bank_extension'], 'value');
      validator.validateMetadata(metadata);
    });
  });

  group('pure CIBA poll state machine', () {
    late FixedOpenBankingClock clock;
    late CibaSession session;
    late CibaPollCoordinator coordinator;

    setUp(() {
      clock = FixedOpenBankingClock(DateTime.utc(2026, 8, 13, 10));
      session = CibaSession(
        id: const AuthorizationSessionId('ciba-session'),
        providerId: const ProviderId('fake'),
        deliveryMode: CibaDeliveryMode.poll,
        authenticationRequestIdHash: 'hash-only',
        createdAt: clock.now(),
        expiresAt: clock.now().add(const Duration(minutes: 5)),
        pollInterval: const Duration(seconds: 5),
      );
      coordinator = CibaPollCoordinator(session, clock);
    });

    test('concurrent poll is forbidden', () {
      coordinator.beginPoll();
      expect(coordinator.beginPoll, throwsA(isA<OpenBankingValidationError>()));
    });

    test('poll before interval returns slow_down', () {
      coordinator.beginPoll();
      coordinator.completePoll(error: CibaTokenError.authorizationPending);
      clock.advance(const Duration(seconds: 4));
      expect(
        coordinator.beginPoll,
        throwsA(
          isA<OpenBankingValidationError>().having(
            (error) => error.code,
            'code',
            'slow_down',
          ),
        ),
      );
    });

    test('slow_down response increases future interval', () {
      coordinator.beginPoll();
      coordinator.completePoll(error: CibaTokenError.slowDown);
      expect(session.pollInterval, const Duration(seconds: 10));
    });

    test('successful token response completes the session', () {
      coordinator.beginPoll();
      coordinator.completePoll(
        token: const OAuthTokenResponse(
          accessToken: SecretValue('access'),
          tokenType: 'Bearer',
          expiresIn: Duration(minutes: 5),
          scopes: {'openid'},
        ),
      );
      expect(session.status, CibaSessionStatus.completed);
    });

    test('expired session never polls', () {
      clock.advance(const Duration(minutes: 6));
      expect(
        coordinator.beginPoll,
        throwsA(
          isA<OpenBankingValidationError>().having(
            (error) => error.code,
            'code',
            'expired_token',
          ),
        ),
      );
      expect(session.status, CibaSessionStatus.expired);
    });
  });
}
