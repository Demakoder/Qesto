import '../../core/errors.dart';
import '../../core/secrets.dart';
import '../../core/types.dart';
import 'models.dart';

class FapiMetadataParser {
  const FapiMetadataParser();

  static const _knownAuthorizationServerKeys = {
    'issuer',
    'authorization_endpoint',
    'token_endpoint',
    'jwks_uri',
    'pushed_authorization_request_endpoint',
    'backchannel_authentication_endpoint',
    'response_types_supported',
    'response_modes_supported',
    'scopes_supported',
    'code_challenge_methods_supported',
    'token_endpoint_auth_methods_supported',
  };

  AuthorizationServerMetadata parseAuthorizationServer(
    Map<String, Object?> json,
  ) {
    final jwksUri = _requiredUri(json, 'jwks_uri');
    return AuthorizationServerMetadata(
      issuer: _requiredUri(json, 'issuer'),
      authorizationEndpoint: _requiredUri(json, 'authorization_endpoint'),
      tokenEndpoint: _requiredUri(json, 'token_endpoint'),
      jwksUri: jwksUri,
      pushedAuthorizationRequestEndpoint: _optionalUri(
        json['pushed_authorization_request_endpoint'],
      ),
      backchannelAuthenticationEndpoint: _optionalUri(
        json['backchannel_authentication_endpoint'],
      ),
      responseTypesSupported: _strings(json['response_types_supported']),
      responseModesSupported: _strings(json['response_modes_supported']),
      scopesSupported: _strings(json['scopes_supported']),
      codeChallengeMethodsSupported: _strings(
        json['code_challenge_methods_supported'],
      ),
      tokenEndpointAuthMethodsSupported: _strings(
        json['token_endpoint_auth_methods_supported'],
      ),
      extensions: _extensions(json, _knownAuthorizationServerKeys),
    );
  }

  OAuthClientMetadata parseClient(Map<String, Object?> json) {
    const known = {
      'client_id',
      'redirect_uris',
      'token_endpoint_auth_method',
      'grant_types',
      'response_types',
      'jwks_uri',
      'application_type',
    };
    final method = _parseClientAuth(
      _requiredString(json, 'token_endpoint_auth_method'),
    );
    return OAuthClientMetadata(
      clientId: OAuthClientId(_requiredString(json, 'client_id')),
      redirectUris: _strings(json['redirect_uris']).map(Uri.parse).toSet(),
      tokenEndpointAuthMethod: method,
      grantTypes: _strings(json['grant_types']),
      responseTypes: _strings(json['response_types']),
      jwksUri: _optionalUri(json['jwks_uri']),
      applicationType: json['application_type'] as String? ?? 'web',
      extensions: _extensions(json, known),
    );
  }

  OAuthTokenResponse parseTokenResponse(Map<String, Object?> json) {
    const known = {
      'access_token',
      'token_type',
      'expires_in',
      'scope',
      'refresh_token',
      'id_token',
    };
    final expires = json['expires_in'];
    if (expires is! num || expires <= 0) {
      throw const OpenBankingValidationError(
        'invalid_token_response',
        'expires_in must be a positive number of seconds.',
      );
    }
    return OAuthTokenResponse(
      accessToken: SecretValue(_requiredString(json, 'access_token')),
      tokenType: _requiredString(json, 'token_type'),
      expiresIn: Duration(seconds: expires.toInt()),
      scopes: _scope(json['scope']),
      refreshToken: _optionalSecret(json['refresh_token']),
      idToken: _optionalSecret(json['id_token']),
      extensions: _extensions(json, known),
    );
  }

  IdTokenClaims parseIdTokenClaims(Map<String, Object?> json) {
    const known = {
      'iss',
      'sub',
      'aud',
      'exp',
      'iat',
      'nbf',
      'nonce',
      'c_hash',
      'at_hash',
      'urn:openid:params:jwt:claim:auth_req_id',
      'urn:openid:params:jwt:claim:rt_hash',
      'auth_time',
      'acr',
      'azp',
    };
    return IdTokenClaims(
      issuer: _requiredString(json, 'iss'),
      subject: _requiredString(json, 'sub'),
      audience: _audience(json['aud']),
      expiresAt: _timestamp(json, 'exp'),
      issuedAt: _timestamp(json, 'iat'),
      notBefore: _optionalTimestamp(json['nbf']),
      nonce: json['nonce'] as String?,
      authorizationCodeHash: json['c_hash'] as String?,
      accessTokenHash: json['at_hash'] as String?,
      authenticationRequestId:
          json['urn:openid:params:jwt:claim:auth_req_id'] as String?,
      refreshTokenHash: json['urn:openid:params:jwt:claim:rt_hash'] as String?,
      authenticationTime: _optionalTimestamp(json['auth_time']),
      acr: json['acr'] as String?,
      authorizedParty: json['azp'] as String?,
      extensions: _extensions(json, known),
    );
  }

  JarmResponse parseJarmClaims(Map<String, Object?> json) {
    const known = {
      'iss',
      'aud',
      'exp',
      'iat',
      'state',
      'code',
      'error',
      'error_description',
    };
    return JarmResponse(
      issuer: _requiredString(json, 'iss'),
      audience: _audience(json['aud']),
      expiresAt: _timestamp(json, 'exp'),
      issuedAt: _timestamp(json, 'iat'),
      state: _requiredString(json, 'state'),
      code: _optionalSecret(json['code']),
      error: json['error'] as String?,
      errorDescription: json['error_description'] as String?,
      extensions: _extensions(json, known),
    );
  }

  OAuthClientAuthenticationMethod _parseClientAuth(String value) {
    for (final method in OAuthClientAuthenticationMethod.values) {
      if (method.wireName == value) return method;
    }
    throw OpenBankingValidationError(
      'unsupported_client_authentication',
      'Unknown token_endpoint_auth_method: $value.',
    );
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw OpenBankingValidationError(
      'invalid_metadata',
      '$key must be a non-empty string.',
    );
  }
  return value;
}

Uri _requiredUri(Map<String, Object?> json, String key) =>
    Uri.parse(_requiredString(json, key));

Uri? _optionalUri(Object? value) =>
    value is String && value.isNotEmpty ? Uri.parse(value) : null;

Set<String> _strings(Object? value) {
  if (value is! List) return const {};
  return value.whereType<String>().toSet();
}

Set<String> _scope(Object? value) {
  if (value is String) {
    return value.split(' ').where((item) => item.isNotEmpty).toSet();
  }
  return _strings(value);
}

Set<String> _audience(Object? value) {
  if (value is String && value.isNotEmpty) return {value};
  final result = _strings(value);
  if (result.isEmpty) {
    throw const OpenBankingValidationError(
      'invalid_claims',
      'aud must contain at least one audience.',
    );
  }
  return result;
}

DateTime _timestamp(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! num) {
    throw OpenBankingValidationError(
      'invalid_claims',
      '$key must be a NumericDate.',
    );
  }
  return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000, isUtc: true);
}

DateTime? _optionalTimestamp(Object? value) => value is num
    ? DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000, isUtc: true)
    : null;

SecretValue? _optionalSecret(Object? value) =>
    value is String && value.isNotEmpty ? SecretValue(value) : null;

Map<String, Object?> _extensions(
  Map<String, Object?> json,
  Set<String> known,
) => Map<String, Object?>.fromEntries(
  json.entries.where((entry) => !known.contains(entry.key)),
);
