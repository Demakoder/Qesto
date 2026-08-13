import 'dart:js_interop';

@JS('open')
external JSAny? _openWindow(JSString url, JSString target);

Future<bool> openExternalUrl(String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return false;
  return _openWindow(uri.toString().toJS, '_blank'.toJS) != null;
}
