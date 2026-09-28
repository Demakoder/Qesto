import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import '../../../data/persistence/encrypted_local_key_value_store.dart';
import '../domain/ai_export_models.dart';

class AiExportIdStore {
  AiExportIdStore({SecureStringStore? secureStore})
    : _secureStore = secureStore ?? const PlatformSecureStringStore();
  static final instance = AiExportIdStore();
  static const storageKey = 'qesto.ai-export.pseudonym-key.v1';
  final SecureStringStore _secureStore;
  Future<SecretKey>? _pending;

  Future<AiExportIds> forProfile(String profileScope) async =>
      AiExportIds(await (_pending ??= _load()), profileScope);

  Future<SecretKey> _load() async {
    try {
      final stored = await _secureStore.read(storageKey);
      if (stored != null) {
        final bytes = base64Decode(stored);
        if (bytes.length != 32) throw const FormatException();
        return SecretKey(bytes);
      }
      final random = Random.secure();
      final bytes = List<int>.generate(32, (_) => random.nextInt(256));
      // Persist successfully before using the key. Never silently rotate on error.
      await _secureStore.write(storageKey, base64Encode(bytes));
      return SecretKey(bytes);
    } on Object {
      _pending = null;
      throw const AiExportKeyException();
    }
  }
}

class AiExportKeyException implements Exception {
  const AiExportKeyException();
  @override
  String toString() =>
      'Не удалось открыть защищённый ключ экспорта. Повторите попытку; не очищайте защищённое хранилище.';
}

class AiExportIds implements AiExportIdProvider {
  AiExportIds(this._key, this._profileScope);
  final SecretKey _key;
  final String _profileScope;
  final _hmac = Hmac.sha256();
  @override
  Future<String> id(String type, String canonicalId) async {
    final prefix = switch (type) {
      'account' => 'acc',
      'transaction' => 'txn',
      'category' => 'cat',
      'duplicate' => 'dup',
      'transfer' => 'trf',
      _ => throw ArgumentError('Unsupported export entity'),
    };
    final mac = await _hmac.calculateMac(
      utf8.encode(
        jsonEncode([
          'qesto.ai-export.ids.v1',
          _profileScope,
          type,
          canonicalId,
        ]),
      ),
      secretKey: _key,
    );
    return '${prefix}_${mac.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
