import 'dart:io';
import 'android_store_location.dart';
import 'recoverable_json_file.dart';

Future<String?> readString(String key) async =>
    (await RecoverableJsonFile(await _storeFile()).read())?[key] as String?;

Future<void> writeString(String key, String value) async => RecoverableJsonFile(
  await _storeFile(),
).update((current) => {...?current, key: value});

Future<void> remove(String key) async => RecoverableJsonFile(
  await _storeFile(),
).update((current) => {...?current}..remove(key), retainPrevious: false);

File? _androidStore;

Future<File> _storeFile() async {
  if (Platform.isAndroid) {
    return _androidStore ??= await resolveAndroidStore();
  }
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
