import '../../core/errors.dart';
import '../../core/secrets.dart';
import '../../core/types.dart';
import 'models.dart';

class FapiSecurityProfileValidator {
  const FapiSecurityProfileValidator();

  static const _extendedAuthMethods = {
    OAuthClientAuthenticationMethod.privateKeyJwt,
    OAuthClientAuthenticationMethod.tlsClientAuth,
  };

  void validateAuthorizationRequest(
    AuthorizationRequest request, {
    required Set<Uri> registeredRedirectUris,
    bool oidc = true,
    bool productionProfile = true,
  }) {
    if (oidc && !request.scopes.contains('openid')) {
      throw const OpenBankingValidationError(
        'invalid_scope',
        'OIDC authorization requires the openid scope.',
      );
    }
    if (request.responseType != 'code' &&
        request.responseType != 'code id_token') {
      throw const OpenBankingValidationError(
        'unsupported_response_type',
        'Only code and code id_token response types are supported.',
      );
    }
    if (!registeredRedirectUris.contains(request.redirectUri)) {
      throw const OpenBankingValidationError(
        'redirect_uri_mismatch',
        'redirect_uri must exactly match a registered URI.',
      );
    }
    if (productionProfile && request.redirectUri.scheme != 'https') {
      throw const OpenBankingValidationError(
        'https_required',
        'Production redirect URIs must use HTTPS.',
      );
    }
    if (request.state.byteLength < 20 || request.nonce.byteLength < 20) {
      throw const OpenBankingValidationError(
        'insufficient_entropy',
        'state and nonce must each contain at least 20 UTF-8 bytes.',
      );
    }
    if (request.codeChallenge.isEmpty ||
        request.codeChallengeMethod != PkceChallengeMethod.s256) {
      throw const OpenBankingValidationError(
        'invalid_pkce',
        'PKCE with the S256 method is mandatory.',
      );
    }
  }

  void validateExtendedAuthorizationRequest({
    required AuthorizationRequest request,
    required SignedAuthorizationRequestObject requestObject,
    required AuthorizationServerMetadata server,
    required OAuthClientMetadata client,
    required DateTime now,
  }) {
    validateAuthorizationRequest(
      request,
      registeredRedirectUris: client.redirectUris,
    );
    validateClientMetadata(client);
    if (!_extendedAuthMethods.contains(client.tokenEndpointAuthMethod)) {
      throw const OpenBankingValidationError(
        'invalid_client_authentication',
        'The extended profile permits private_key_jwt or tls_client_auth only.',
      );
    }
    if (!requestObject.signatureVerified) {
      throw const OpenBankingValidationError(
        'invalid_request_object_signature',
        'The signed authorization request object was not JOSE-verified.',
      );
    }
    final claims = requestObject.claims;
    if (claims.issuer != request.clientId.value) {
      throw const OpenBankingValidationError(
        'invalid_request_object_issuer',
        'The request object issuer must be the OAuth client identifier.',
      );
    }
    if (!claims.audience.contains(server.issuer.toString())) {
      throw const OpenBankingValidationError(
        'invalid_request_object_audience',
        'The request object audience must contain the authorization issuer.',
      );
    }
    if (claims.expiresAt.difference(claims.notBefore) >
            const Duration(minutes: 60) ||
        !claims.expiresAt.isAfter(claims.notBefore)) {
      throw const OpenBankingValidationError(
        'invalid_request_object_lifetime',
        'Request object exp must be after nbf and no more than 60 minutes later.',
      );
    }
    if (claims.expiresAt.isBefore(now) || claims.notBefore.isAfter(now)) {
      throw const OpenBankingValidationError(
        'invalid_request_object_time',
        'The request object is expired or not yet valid.',
      );
    }
    _requireSignedParameter(
      claims.parameters,
      'client_id',
      request.clientId.value,
    );
    _requireSignedParameter(
      claims.parameters,
      'redirect_uri',
      request.redirectUri.toString(),
    );
    _requireSignedParameter(
      claims.parameters,
      'response_type',
      request.responseType,
    );
    final isJarm = request.responseMode?.contains('jwt') ?? false;
    final isHybrid = request.responseType == 'code id_token';
    if (!isJarm && !isHybrid) {
      throw const OpenBankingValidationError(
        'response_protection_required',
        'The authorization response must use JARM or code id_token.',
      );
    }
  }

  void validateClientMetadata(OAuthClientMetadata client) {
    if (client.redirectUris.isEmpty) {
      throw const OpenBankingValidationError(
        'invalid_client_metadata',
        'At least one redirect URI is required.',
      );
    }
    if (client.tokenEndpointAuthMethod ==
        OAuthClientAuthenticationMethod.none) {
      throw const OpenBankingValidationError(
        'public_client_forbidden',
        'Public OAuth clients are forbidden by the extended profile.',
      );
    }
    if (!client.grantTypes.contains('authorization_code')) {
      throw const OpenBankingValidationError(
        'invalid_client_metadata',
        'The authorization_code grant must be registered.',
      );
    }
  }

