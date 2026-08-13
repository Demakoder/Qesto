import '../../core/secrets.dart';
import '../../core/types.dart';

enum PkceChallengeMethod { s256, plain }

enum OAuthClientAuthenticationMethod {
  privateKeyJwt('private_key_jwt'),
  tlsClientAuth('tls_client_auth'),
  clientSecretJwt('client_secret_jwt'),
  clientSecretBasic('client_secret_basic'),
  clientSecretPost('client_secret_post'),
  none('none');

  const OAuthClientAuthenticationMethod(this.wireName);

  final String wireName;
}

class AuthorizationRequest {
  const AuthorizationRequest({
    required this.scopes,
    required this.responseType,
    required this.clientId,
    required this.redirectUri,
    required this.state,
    required this.nonce,
    required this.codeChallenge,
    this.codeChallengeMethod = PkceChallengeMethod.s256,
    this.request,
    this.requestUri,
    this.responseMode,
    this.acrValues = const [],
    this.prompt,
    this.maxAge,
  });

  final Set<String> scopes;
  final String responseType;
  final OAuthClientId clientId;
  final Uri redirectUri;
  final SecretValue state;
  final SecretValue nonce;
  final String codeChallenge;
  final PkceChallengeMethod codeChallengeMethod;
  final String? request;
  final Uri? requestUri;
  final String? responseMode;
  final List<String> acrValues;
  final String? prompt;
  final Duration? maxAge;
}

class AuthorizationRequestObjectClaims {
  const AuthorizationRequestObjectClaims({
    required this.issuer,
    required this.audience,
    required this.issuedAt,
    required this.notBefore,
    required this.expiresAt,
    required this.parameters,
  });

  final String issuer;
  final Set<String> audience;
  final DateTime issuedAt;
  final DateTime notBefore;
  final DateTime expiresAt;
  final Map<String, Object?> parameters;
}

class SignedAuthorizationRequestObject {
  const SignedAuthorizationRequestObject({
    required this.compactJwt,
    required this.claims,
    required this.signatureVerified,
  });

  final String compactJwt;
  final AuthorizationRequestObjectClaims claims;
  final bool signatureVerified;
}

class OAuthAuthorizationCodeTokenRequest {
  const OAuthAuthorizationCodeTokenRequest({
    required this.code,
    required this.redirectUri,
    required this.clientId,
    required this.codeVerifier,
  });

  final SecretValue code;
  final Uri redirectUri;
  final OAuthClientId clientId;
  final SecretValue codeVerifier;
}

class OAuthRefreshTokenRequest {
  const OAuthRefreshTokenRequest({
    required this.refreshToken,
    required this.clientId,
    this.scopes = const {},
  });

  final SecretValue refreshToken;
  final OAuthClientId clientId;
  final Set<String> scopes;
}

class OAuthTokenResponse {
  const OAuthTokenResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    required this.scopes,
    this.refreshToken,
    this.idToken,
    this.extensions = const {},
  });

  final SecretValue accessToken;
  final String tokenType;
  final Duration expiresIn;
  final Set<String> scopes;
  final SecretValue? refreshToken;
  final SecretValue? idToken;
  final Map<String, Object?> extensions;

  Map<String, Object?> toSafeJson() => {
    ...extensions,
    'access_token': accessToken,
    'token_type': tokenType,
    'expires_in': expiresIn.inSeconds,
    'scope': scopes.join(' '),
    if (refreshToken != null) 'refresh_token': refreshToken,
    if (idToken != null) 'id_token': idToken,
  };
}

class ClientAssertionClaims {
  const ClientAssertionClaims({
    required this.issuer,
    required this.subject,
    required this.audience,
    required this.jwtId,
    required this.issuedAt,
    required this.expiresAt,
  });

  final OAuthClientId issuer;
  final OAuthClientId subject;
  final Set<String> audience;
  final String jwtId;
  final DateTime issuedAt;
  final DateTime expiresAt;
}

class OAuthClientAuthentication {
  const OAuthClientAuthentication({
    required this.method,
    this.clientAssertion,
    this.certificateThumbprint,
  });

  final OAuthClientAuthenticationMethod method;
  final SecretValue? clientAssertion;
  final String? certificateThumbprint;
}

class AuthorizationServerMetadata {
  const AuthorizationServerMetadata({
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.jwksUri,
    required this.responseTypesSupported,
    required this.tokenEndpointAuthMethodsSupported,
    this.pushedAuthorizationRequestEndpoint,
    this.backchannelAuthenticationEndpoint,
    this.responseModesSupported = const {},
    this.scopesSupported = const {},
    this.codeChallengeMethodsSupported = const {},
    this.extensions = const {},
  });

  final Uri issuer;
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final Uri jwksUri;
  final Uri? pushedAuthorizationRequestEndpoint;
  final Uri? backchannelAuthenticationEndpoint;
  final Set<String> responseTypesSupported;
  final Set<String> responseModesSupported;
  final Set<String> scopesSupported;
  final Set<String> codeChallengeMethodsSupported;
  final Set<String> tokenEndpointAuthMethodsSupported;
  final Map<String, Object?> extensions;
}

