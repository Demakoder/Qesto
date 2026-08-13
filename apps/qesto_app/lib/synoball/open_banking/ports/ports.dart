import '../core/errors.dart';
import '../core/runtime.dart';
import '../core/secrets.dart';
import '../security/fapi_sec_1_6_2024/models.dart';

class OpenBankingTransportRequest {
  const OpenBankingTransportRequest({
    required this.method,
    required this.uri,
    this.headers = const {},
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final Object? body;
}

class OpenBankingTransportResponse {
  const OpenBankingTransportResponse({
    required this.statusCode,
    this.headers = const {},
    this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Object? body;
}

abstract interface class OpenBankingTransport {
  Future<OpenBankingTransportResponse> send(
    OpenBankingTransportRequest request,
  );
}

class DisabledOpenBankingTransport implements OpenBankingTransport {
  const DisabledOpenBankingTransport([
    this.guard = const DenyAllExternalIoGuard(),
  ]);

  final ExternalIoGuard guard;

  @override
  Future<OpenBankingTransportResponse> send(
    OpenBankingTransportRequest request,
  ) async => guard.assertExternalIoAllowed();
}

/// Deterministic in-memory transport for tests. It never opens a socket.
class FixtureOpenBankingTransport implements OpenBankingTransport {
  const FixtureOpenBankingTransport(this.handler);

  final OpenBankingTransportResponse Function(OpenBankingTransportRequest)
  handler;

  @override
  Future<OpenBankingTransportResponse> send(
    OpenBankingTransportRequest request,
  ) async => handler(request);
}

abstract interface class JoseCryptoProvider {
  Future<String> signJws({
    required JoseHeader header,
    required Object payload,
    required SecretReference key,
  });

  Future<Map<String, Object?>> verifyJws({
    required String compactJws,
    required JsonWebKeySet keys,
  });

  Future<String> decryptJwe({
    required String compactJwe,
    required SecretReference key,
  });
}

class DisabledJoseCryptoProvider implements JoseCryptoProvider {
  const DisabledJoseCryptoProvider();

  Never _disabled() => throw const OpenBankingNotEnabledError(
    'JOSE signing, verification and decryption require an approved provider.',
  );

  @override
  Future<String> decryptJwe({
    required String compactJwe,
    required SecretReference key,
  }) async => _disabled();

  @override
  Future<String> signJws({
    required JoseHeader header,
    required Object payload,
    required SecretReference key,
  }) async => _disabled();

  @override
  Future<Map<String, Object?>> verifyJws({
    required String compactJws,
    required JsonWebKeySet keys,
  }) async => _disabled();
}

abstract interface class ClientAssertionSigner {
  Future<SecretValue> sign(ClientAssertionClaims claims);
}

class DisabledClientAssertionSigner implements ClientAssertionSigner {
  const DisabledClientAssertionSigner();

  @override
  Future<SecretValue> sign(ClientAssertionClaims claims) => Future.error(
    const OpenBankingNotEnabledError(
      'Client assertion signing is intentionally disabled.',
    ),
  );
}

abstract interface class CertificateStore {
  Future<MtlsCertificateIdentity> load(String alias);
}

class DisabledCertificateStore implements CertificateStore {
  const DisabledCertificateStore();

  @override
  Future<MtlsCertificateIdentity> load(String alias) => Future.error(
    const OpenBankingNotEnabledError(
      'No real mTLS certificate store is configured.',
    ),
  );
}

abstract interface class JwksProvider {
  Future<JsonWebKeySet> load(Uri jwksUri);
}

class InMemoryJwksProvider implements JwksProvider {
  InMemoryJwksProvider(this._sets);

  final Map<Uri, JsonWebKeySet> _sets;

  @override
  Future<JsonWebKeySet> load(Uri jwksUri) async {
    final result = _sets[jwksUri];
    if (result == null) {
      throw const OpenBankingValidationError(
        'jwks_not_found',
        'No in-memory JWKS fixture exists for this URI.',
      );
    }
    return result;
  }
}

abstract interface class RandomSource {
  SecretValue secret({required int bytes});
  String identifier();
}

class DisabledRandomSource implements RandomSource {
  const DisabledRandomSource();

  Never _disabled() => throw const OpenBankingNotEnabledError(
    'A cryptographically secure random source is not configured.',
  );

  @override
  String identifier() => _disabled();

  @override
  SecretValue secret({required int bytes}) => _disabled();
}

class DetachedPayloadSigningContext {
  const DetachedPayloadSigningContext({
    required this.interactionId,
    required this.method,
    required this.path,
  });

  final String interactionId;
  final String method;
  final String path;
}

abstract interface class DetachedPayloadSigner {
  Future<String> signPayload(
    List<int> payload,
    DetachedPayloadSigningContext context,
  );
}

class DisabledDetachedPayloadSigner implements DetachedPayloadSigner {
  const DisabledDetachedPayloadSigner();

  @override
  Future<String> signPayload(
    List<int> payload,
    DetachedPayloadSigningContext context,
  ) => Future.error(
    const OpenBankingNotEnabledError(
      'Detached x-jws-signature signing is intentionally disabled.',
    ),
  );
}
