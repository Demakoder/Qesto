import '../../core/clock.dart';
import '../../core/errors.dart';
import '../../core/secrets.dart';
import '../../core/types.dart';
import '../fapi_sec_1_6_2024/models.dart';

enum CibaDeliveryMode {
  poll('poll'),
  ping('ping'),
  push('push');

  const CibaDeliveryMode(this.wireName);

  final String wireName;
}

enum CibaSessionStatus {
  created,
  authorizationPending,
  authorized,
  accessDenied,
  expired,
  completed,
  failed,
}

enum CibaTokenError {
  authorizationPending('authorization_pending'),
  slowDown('slow_down'),
  expiredToken('expired_token'),
  accessDenied('access_denied'),
  invalidGrant('invalid_grant');

  const CibaTokenError(this.wireName);

  final String wireName;
}

class CibaProviderMetadata {
  const CibaProviderMetadata({
    required this.backchannelAuthenticationEndpoint,
    required this.deliveryModesSupported,
    required this.userCodeParameterSupported,
    required this.authenticationRequestSigningAlgorithms,
    this.extensions = const {},
  });

  final Uri backchannelAuthenticationEndpoint;
  final Set<CibaDeliveryMode> deliveryModesSupported;
  final bool userCodeParameterSupported;
  final Set<String> authenticationRequestSigningAlgorithms;
  final Map<String, Object?> extensions;
}

class CibaAuthenticationRequest {
  const CibaAuthenticationRequest({
    required this.clientId,
    required this.scopes,
    required this.deliveryMode,
    this.loginHint,
    this.idTokenHint,
    this.loginHintToken,
    this.userCode,
    this.bindingMessage,
    this.requestedExpiry,
    this.clientNotificationToken,
    this.acrValues = const {},
  });

  final OAuthClientId clientId;
  final Set<String> scopes;
  final CibaDeliveryMode deliveryMode;
  final String? loginHint;
  final SecretValue? idTokenHint;
  final SecretValue? loginHintToken;
  final SecretValue? userCode;
  final String? bindingMessage;
  final Duration? requestedExpiry;
  final SecretValue? clientNotificationToken;
  final Set<String> acrValues;
}

class CibaAuthenticationResponse {
  const CibaAuthenticationResponse({
    required this.authenticationRequestId,
    required this.expiresIn,
    required this.interval,
  });

  final SecretValue authenticationRequestId;
  final Duration expiresIn;
  final Duration interval;
}

class CibaNotification {
  const CibaNotification({
    required this.authenticationRequestId,
    required this.clientNotificationToken,
  });

  final SecretValue authenticationRequestId;
  final SecretValue clientNotificationToken;
}

class CibaPushNotification extends CibaNotification {
  const CibaPushNotification({
    required super.authenticationRequestId,
    required super.clientNotificationToken,
    required this.tokenResponse,
  });

  final OAuthTokenResponse tokenResponse;
}

class CibaSession {
  CibaSession({
    required this.id,
    required this.providerId,
    required this.deliveryMode,
    required this.authenticationRequestIdHash,
    required this.createdAt,
    required this.expiresAt,
    required this.pollInterval,
    this.status = CibaSessionStatus.authorizationPending,
  });

  final AuthorizationSessionId id;
  final ProviderId providerId;
  final CibaDeliveryMode deliveryMode;
  final String authenticationRequestIdHash;
  final DateTime createdAt;
  final DateTime expiresAt;
  Duration pollInterval;
  CibaSessionStatus status;
  DateTime? lastPollAt;
  bool pollInFlight = false;
  CibaTokenError? lastError;
}

class CibaValidator {
  const CibaValidator();

  void validateRequest(CibaAuthenticationRequest request) {
    final hints = [
      request.loginHint != null,
      request.idTokenHint != null,
      request.loginHintToken != null,
    ].where((present) => present).length;
    if (hints != 1) {
      throw const OpenBankingValidationError(
        'invalid_ciba_hint',
        'Exactly one of login_hint, id_token_hint or login_hint_token is required.',
      );
    }
    if (!request.scopes.contains('openid')) {
      throw const OpenBankingValidationError(
        'invalid_scope',
        'CIBA requires the openid scope.',
      );
    }
    if ((request.bindingMessage?.length ?? 0) > 100) {
      throw const OpenBankingValidationError(
        'invalid_binding_message',
        'binding_message must not exceed 100 characters.',
      );
    }
    if (request.requestedExpiry != null &&
        request.requestedExpiry!.inSeconds <= 0) {
      throw const OpenBankingValidationError(
        'invalid_requested_expiry',
        'requested_expiry must be positive.',
      );
    }
    if (request.deliveryMode != CibaDeliveryMode.poll) {
      final token = request.clientNotificationToken;
      if (token == null || token.byteLength < 20 || token.byteLength > 1024) {
        throw const OpenBankingValidationError(
          'invalid_client_notification_token',
          'Ping and push require a 20..1024-byte client notification token.',
        );
      }
    }
  }

