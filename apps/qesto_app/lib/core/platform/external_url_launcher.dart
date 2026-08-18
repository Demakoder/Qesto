import 'external_url_launcher_stub.dart'
    if (dart.library.io) 'external_url_launcher_io.dart'
    if (dart.library.js_interop) 'external_url_launcher_web.dart'
    as platform;

final _trailingDotPattern = RegExp(r'\.$');
final _ipv6LinkLocalPattern = RegExp(r'^fe[89ab]');
final _ipv6SiteLocalPattern = RegExp(r'^fe[c-f]');
final _singleNumericHostPattern = RegExp(r'^(0x[0-9a-f]+|[0-9]+)$');
final _decimalIpv4Pattern = RegExp(r'^[0-9.]+$');
final _numericHostLabelPattern = RegExp(r'^(?:0x[0-9a-f]+|[0-9]+)$');

Future<bool> openExternalUrl(String value) => isSafeExternalWebUrl(value)
    ? platform.openExternalUrl(value)
    : Future<bool>.value(false);

bool isSafeExternalWebUrl(String value) =>
    externalWebUrlValidationError(value) == null;

String? externalWebUrlValidationError(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
    return 'Разрешены только ссылки HTTP и HTTPS';
  }
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    return 'Ссылка содержит недопустимый адрес';
  }

  final host = uri.host.toLowerCase().replaceFirst(_trailingDotPattern, '');
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal') ||
      host.endsWith('.lan') ||
      _isNonPublicIpLiteral(host)) {
    return 'Локальные и служебные адреса заблокированы';
  }
  return null;
}

bool _isNonPublicIpLiteral(String host) {
  if (host.contains(':')) {
    final normalized = host.toLowerCase();
    if (normalized == '::' ||
        normalized == '::1' ||
        normalized.startsWith('fc') ||
        normalized.startsWith('fd') ||
        _ipv6LinkLocalPattern.hasMatch(normalized) ||
        _ipv6SiteLocalPattern.hasMatch(normalized) ||
        normalized.startsWith('ff') ||
        normalized.startsWith('2001:db8:')) {
      return true;
    }
    final embeddedIpv4 = normalized.split(':').last;
    return embeddedIpv4.contains('.') && _isNonPublicIpv4(embeddedIpv4);
  }

  if (_singleNumericHostPattern.hasMatch(host)) return true;
  if (_decimalIpv4Pattern.hasMatch(host)) {
    final parts = host.split('.');
    if (parts.any((part) => part.length > 1 && part.startsWith('0'))) {
      return true;
    }
    return _isNonPublicIpv4(host);
  }
  return host.split('.').every(_numericHostLabelPattern.hasMatch);
}

bool _isNonPublicIpv4(String host) {
  final parts = host.split('.').map(int.tryParse).toList(growable: false);
  if (parts.length != 4 || parts.any((part) => part == null || part > 255)) {
    return true;
  }
  final first = parts[0]!;
  final second = parts[1]!;
  if (first == 0 || first == 10 || first == 127 || first >= 224) return true;
  if (first == 100 && second >= 64 && second <= 127) return true;
  if (first == 169 && second == 254) return true;
  if (first == 172 && second >= 16 && second <= 31) return true;
  if (first == 192 && second == 168) return true;
  if (first == 198 && (second == 18 || second == 19)) return true;
  return false;
}
