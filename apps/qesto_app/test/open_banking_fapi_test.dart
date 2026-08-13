import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  const validator = FapiSecurityProfileValidator();
  final redirect = Uri.parse('https://qesto.invalid/callback');

  AuthorizationRequest request({
    String state = '01234567890123456789',
    String nonce = 'abcdefghijabcdefghij',
    Uri? redirectUri,
    String responseType = 'code',
    String? responseMode = 'jwt',
    Set<String> scopes = const {'openid', 'accounts'},
    PkceChallengeMethod pkceMethod = PkceChallengeMethod.s256,
  }) => AuthorizationRequest(
    scopes: scopes,
    responseType: responseType,
    clientId: const OAuthClientId('qesto-client'),
    redirectUri: redirectUri ?? redirect,
    state: SecretValue(state),
    nonce: SecretValue(nonce),
    codeChallenge: 'fixture-s256-challenge',
    codeChallengeMethod: pkceMethod,
    responseMode: responseMode,
  );

  group('base OAuth/OIDC protections', () {
    test('valid request passes', () {
      validator.validateAuthorizationRequest(
        request(),
        registeredRedirectUris: {redirect},
      );
    });

    test('short state is rejected', () {
      expect(
        () => validator.validateAuthorizationRequest(
          request(state: 'short'),
          registeredRedirectUris: {redirect},
        ),
        throwsA(
          isA<OpenBankingValidationError>().having(
            (error) => error.code,
            'code',
            'insufficient_entropy',
          ),
        ),
      );
    });

    test('short nonce is rejected', () {
      expect(
        () => validator.validateAuthorizationRequest(
          request(nonce: 'short'),
          registeredRedirectUris: {redirect},
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('OIDC request without openid is rejected', () {
      expect(
        () => validator.validateAuthorizationRequest(
          request(scopes: const {'accounts'}),
          registeredRedirectUris: {redirect},
        ),
        throwsA(
          isA<OpenBankingValidationError>().having(
            (error) => error.code,
            'code',
            'invalid_scope',
          ),
        ),
      );
    });

    test('PKCE plain method is rejected', () {
      expect(
        () => validator.validateAuthorizationRequest(
          request(pkceMethod: PkceChallengeMethod.plain),
          registeredRedirectUris: {redirect},
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('redirect URI comparison is exact', () {
      expect(
        () => validator.validateAuthorizationRequest(
          request(redirectUri: Uri.parse('https://qesto.invalid/callback/')),
          registeredRedirectUris: {redirect},
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('public HTTP redirect is rejected in production profile', () {
      final httpRedirect = Uri.parse('http://qesto.invalid/callback');
      expect(
        () => validator.validateAuthorizationRequest(
          request(redirectUri: httpRedirect),
          registeredRedirectUris: {httpRedirect},
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('access token in query is rejected', () {
      expect(
        () => const FapiHttpSecurityValidator().validateRequestUri(
          Uri.parse('https://bank.invalid/accounts?access_token=secret'),
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('token expiry and scope are enforced', () {
      final now = DateTime.utc(2026, 8, 13);
      final token = CertificateBoundAccessToken(
        token: const SecretValue('token'),
        certificateSha256Thumbprint: 'thumb',
        expiresAt: now.add(const Duration(minutes: 1)),
        scopes: const {'accounts'},
      );
      const FapiHttpSecurityValidator().validateAccessToken(
        token: token,
        now: now,
        requiredScopes: const {'accounts'},
      );
      expect(
        () => const FapiHttpSecurityValidator().validateAccessToken(
          token: token,
          now: now,
          requiredScopes: const {'balances'},
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
      expect(
        () => const FapiHttpSecurityValidator().validateAccessToken(
          token: token,
          now: now.add(const Duration(minutes: 2)),
          requiredScopes: const {'accounts'},
        ),
        throwsA(
          isA<OpenBankingValidationError>().having(
            (error) => error.code,
            'code',
            'expired_access_token',
          ),
        ),
      );
    });
  });

  group('metadata and token parsing', () {
    const parser = FapiMetadataParser();

    test('discovery preserves forward-compatible extensions', () {
      final metadata = parser.parseAuthorizationServer({
        'issuer': 'https://bank.invalid',
        'authorization_endpoint': 'https://bank.invalid/authorize',
        'token_endpoint': 'https://bank.invalid/token',
        'jwks_uri': 'https://bank.invalid/jwks',
        'response_types_supported': ['code'],
        'token_endpoint_auth_methods_supported': ['private_key_jwt'],
        'code_challenge_methods_supported': ['S256'],
        'future_cbr_field': {'enabled': true},
      });
      expect(metadata.jwksUri.path, '/jwks');
      expect(metadata.extensions, contains('future_cbr_field'));
      validator.validateAuthorizationServerMetadata(metadata);
    });

    test('jwks_uri is mandatory', () {
      expect(
        () => parser.parseAuthorizationServer({
          'issuer': 'https://bank.invalid',
          'authorization_endpoint': 'https://bank.invalid/authorize',
          'token_endpoint': 'https://bank.invalid/token',
        }),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('token response secrets remain redacted', () {
      final token = parser.parseTokenResponse({
        'access_token': 'actual-access-token',
        'token_type': 'Bearer',
        'expires_in': 300,
        'scope': 'accounts balances',
        'future': 'preserved',
      });
      expect(token.accessToken.toString(), SecretValue.redacted);
      expect(token.scopes, containsAll({'accounts', 'balances'}));
      expect(token.extensions['future'], 'preserved');
    });
  });

  group('extended FAPI profile', () {
    final server = const FapiMetadataParser().parseAuthorizationServer({
      'issuer': 'https://bank.invalid',
      'authorization_endpoint': 'https://bank.invalid/authorize',
      'token_endpoint': 'https://bank.invalid/token',
      'jwks_uri': 'https://bank.invalid/jwks',
      'response_types_supported': ['code'],
      'token_endpoint_auth_methods_supported': ['private_key_jwt'],
      'code_challenge_methods_supported': ['S256'],
    });
    final client = OAuthClientMetadata(
      clientId: const OAuthClientId('qesto-client'),
      redirectUris: {redirect},
      tokenEndpointAuthMethod: OAuthClientAuthenticationMethod.privateKeyJwt,
      grantTypes: const {'authorization_code'},
      responseTypes: const {'code'},
    );
    final now = DateTime.utc(2026, 8, 13, 10);

    SignedAuthorizationRequestObject object({
      Duration lifetime = const Duration(minutes: 10),
      bool verified = true,
    }) => SignedAuthorizationRequestObject(
      compactJwt: 'header.payload.signature',
      signatureVerified: verified,
      claims: AuthorizationRequestObjectClaims(
        issuer: 'qesto-client',
        audience: const {'https://bank.invalid'},
        issuedAt: now,
        notBefore: now,
        expiresAt: now.add(lifetime),
        parameters: {
          'client_id': 'qesto-client',
          'redirect_uri': redirect.toString(),
          'response_type': 'code',
        },
      ),
    );

    test('signed request object with JARM passes', () {
      validator.validateExtendedAuthorizationRequest(
        request: request(),
        requestObject: object(),
        server: server,
        client: client,
        now: now,
      );
    });

    test('request object lifetime over 60 minutes is rejected', () {
      expect(
        () => validator.validateExtendedAuthorizationRequest(
          request: request(),
          requestObject: object(lifetime: const Duration(minutes: 61)),
          server: server,
          client: client,
          now: now,
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('unsigned request object is rejected', () {
      expect(
        () => validator.validateExtendedAuthorizationRequest(
          request: request(),
          requestObject: object(verified: false),
          server: server,
          client: client,
          now: now,
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('wrong request object audience is rejected', () {
      final wrongAudience = SignedAuthorizationRequestObject(
        compactJwt: 'header.payload.signature',
        signatureVerified: true,
        claims: AuthorizationRequestObjectClaims(
          issuer: 'qesto-client',
          audience: const {'https://other.invalid'},
          issuedAt: now,
          notBefore: now,
          expiresAt: now.add(const Duration(minutes: 10)),
          parameters: {
            'client_id': 'qesto-client',
            'redirect_uri': redirect.toString(),
            'response_type': 'code',
          },
        ),
      );
      expect(
        () => validator.validateExtendedAuthorizationRequest(
          request: request(),
          requestObject: wrongAudience,
          server: server,
          client: client,
          now: now,
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('public client is rejected', () {
      final publicClient = OAuthClientMetadata(
        clientId: const OAuthClientId('qesto-client'),
        redirectUris: {redirect},
        tokenEndpointAuthMethod: OAuthClientAuthenticationMethod.none,
        grantTypes: const {'authorization_code'},
        responseTypes: const {'code'},
      );
      expect(
        () => validator.validateExtendedAuthorizationRequest(
          request: request(),
          requestObject: object(),
          server: server,
          client: publicClient,
          now: now,
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('client authentication requires assertion or certificate', () {
      expect(
        () => validator.validateClientAuthentication(
          const OAuthClientAuthentication(
            method: OAuthClientAuthenticationMethod.privateKeyJwt,
          ),
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
      validator.validateClientAuthentication(
        const OAuthClientAuthentication(
          method: OAuthClientAuthenticationMethod.privateKeyJwt,
          clientAssertion: SecretValue('signed-jwt'),
        ),
      );
      validator.validateClientAuthentication(
        const OAuthClientAuthentication(
          method: OAuthClientAuthenticationMethod.tlsClientAuth,
          certificateThumbprint: 'thumb',
        ),
      );
      expect(
        () => validator.validateClientAuthentication(
          const OAuthClientAuthentication(
            method: OAuthClientAuthenticationMethod.clientSecretJwt,
          ),
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('client assertion lifetime and audience are validated', () {
      validator.validateClientAssertion(
        claims: ClientAssertionClaims(
          issuer: const OAuthClientId('qesto-client'),
          subject: const OAuthClientId('qesto-client'),
          audience: const {'https://bank.invalid/token'},
          jwtId: 'unique-id',
          issuedAt: now,
          expiresAt: now.add(const Duration(minutes: 2)),
        ),
        clientId: const OAuthClientId('qesto-client'),
        tokenEndpoint: Uri.parse('https://bank.invalid/token'),
        now: now,
      );
    });

    test('PKCE verifier length is validated at token exchange', () {
      expect(
        () => validator.validateAuthorizationCodeTokenRequest(
          OAuthAuthorizationCodeTokenRequest(
            code: const SecretValue('code'),
            redirectUri: redirect,
            clientId: const OAuthClientId('qesto-client'),
            codeVerifier: const SecretValue('too-short'),
          ),
          registeredRedirectUris: {redirect},
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });
  });

  group('JARM, ID token and certificate binding', () {
    final now = DateTime.utc(2026, 8, 13, 10);

    test('valid JARM response passes', () {
      const JarmValidator().validate(
        JarmValidationInput(
          response: JarmResponse(
            issuer: 'https://bank.invalid',
            audience: {'qesto-client'},
            expiresAt: DateTime.utc(2026, 8, 13, 10, 5),
            issuedAt: DateTime.utc(2026, 8, 13, 10),
            state: '01234567890123456789',
            code: SecretValue('code'),
          ),
          joseVerified: true,
          expectedIssuer: 'https://bank.invalid',
          expectedAudience: 'qesto-client',
          expectedState: SecretValue('01234567890123456789'),
          now: DateTime.utc(2026, 8, 13, 10),
        ),
      );
    });

    test('ID token nonce mismatch fails', () {
      final claims = IdTokenClaims(
        issuer: 'https://bank.invalid',
        subject: 'user',
        audience: const {'qesto-client'},
        expiresAt: now.add(const Duration(minutes: 5)),
        issuedAt: now,
        nonce: 'wrong',
      );
      expect(
        () => const IdTokenValidator().validate(
          IdTokenValidationInput(
            claims: claims,
            joseVerified: true,
            expectedIssuer: 'https://bank.invalid',
            expectedClientId: const OAuthClientId('qesto-client'),
            expectedNonce: const SecretValue('expected'),
            now: now,
          ),
        ),
        throwsA(isA<OpenBankingValidationError>()),
      );
    });

    test('ID token issuer and audience mismatch fail independently', () {
      IdTokenClaims claims({
        String issuer = 'https://bank.invalid',
        Set<String> audience = const {'qesto-client'},
      }) => IdTokenClaims(
        issuer: issuer,
        subject: 'user',
        audience: audience,
        expiresAt: now.add(const Duration(minutes: 5)),
        issuedAt: now,
        nonce: 'expected',
      );
      for (final invalid in [
        claims(issuer: 'https://wrong.invalid'),
        claims(audience: const {'other-client'}),
      ]) {
        expect(
          () => const IdTokenValidator().validate(
            IdTokenValidationInput(
              claims: invalid,
              joseVerified: true,
              expectedIssuer: 'https://bank.invalid',
              expectedClientId: const OAuthClientId('qesto-client'),
              expectedNonce: const SecretValue('expected'),
              now: now,
            ),
          ),
          throwsA(isA<OpenBankingValidationError>()),
        );
      }
    });

    test('mTLS mismatch maps to invalid_token and 401', () {
      final token = CertificateBoundAccessToken(
        token: const SecretValue('access'),
        certificateSha256Thumbprint: 'expected',
        expiresAt: now.add(const Duration(minutes: 1)),
        scopes: const {'accounts'},
      );
      final cert = MtlsCertificateIdentity(
        alias: 'fixture',
        sha256Thumbprint: 'different',
        notBefore: now.subtract(const Duration(days: 1)),
        notAfter: now.add(const Duration(days: 1)),
        subject: 'CN=fixture',
        issuer: 'CN=fixture-ca',
      );
      expect(
        () => const CertificateBindingValidator().validate(
          accessToken: token,
          certificate: cert,
          now: now,
        ),
        throwsA(
          isA<InvalidTokenBindingError>().having(
            (error) => error.httpStatus,
            'httpStatus',
            401,
          ),
        ),
      );
    });
  });
}