  void validateMetadata(CibaProviderMetadata metadata) {
    if (metadata.backchannelAuthenticationEndpoint.scheme != 'https') {
      throw const OpenBankingValidationError(
        'invalid_ciba_metadata',
        'The backchannel authentication endpoint must use HTTPS.',
      );
    }
    if (metadata.deliveryModesSupported.isEmpty) {
      throw const OpenBankingValidationError(
        'invalid_ciba_metadata',
        'At least one CIBA delivery mode must be advertised.',
      );
    }
  }
}

class CibaMetadataParser {
  const CibaMetadataParser();

  CibaProviderMetadata parse(Map<String, Object?> json) {
    const known = {
      'backchannel_authentication_endpoint',
      'backchannel_token_delivery_modes_supported',
      'backchannel_user_code_parameter_supported',
      'backchannel_authentication_request_signing_alg_values_supported',
    };
    final endpoint = json['backchannel_authentication_endpoint'];
    if (endpoint is! String || endpoint.isEmpty) {
      throw const OpenBankingValidationError(
        'invalid_ciba_metadata',
        'backchannel_authentication_endpoint is required.',
      );
    }
    final rawModes = json['backchannel_token_delivery_modes_supported'];
    final modes = <CibaDeliveryMode>{};
    if (rawModes is List) {
      for (final raw in rawModes.whereType<String>()) {
        for (final mode in CibaDeliveryMode.values) {
          if (mode.wireName == raw) modes.add(mode);
        }
      }
    }
    return CibaProviderMetadata(
      backchannelAuthenticationEndpoint: Uri.parse(endpoint),
      deliveryModesSupported: modes,
      userCodeParameterSupported:
          json['backchannel_user_code_parameter_supported'] as bool? ?? false,
      authenticationRequestSigningAlgorithms:
          (json['backchannel_authentication_request_signing_alg_values_supported']
                  as List?)
              ?.whereType<String>()
              .toSet() ??
          const {},
      extensions: Map.fromEntries(
        json.entries.where((entry) => !known.contains(entry.key)),
      ),
    );
  }
}

class CibaPollCoordinator {
  CibaPollCoordinator(this.session, this.clock);

  final CibaSession session;
  final OpenBankingClock clock;

  void beginPoll() {
    final now = clock.now();
    if (session.deliveryMode != CibaDeliveryMode.poll) {
      throw const OpenBankingValidationError(
        'invalid_ciba_mode',
        'Token polling is available only in poll mode.',
      );
    }
    if (!now.isBefore(session.expiresAt)) {
      session.status = CibaSessionStatus.expired;
      session.lastError = CibaTokenError.expiredToken;
      throw const OpenBankingValidationError(
        'expired_token',
        'The CIBA authentication request has expired.',
      );
    }
    if (session.pollInFlight) {
      throw const OpenBankingValidationError(
        'concurrent_poll_forbidden',
        'Only one CIBA token poll may be in flight.',
      );
    }
    final lastPoll = session.lastPollAt;
    if (lastPoll != null && now.difference(lastPoll) < session.pollInterval) {
      session.lastError = CibaTokenError.slowDown;
      throw const OpenBankingValidationError(
        'slow_down',
        'CIBA token polling started before the configured interval elapsed.',
      );
    }
    session.pollInFlight = true;
    session.lastPollAt = now;
  }

  void completePoll({OAuthTokenResponse? token, CibaTokenError? error}) {
    if (!session.pollInFlight) {
      throw const OpenBankingValidationError(
        'poll_not_started',
        'beginPoll must be called before completePoll.',
      );
    }
    session.pollInFlight = false;
    if (token != null && error != null) {
      throw const OpenBankingValidationError(
        'invalid_ciba_poll_result',
        'A poll result cannot contain both a token and an error.',
      );
    }
    if (token != null) {
      session.status = CibaSessionStatus.completed;
      session.lastError = null;
      return;
    }
    session.lastError = error;
    switch (error) {
      case CibaTokenError.authorizationPending:
        session.status = CibaSessionStatus.authorizationPending;
      case CibaTokenError.slowDown:
        session.pollInterval += const Duration(seconds: 5);
        session.status = CibaSessionStatus.authorizationPending;
      case CibaTokenError.expiredToken:
        session.status = CibaSessionStatus.expired;
      case CibaTokenError.accessDenied:
        session.status = CibaSessionStatus.accessDenied;
      case CibaTokenError.invalidGrant:
        session.status = CibaSessionStatus.failed;
      case null:
        session.status = CibaSessionStatus.failed;
    }
  }
}
