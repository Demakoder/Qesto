import 'package:web/web.dart' as web;

Future<bool> openExternalUrl(String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return false;
  final anchor = web.HTMLAnchorElement()
    ..href = uri.toString()
    ..target = '_blank'
    ..rel = 'noopener noreferrer';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  return true;
}