class OAuthClientMetadata {
  const OAuthClientMetadata({
    required this.clientId,
    required this.redirectUris,
    required this.tokenEndpointAuthMethod,
    required this.grantTypes,
    required this.responseTypes,
    this.jwksUri,
    this.applicationType = 'web',
    this.extensions = const {},
  });

  final OAuthClientId clientId;
  final Set<Uri> redirectUris;
  final OAuthClientAuthenticationMethod tokenEndpointAuthMethod;
  final Set<String> grantTypes;
  final Set<String> responseTypes;
  final Uri? jwksUri;
  final String applicationType;
  final Map<String, Object?> extensions;
}

class IdTokenClaims {
  const IdTokenClaims({
    required this.issuer,
    required this.subject,
    required this.audience,
    required this.expiresAt,
    required this.issuedAt,
    this.notBefore,
    this.nonce,
    this.authorizationCodeHash,
    this.accessTokenHash,
    this.authenticationRequestId,
    this.refreshTokenHash,
    this.authenticationTime,
    this.acr,
    this.authorizedParty,
    this.extensions = const {},
  });

  final String issuer;
  final String subject;
  final Set<String> audience;
  final DateTime expiresAt;
  final DateTime issuedAt;
  final DateTime? notBefore;
  final String? nonce;
  final String? authorizationCodeHash;
  final String? accessTokenHash;
  final String? authenticationRequestId;
  final String? refreshTokenHash;
  final DateTime? authenticationTime;
  final String? acr;
  final String? authorizedParty;
  final Map<String, Object?> extensions;
}

class IdTokenValidationInput {
  const IdTokenValidationInput({
    required this.claims,
    required this.joseVerified,
    required this.expectedIssuer,
    required this.expectedClientId,
    required this.expectedNonce,
    required this.now,
    this.clockSkew = const Duration(seconds: 30),
    this.authorizationCodeHashVerified = true,
    this.accessTokenHashVerified = true,
  });

  final IdTokenClaims claims;
  final bool joseVerified;
  final String expectedIssuer;
  final OAuthClientId expectedClientId;
  final SecretValue expectedNonce;
  final DateTime now;
  final Duration clockSkew;
  final bool authorizationCodeHashVerified;
  final bool accessTokenHashVerified;
}

class JoseHeader {
  const JoseHeader({
    required this.algorithm,
    this.keyId,
    this.type,
    this.contentType,
    this.x509Sha256Thumbprint,
    this.encryptionAlgorithm,
    this.extensions = const {},
  });

  final String algorithm;
  final String? keyId;
  final String? type;
  final String? contentType;
  final String? x509Sha256Thumbprint;
  final String? encryptionAlgorithm;
  final Map<String, Object?> extensions;
}

class JsonWebKey {
  const JsonWebKey({
    required this.keyType,
    required this.use,
    required this.algorithm,
    required this.keyId,
    required this.parameters,
  });

  final String keyType;
  final String? use;
  final String? algorithm;
  final String? keyId;
  final Map<String, Object?> parameters;
}

class JsonWebKeySet {
  const JsonWebKeySet(this.keys);

  final List<JsonWebKey> keys;
}

class JarmResponse {
  const JarmResponse({
    required this.issuer,
    required this.audience,
    required this.expiresAt,
    required this.issuedAt,
    required this.state,
    this.code,
    this.error,
    this.errorDescription,
    this.extensions = const {},
  });

  final String issuer;
  final Set<String> audience;
  final DateTime expiresAt;
  final DateTime issuedAt;
  final String state;
  final SecretValue? code;
  final String? error;
  final String? errorDescription;
  final Map<String, Object?> extensions;
}

class JarmValidationInput {
  const JarmValidationInput({
    required this.response,
    required this.joseVerified,
    required this.expectedIssuer,
    required this.expectedAudience,
    required this.expectedState,
    required this.now,
    this.clockSkew = const Duration(seconds: 30),
  });

  final JarmResponse response;
  final bool joseVerified;
  final String expectedIssuer;
  final String expectedAudience;
  final SecretValue expectedState;
  final DateTime now;
  final Duration clockSkew;
}

class MtlsCertificateIdentity {
  const MtlsCertificateIdentity({
    required this.alias,
    required this.sha256Thumbprint,
    required this.notBefore,
    required this.notAfter,
    required this.subject,
    required this.issuer,
  });

  final String alias;
  final String sha256Thumbprint;
  final DateTime notBefore;
  final DateTime notAfter;
  final String subject;
  final String issuer;
}

class CertificateBoundAccessToken {
  const CertificateBoundAccessToken({
    required this.token,
    required this.certificateSha256Thumbprint,
    required this.expiresAt,
    required this.scopes,
  });

  final SecretValue token;
  final String certificateSha256Thumbprint;
  final DateTime expiresAt;
  final Set<String> scopes;
}
