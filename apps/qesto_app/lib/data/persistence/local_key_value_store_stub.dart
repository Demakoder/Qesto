final _values = <String, String>{};

Future<String?> readString(String key) async => _values[key];

Future<void> writeString(String key, String value) async {
  _values[key] = value;
}

Future<void> remove(String key) async {
  _values.remove(key);
}
