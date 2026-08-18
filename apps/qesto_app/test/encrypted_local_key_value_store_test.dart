import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/persistence/encrypted_local_key_value_store.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';

void main() {
  group('EncryptedLocalKeyValueStore', () {
    test('round-trips data without storing its plaintext', () async {
      final delegate = MemoryKeyValueStore();
      final secrets = _MemorySecureStringStore();
      final store = EncryptedLocalKeyValueStore(
        delegate: delegate,
        secureStore: secrets,
      );

      await store.writeString('finance', '{"merchant":"Магазин"}');

      final raw = await delegate.readString('finance');
      expect(raw, startsWith('qesto:aes-gcm:v1:'));
      expect(raw, isNot(contains('Магазин')));
      final reopened = EncryptedLocalKeyValueStore(
        delegate: delegate,
        secureStore: secrets,
      );
      expect(await reopened.readString('finance'), '{"merchant":"Магазин"}');
    });

    test('migrates a legacy plaintext value after reading it', () async {
      final delegate = MemoryKeyValueStore({'finance': 'legacy-value'});
      final store = EncryptedLocalKeyValueStore(
        delegate: delegate,
        secureStore: _MemorySecureStringStore(),
      );

      expect(await store.readString('finance'), 'legacy-value');
      final migrated = await delegate.readString('finance');
      expect(migrated, startsWith('qesto:aes-gcm:v1:'));
      expect(migrated, isNot(contains('legacy-value')));
    });

    test('rejects ciphertext copied under another key', () async {
      final delegate = MemoryKeyValueStore();
      final store = EncryptedLocalKeyValueStore(
        delegate: delegate,
        secureStore: _MemorySecureStringStore(),
      );
      await store.writeString('first', 'secret');
      await delegate.writeString(
        'second',
        (await delegate.readString('first'))!,
      );

      expect(
        () => store.readString('second'),
        throwsA(isA<EncryptedStorageException>()),
      );
    });

    test('rejects modified ciphertext', () async {
      final delegate = MemoryKeyValueStore();
      final store = EncryptedLocalKeyValueStore(
        delegate: delegate,
        secureStore: _MemorySecureStringStore(),
      );
      await store.writeString('finance', 'secret');
      final raw = (await delegate.readString('finance'))!;
      await delegate.writeString(
        'finance',
        '${raw.substring(0, raw.length - 1)}X',
      );

      expect(
        () => store.readString('finance'),
        throwsA(isA<EncryptedStorageException>()),
      );
    });
  });
}

class _MemorySecureStringStore implements SecureStringStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
