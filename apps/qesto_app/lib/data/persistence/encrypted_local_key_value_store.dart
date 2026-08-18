import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'local_key_value_store.dart';

/// Stores the small encryption key in the operating system's protected vault.
abstract interface class SecureStringStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

class PlatformSecureStringStore implements SecureStringStore {
  const PlatformSecureStringStore({
    this._storage = const FlutterSecureStorage(),
  });

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Encrypts every value before passing it to the existing platform store.
///
/// AES-GCM authenticates both the ciphertext and the logical storage key. A
/// copied or modified value therefore fails closed instead of being decoded as
/// financial data. Legacy plaintext values are encrypted after their first
/// successful read, which keeps upgrades compatible with existing installs.
class EncryptedLocalKeyValueStore extends LocalKeyValueStore {
  EncryptedLocalKeyValueStore({
    LocalKeyValueStore? delegate,
    SecureStringStore? secureStore,
    AesGcm? algorithm,
  }) : _delegate = delegate ?? const LocalKeyValueStore(),
       _secureStore = secureStore ?? const PlatformSecureStringStore(),
       _algorithm = algorithm ?? AesGcm.with256bits();

  static const _masterKeyName = 'qesto.local-storage.master-key.v1';
  static const _envelopePrefix = 'qesto:aes-gcm:v1:';

  final LocalKeyValueStore _delegate;
  final SecureStringStore _secureStore;
  final AesGcm _algorithm;
  Future<SecretKey>? _masterKeyFuture;

  @override
  Future<String?> readString(String key) async {
    final stored = await _delegate.readString(key);
    if (stored == null) return null;
    if (!stored.startsWith(_envelopePrefix)) {
      await writeString(key, stored);
      return stored;
    }

    try {
      final payload = jsonDecode(stored.substring(_envelopePrefix.length));
      if (payload is! Map<String, dynamic> || payload['v'] != 1) {
        throw const FormatException('Unsupported encrypted storage envelope');
      }
      final box = SecretBox(
        base64Decode(payload['ciphertext'] as String),
        nonce: base64Decode(payload['nonce'] as String),
        mac: Mac(base64Decode(payload['mac'] as String)),
      );
      final clearBytes = await _algorithm.decrypt(
        box,
        secretKey: await _masterKey(),
        aad: utf8.encode(key),
      );
      return utf8.decode(clearBytes);
    } on Object catch (error) {
      throw EncryptedStorageException(
        'Не удалось расшифровать локальные данные Qesto.',
        error,
      );
    }
  }

  @override
  Future<void> writeString(String key, String value) async {
    final secretBox = await _algorithm.encrypt(
      utf8.encode(value),
      secretKey: await _masterKey(),
      nonce: _algorithm.newNonce(),
      aad: utf8.encode(key),
    );
    final envelope = jsonEncode({
      'v': 1,
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    });
    await _delegate.writeString(key, '$_envelopePrefix$envelope');
  }

  @override
  Future<void> remove(String key) => _delegate.remove(key);

  Future<SecretKey> _masterKey() =>
      _masterKeyFuture ??= _loadOrCreateMasterKey();

  Future<SecretKey> _loadOrCreateMasterKey() async {
    final stored = await _secureStore.read(_masterKeyName);
    if (stored != null) {
      final bytes = base64Decode(stored);
      if (bytes.length != 32) {
        throw const EncryptedStorageException(
          'Защищённый ключ Qesto имеет неверный размер.',
        );
      }
      return SecretKey(bytes);
    }

    final generated = await _algorithm.newSecretKey();
    final bytes = await generated.extractBytes();
    await _secureStore.write(_masterKeyName, base64Encode(bytes));
    return SecretKey(bytes);
  }
}

class EncryptedStorageException implements Exception {
  const EncryptedStorageException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
