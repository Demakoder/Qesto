import 'package:web/web.dart' as web;

Future<String?> readString(String key) async =>
    web.window.localStorage.getItem(key);

Future<void> writeString(String key, String value) async {
  web.window.localStorage.setItem(key, value);
}

Future<void> remove(String key) async {
  web.window.localStorage.removeItem(key);
}
