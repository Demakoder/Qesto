import 'dart:io';

Future<bool> openExternalUrl(String value) async {
  final uri = Uri.tryParse(value);
  if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return false;
  try {
    if (Platform.isWindows) {
      await Process.start('rundll32.exe', [
        'url.dll,FileProtocolHandler',
        uri.toString(),
      ], mode: ProcessStartMode.detached);
    } else if (Platform.isMacOS) {
      await Process.start('open', [
        uri.toString(),
      ], mode: ProcessStartMode.detached);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [
        uri.toString(),
      ], mode: ProcessStartMode.detached);
    } else {
      return false;
    }
    return true;
  } on Object {
    return false;
  }
}
