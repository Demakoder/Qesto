import 'external_url_launcher_stub.dart'
    if (dart.library.io) 'external_url_launcher_io.dart'
    if (dart.library.js_interop) 'external_url_launcher_web.dart'
    as platform;

Future<bool> openExternalUrl(String value) => platform.openExternalUrl(value);
