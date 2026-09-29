import '../domain/bank_browser_models.dart';

class BankBrowserSecurityPolicy {
  const BankBrowserSecurityPolicy();

  static const _blockedSchemes = {
    'http',
    'file',
    'javascript',
    'data',
    'blob',
    'about',
  };

  NavigationDecision decide(
    Uri? uri,
    BankConnectorConfig config, {
    bool isMainFrame = true,
  }) {
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return NavigationDecision.block;
    }
    final scheme = uri.scheme.toLowerCase();
    if (_blockedSchemes.contains(scheme) || scheme != 'https') {
      return NavigationDecision.block;
    }
    if (!isMainFrame) return NavigationDecision.allow;
    final origin = normalizedOrigin(uri);
    if (config.allTrustedOrigins.contains(origin)) {
      return NavigationDecision.allow;
    }
    return NavigationDecision.block;
  }

  String normalizedOrigin(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final defaultPort =
        (scheme == 'https' && uri.port == 443) ||
        (scheme == 'http' && uri.port == 80);
    return '$scheme://$host${defaultPort || !uri.hasPort ? '' : ':${uri.port}'}';
  }

  Uri sanitizedForPersistence(Uri uri) => Uri(
    scheme: uri.scheme,
    userInfo: '',
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  );
}
