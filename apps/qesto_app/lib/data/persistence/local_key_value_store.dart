import 'local_key_value_store_stub.dart'
    if (dart.library.io) 'local_key_value_store_io.dart'
    if (dart.library.js_interop) 'local_key_value_store_web.dart'
    as platform;

class LocalKeyValueStore {
  const LocalKeyValueStore();

  Future<String?> readString(String key) => platform.readString(key);

  Future<void> writeString(String key, String value) =>
      platform.writeString(key, value);

  Future<void> remove(String key) => platform.remove(key);
}

class MemoryKeyValueStore extends LocalKeyValueStore {
  MemoryKeyValueStore([Map<String, String>? initial])
    : _values = Map.of(initial ?? const {});

  final Map<String, String> _values;

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}