  void validateAuthorizationServerMetadata(
    AuthorizationServerMetadata metadata,
  ) {
    if (metadata.issuer.scheme != 'https' ||
        metadata.authorizationEndpoint.scheme != 'https' ||
        metadata.tokenEndpoint.scheme != 'https' ||
        metadata.jwksUri.scheme != 'https') {
      throw const OpenBankingValidationError(
        'invalid_server_metadata',
        'Issuer, authorization, token and JWKS endpoints must use HTTPS.',
      );
    }
    if (!metadata.codeChallengeMethodsSupported.contains('S256')) {
      throw const OpenBankingValidationError(
        'invalid_server_metadata',
        'Authorization server metadata must advertise PKCE S256.',
      );
    }
  }

  void validateClientAssertion({
    required ClientAssertionClaims claims,
    required OAuthClientId clientId,
    required Uri tokenEndpoint,
    required DateTime now,
  }) {
    if (claims.issuer != clientId || claims.subject != clientId) {
      throw const OpenBankingValidationError(
        'invalid_client_assertion_subject',
        'Client assertion iss and sub must identify the OAuth client.',
      );
    }
    if (!claims.audience.contains(tokenEndpoint.toString())) {
      throw const OpenBankingValidationError(
        'invalid_client_assertion_audience',
        'Client assertion audience must contain the token endpoint.',
      );
    }
    if (claims.jwtId.isEmpty ||
        !claims.expiresAt.isAfter(now) ||
        claims.issuedAt.isAfter(now.add(const Duration(seconds: 30))) ||
        claims.expiresAt.difference(claims.issuedAt) >
            const Duration(minutes: 5)) {
      throw const OpenBankingValidationError(
        'invalid_client_assertion_time',
        'Client assertion requires jti and a valid lifetime of at most 5 minutes.',
      );
    }
  }

  void validateClientAuthentication(OAuthClientAuthentication authentication) {
    switch (authentication.method) {
      case OAuthClientAuthenticationMethod.privateKeyJwt:
        if (authentication.clientAssertion == null) {
          throw const OpenBankingValidationError(
            'client_assertion_required',
            'private_key_jwt requires a signed client assertion.',
          );
        }
      case OAuthClientAuthenticationMethod.tlsClientAuth:
        if (authentication.certificateThumbprint == null ||
            authentication.certificateThumbprint!.isEmpty) {
          throw const OpenBankingValidationError(
            'client_certificate_required',
            'tls_client_auth requires an mTLS certificate thumbprint.',
          );
        }
      case OAuthClientAuthenticationMethod.clientSecretBasic:
      case OAuthClientAuthenticationMethod.clientSecretJwt:
      case OAuthClientAuthenticationMethod.clientSecretPost:
      case OAuthClientAuthenticationMethod.none:
        throw const OpenBankingValidationError(
          'invalid_client_authentication',
          'The extended profile permits private_key_jwt or tls_client_auth only.',
        );
    }
  }

  void validateAuthorizationCodeTokenRequest(
    OAuthAuthorizationCodeTokenRequest request, {
    required Set<Uri> registeredRedirectUris,
  }) {
    if (!registeredRedirectUris.contains(request.redirectUri)) {
      throw const OpenBankingValidationError(
        'redirect_uri_mismatch',
        'Token request redirect_uri must exactly match the registered URI.',
      );
    }
    if (request.codeVerifier.byteLength < 43 ||
        request.codeVerifier.byteLength > 128) {
      throw const OpenBankingValidationError(
        'invalid_code_verifier',
        'PKCE code_verifier must contain 43..128 bytes.',
      );
    }
  }

  void _requireSignedParameter(
    Map<String, Object?> parameters,
    String name,
    String expected,
  ) {
    if (parameters[name] != expected) {
      throw OpenBankingValidationError(
        'invalid_signed_parameter',
        '$name must be present in the request object and match the request.',
      );
    }
  }
}

class IdTokenValidator {
  const IdTokenValidator();

