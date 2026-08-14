import 'dart:convert';
import 'dart:io';

Future<void> _pendingWrite = Future<void>.value();

Future<String?> readString(String key) async => (await _readAll())[key];

Future<void> writeString(String key, String value) {
  final previous = _pendingWrite;
  _pendingWrite = () async {
    try {
      await previous;
    } on Object {
      // A valid later snapshot must still be allowed to replace a failed one.
    }
    final values = await _readAll();
    values[key] = value;
    await _writeAll(values);
  }();
  return _pendingWrite;
}

Future<void> remove(String key) {
  final previous = _pendingWrite;
  _pendingWrite = () async {
    try {
      await previous;
    } on Object {
      // A later removal must still be allowed after a failed write.
    }
    final values = await _readAll();
    values.remove(key);
    await _writeAll(values);
  }();
  return _pendingWrite;
}

Future<Map<String, String>> _readAll() async {
  final file = _storeFile();
  final backup = File('${file.path}.backup');
  final source = await file.exists()
      ? await file.readAsString()
      : await backup.exists()
      ? await backup.readAsString()
      : null;
  if (source == null || source.trim().isEmpty) return <String, String>{};
  try {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) return <String, String>{};
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  } on FormatException {
    return <String, String>{};
  }
}

Future<void> _writeAll(Map<String, String> values) async {
  final file = _storeFile();
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.temporary');
  final backup = File('${file.path}.backup');
  await temporary.writeAsString(jsonEncode(values), flush: true);
  if (await backup.exists()) await backup.delete();
  if (await file.exists()) await file.rename(backup.path);
  try {
    await temporary.rename(file.path);
    if (await backup.exists()) await backup.delete();
  } on Object {
    if (!await file.exists() && await backup.exists()) {
      await backup.rename(file.path);
    }
    rethrow;
  }
}

File _storeFile() {
  final environment = Platform.environment;
  late final String root;
  if (Platform.isWindows) {
    root = environment['APPDATA'] ?? Directory.current.path;
  } else if (Platform.isMacOS) {
    final home = environment['HOME'] ?? Directory.current.path;
    root =
        '$home${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support';
  } else {
    final home = environment['HOME'] ?? Directory.current.path;
    root = '$home${Platform.pathSeparator}.local${Platform.pathSeparator}share';
  }
  return File(
    '$root${Platform.pathSeparator}Qesto${Platform.pathSeparator}store.json',
  );
}