  void validate(IdTokenValidationInput input) {
    final claims = input.claims;
    if (!input.joseVerified) {
      throw const OpenBankingValidationError(
        'invalid_id_token_signature',
        'ID Token JOSE validation must succeed before claim validation.',
      );
    }
    if (claims.issuer != input.expectedIssuer) {
      throw const OpenBankingValidationError(
        'invalid_id_token_issuer',
        'Unexpected ID Token issuer.',
      );
    }
    if (!claims.audience.contains(input.expectedClientId.value)) {
      throw const OpenBankingValidationError(
        'invalid_id_token_audience',
        'ID Token audience does not contain the OAuth client.',
      );
    }
    if (claims.audience.length > 1 &&
        claims.authorizedParty != input.expectedClientId.value) {
      throw const OpenBankingValidationError(
        'invalid_authorized_party',
        'azp must identify the OAuth client for a multi-audience ID Token.',
      );
    }
    final earliestAccepted = input.now.subtract(input.clockSkew);
    final latestAccepted = input.now.add(input.clockSkew);
    if (claims.expiresAt.isBefore(earliestAccepted)) {
      throw const OpenBankingValidationError(
        'expired_id_token',
        'ID Token has expired.',
      );
    }
    if (claims.issuedAt.isAfter(latestAccepted) ||
        (claims.notBefore?.isAfter(latestAccepted) ?? false)) {
      throw const OpenBankingValidationError(
        'id_token_not_yet_valid',
        'ID Token is not yet valid.',
      );
    }
    if (claims.nonce == null || !input.expectedNonce.matches(claims.nonce!)) {
      throw const OpenBankingValidationError(
        'invalid_nonce',
        'ID Token nonce does not match the authorization session.',
      );
    }
    if (!input.authorizationCodeHashVerified ||
        !input.accessTokenHashVerified) {
      throw const OpenBankingValidationError(
        'invalid_token_hash',
        'c_hash or at_hash validation failed.',
      );
    }
  }
}

class JarmValidator {
  const JarmValidator();

  void validate(JarmValidationInput input) {
    final response = input.response;
    if (!input.joseVerified) {
      throw const OpenBankingValidationError(
        'invalid_jarm_signature',
        'JARM JOSE validation must succeed before claim validation.',
      );
    }
    if (response.issuer != input.expectedIssuer ||
        !response.audience.contains(input.expectedAudience)) {
      throw const OpenBankingValidationError(
        'invalid_jarm_issuer_or_audience',
        'Unexpected JARM issuer or audience.',
      );
    }
    if (!input.expectedState.matches(response.state)) {
      throw const OpenBankingValidationError(
        'invalid_state',
        'JARM state does not match the authorization session.',
      );
    }
    final earliestAccepted = input.now.subtract(input.clockSkew);
    final latestAccepted = input.now.add(input.clockSkew);
    if (response.expiresAt.isBefore(earliestAccepted) ||
        response.issuedAt.isAfter(latestAccepted)) {
      throw const OpenBankingValidationError(
        'invalid_jarm_time',
        'JARM response is expired or issued in the future.',
      );
    }
    if (response.code == null && response.error == null) {
      throw const OpenBankingValidationError(
        'invalid_jarm_response',
        'JARM must contain either a code or an OAuth error.',
      );
    }
    if (response.code != null && response.error != null) {
      throw const OpenBankingValidationError(
        'invalid_jarm_response',
        'JARM cannot contain both a code and an OAuth error.',
      );
    }
  }
}

class CertificateBindingValidator {
  const CertificateBindingValidator();

  void validate({
    required CertificateBoundAccessToken accessToken,
    required MtlsCertificateIdentity certificate,
    required DateTime now,
  }) {
    if (certificate.notBefore.isAfter(now) ||
        certificate.notAfter.isBefore(now) ||
        certificate.sha256Thumbprint !=
            accessToken.certificateSha256Thumbprint) {
      throw const InvalidTokenBindingError();
    }
  }
}

class FapiHttpSecurityValidator {
  const FapiHttpSecurityValidator();

  void validateRequestUri(Uri uri, {bool productionProfile = true}) {
    if (productionProfile && uri.scheme != 'https') {
      throw const OpenBankingValidationError(
        'https_required',
        'Production Open Banking requests must use HTTPS.',
      );
    }
    final forbidden = uri.queryParameters.keys.any(
      (key) => key.toLowerCase() == 'access_token',
    );
    if (forbidden) {
      throw const OpenBankingValidationError(
        'token_in_query_forbidden',
        'Access tokens must never be sent in URI query parameters.',
      );
    }
  }

  void validateAccessToken({
    required CertificateBoundAccessToken token,
    required DateTime now,
    required Set<String> requiredScopes,
  }) {
    if (!token.expiresAt.isAfter(now)) {
      throw const OpenBankingValidationError(
        'expired_access_token',
        'The access token is expired.',
      );
    }
    if (!token.scopes.containsAll(requiredScopes)) {
      throw const OpenBankingValidationError(
        'insufficient_scope',
        'The access token does not cover the required scopes.',
      );
    }
  }
}

bool secretMatches(SecretValue secret, String candidate) =>
    secret.matches(candidate);
