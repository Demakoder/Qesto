import 'dart:async';
import '../../../core/safety/financial_write_guard.dart';

import 'package:flutter/material.dart';
import 'package:webview_cef/webview_cef.dart';

import '../data/browser_profile_manager.dart';
import '../domain/bank_browser_models.dart';
import '../observation/page_observer.dart';
import '../security/bank_browser_security_policy.dart';

typedef BrowserNotice = void Function(String message);

/// Qesto-facing browser lifecycle. CEF details stay behind this boundary so a
/// future bank connector never owns cookies, a RequestContext, or native APIs.
class BrowserController extends ChangeNotifier implements PageObserver {
  BrowserController({
    required BankProfile profile,
    required this.bank,
    required this.profileManager,
    required this.onNotice,
    this.securityPolicy = const BankBrowserSecurityPolicy(),
  }) : _profile = profile,
       _state = BankBrowserState(
         lifecycle: BankBrowserLifecycle.closed,
         profile: profile,
         bank: bank,
         loadState: BankBrowserLoadState.idle,
       );

  static const _devToolsRequested = bool.fromEnvironment(
    'BANK_BROWSER_DEVTOOLS',
    defaultValue: false,
  );

  final BankConnectorConfig bank;
  final BrowserProfileManager profileManager;
  final BankBrowserSecurityPolicy securityPolicy;
  final BrowserNotice onNotice;
  final _observations = StreamController<PageObservation>.broadcast();
  final _navigationWaiters = <Completer<Uri>>[];
  final _loadWaiters = <BankBrowserLoadState, List<Completer<void>>>{};

  BankProfile _profile;
  BankBrowserState _state;
  WebViewController? _webView;
  BrowserMode _mode = BrowserMode.auth;
  BrowserPresentationMode _presentationMode = BrowserPresentationMode.visible;
  String? _title;
  bool _runtimeReady = false;
  bool _disposed = false;
  bool _closed = false;
  Future<void>? _closeFuture;
  bool _certificateProblem = false;

  BankBrowserState get state => _state;
  BankProfile get profile => _profile;
  BrowserMode get mode => _mode;
  BrowserPresentationMode get presentationMode => _presentationMode;
  bool get isRuntimeReady => _runtimeReady && _webView != null;
  bool get hasCertificateProblem => _certificateProblem;

  @override
  Stream<PageObservation> get observations => _observations.stream;

  Uri get initialUrl {
    final candidate = _profile.lastKnownUrl;
    return securityPolicy.decide(candidate, bank) == NavigationDecision.allow
        ? candidate!
        : bank.startUrl;
  }

  Future<void> open({
    BrowserPresentationMode presentationMode = BrowserPresentationMode.visible,
  }) async {
    if (_disposed || _closed) throw StateError('Browser closed');
    _presentationMode = presentationMode;
    _setState(
      lifecycle: BankBrowserLifecycle.opening,
      loadState: BankBrowserLoadState.idle,
    );
    try {
      _profile = await profileManager.openProfile(_profile);
      if (_disposed || _closed) return;
      final profileDirectory = profileManager.cefDataDirectory(_profile.id);
      await profileManager.prepareCefProfile(_profile.id);
      await WebviewManager().initialize(
        rootCachePath: profileManager.rootDirectory.absolute.path,
      );
      if (_disposed || _closed) return;

      final webView = WebviewManager().createWebView(
        loading: const Center(child: CircularProgressIndicator()),
      );
      webView.setWebviewListener(
        WebviewEventsListener(
          onUrlChanged: _onUrlChanged,
          onTitleChanged: (value) => _title = value,
          onLoadStart: (_, value) => _onLoadStart(value),
          onLoadEnd: (_, value) => unawaited(_onLoadEnd(value)),
          onCertificateError: _onCertificateError,
        ),
      );
      _webView = webView;
      await webView.initialize(
        initialUrl.toString(),
        profilePath: profileDirectory.absolute.path,
        allowedOrigins: bank.allTrustedOrigins.toList(growable: false),
        enableDevTools:
            !const bool.fromEnvironment('dart.vm.product') &&
            _devToolsRequested,
      );
      if (_disposed || _closed) return;
      if (presentationMode == BrowserPresentationMode.background) {
        await webView.setSurfaceSize();
        await webView.setClientFocus(false);
      }
      if (_disposed || _closed) return;
      _runtimeReady = true;
      _setState(
        lifecycle: _state.loadState == BankBrowserLoadState.finished
            ? BankBrowserLifecycle.ready
            : BankBrowserLifecycle.loading,
        loadState: _state.loadState == BankBrowserLoadState.idle
            ? BankBrowserLoadState.started
            : _state.loadState,
        currentUrl: _state.currentUrl ?? initialUrl,
      );
      await _refreshNavigationCapabilities();
    } on Object {
      if (_closed || _disposed) return;
      _runtimeReady = false;
      _setState(
        lifecycle: BankBrowserLifecycle.error,
        loadState: BankBrowserLoadState.failed,
        errorMessage: 'Не удалось запустить Chromium Embedded Framework',
      );
    }
  }

  Widget buildWebView({Key? key}) {
    final webView = _webView;
    if (!_runtimeReady || webView == null) return const SizedBox.shrink();
    return KeyedSubtree(key: key, child: webView.webviewWidget);
  }

  Future<void> navigate(Uri uri) async {
    _checkOpen();
    if (securityPolicy.decide(uri, bank) != NavigationDecision.allow) {
      onNotice('Переход за пределы официальных адресов банка заблокирован');
      return;
    }
    await _webView?.loadUrl(uri.toString());
  }

  Future<void> goBack() async {
    final webView = _webView;
    if (webView != null && await webView.canGoBack()) await webView.goBack();
  }

  Future<void> goForward() async {
    final webView = _webView;
    if (webView != null && await webView.canGoForward()) {
      await webView.goForward();
    }
  }

  Future<void> reload() async => _webView?.reload();
  Future<void> stop() async => _webView?.stopLoading();
  Future<void> focus() async => _webView?.setClientFocus(true);
  Future<Uri?> currentUrl() async => _state.currentUrl;
  Future<String?> title() async => _title;

  /// Minimal test-only read surface. In AUTH mode no DOM or form value can be
  /// requested; these values already arrive through normal browser callbacks.
  Future<String?> executeReadOnlyJavaScript(ReadOnlyBrowserValue value) async {
    return switch (value) {
      ReadOnlyBrowserValue.documentTitle => _title,
      ReadOnlyBrowserValue.locationOrigin => _state.origin,
    };
  }

  /// Executes a connector-owned, bounded script. Scripts are never accepted
  /// from the page or from user input; the marker makes accidental use from a
  /// generic browser action fail closed. Return JSON as a string because the
  /// CEF bridge intentionally exposes only primitive/list values.
  Future<dynamic> evaluateConnectorJavascript(
    String script, {
    BrowserMode mode = BrowserMode.read,
  }) async {
    _checkOpen();
    if (_webView == null || !_runtimeReady || script.length > 64 * 1024) {
      return null;
    }
    final marker = mode == BrowserMode.auth
        ? 'QESTO_SBER_AUTH_V1'
        : 'QESTO_SBER_READ_V1';
    if (!script.contains(marker) ||
        script.contains('document.cookie') ||
        script.contains('localStorage') ||
        script.contains('sessionStorage') ||
        script.contains('fetch(') ||
        script.contains('XMLHttpRequest')) {
      return null;
    }
    if (mode == BrowserMode.auth) {
      if (securityPolicy.decide(_state.currentUrl, bank) !=
          NavigationDecision.allow) {
        return null;
      }
    } else {
      setMode(BrowserMode.read);
    }
    return _webView!.evaluateJavascript(script);
  }

  /// Development-only DOM surface. The explicit DEV bridge adds its own
  /// read-only guard; this method also rejects network, cookie, navigation,
  /// and browser-storage mutation primitives in every script.
  Future<dynamic> evaluateDevJavascript(String script) async {
    if (_webView == null || !_runtimeReady || script.length > 256 * 1024) {
      return null;
    }
    final navigationMutation = RegExp(
      r'\b(?:window\.)?location(?:\.(?:href|assign|replace))?\s*=|'
      r'\b(?:window\.)?location\.(?:assign|replace)\s*\(|'
      r'\bhistory\.(?:pushState|replaceState)\s*\(|'
      r'\bwindow\.open\s*\(',
    );
    if (!script.contains('QESTO_DEV_V1') ||
        script.contains('document.cookie') ||
        script.contains('fetch(') ||
        script.contains('XMLHttpRequest') ||
        script.contains('navigator.sendBeacon') ||
        navigationMutation.hasMatch(script)) {
      return null;
    }
    setMode(BrowserMode.read);
    return _webView!.evaluateJavascript(script);
  }

  void setMode(BrowserMode value) {
    _mode = value;
  }

  Future<Uri> waitForNavigation() {
    _checkOpen();
    final completer = Completer<Uri>();
    _navigationWaiters.add(completer);
    return completer.future;
  }

  Future<void> waitForLoadState(BankBrowserLoadState state) {
    _checkOpen();
    if (_state.loadState == state) return Future.value();
    final completer = Completer<void>();
    _loadWaiters.putIfAbsent(state, () => []).add(completer);
    return completer.future;
  }

  void _checkOpen() {
    FinancialWriteGuard.check();
    if (_disposed || _closed) throw StateError('Browser closed');
  }

  Future<void> close() => _closeFuture ??= _closeNative();

  Future<void> _closeNative() async {
    _closed = true;
    _cancelWaiters();
    final webView = _webView;
    _webView = null;
    _runtimeReady = false;
    if (webView != null) {
      // dispose also handles a create that is still in flight. Don't call
      // initialized-only commands while startup is being cancelled.
      await webView.dispose();
    }
    _setState(
      lifecycle: BankBrowserLifecycle.closed,
      loadState: BankBrowserLoadState.idle,
    );
  }

  Future<void> disposeEnvironment() => close();

  Future<void> destroyProfile() async {
    await close();
    await profileManager.deleteProfile(_profile.id);
  }

  void _onLoadStart(String value) {
    if (_disposed || _closed) return;
    // CEF creates the off-screen browser on an internal about:blank document
    // before loading the bank URL. It never leaves the browser process and is
    // not a user navigation, so do not surface it as a blocked transition.
    if (value == 'about:blank') return;
    final uri = Uri.tryParse(value);
    if (uri != null &&
        securityPolicy.decide(uri, bank) != NavigationDecision.allow) {
      onNotice('Небезопасный переход заблокирован Chromium');
      return;
    }
    _setState(
      lifecycle: BankBrowserLifecycle.loading,
      loadState: BankBrowserLoadState.started,
      currentUrl: uri,
    );
  }

  Future<void> _onLoadEnd(String value) async {
    if (_disposed || _closed) return;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        securityPolicy.decide(uri, bank) != NavigationDecision.allow) {
      return;
    }
    _certificateProblem = false;
    _setState(
      lifecycle: BankBrowserLifecycle.ready,
      loadState: BankBrowserLoadState.finished,
      currentUrl: uri,
      lastSuccessfulLoad: DateTime.now(),
      errorMessage: null,
    );
    _profile = await profileManager.updateLastKnownUrl(
      _profile,
      securityPolicy.sanitizedForPersistence(uri),
    );
    await _refreshNavigationCapabilities();
  }

  void _onUrlChanged(String value) {
    if (_disposed || _closed) return;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        securityPolicy.decide(uri, bank) != NavigationDecision.allow) {
      return;
    }
    _setState(currentUrl: uri);
    for (final completer in _navigationWaiters.toList()) {
      if (!completer.isCompleted) completer.complete(uri);
    }
    _navigationWaiters.clear();
  }

  void _onCertificateError(String origin) {
    if (_disposed || _closed) return;
    _certificateProblem = true;
    _setState(
      lifecycle: BankBrowserLifecycle.error,
      loadState: BankBrowserLoadState.failed,
      errorMessage:
          'Windows не доверяет сертификату банка. Установите корневой и выпускающий сертификаты Минцифры по официальной инструкции.',
    );
  }

  Future<void> _refreshNavigationCapabilities() async {
    final webView = _webView;
    // Native load events may arrive before the Flutter wrapper finishes
    // initialize(). open() refreshes these controls once it is ready.
    if (webView == null || !_runtimeReady || _closed || _disposed) return;
    _setState(
      canGoBack: await webView.canGoBack(),
      canGoForward: await webView.canGoForward(),
    );
  }

  void _setState({
    BankBrowserLifecycle? lifecycle,
    BankBrowserLoadState? loadState,
    Uri? currentUrl,
    bool? canGoBack,
    bool? canGoForward,
    DateTime? lastSuccessfulLoad,
    String? errorMessage,
  }) {
    if (_disposed) return;
    final nextUrl = currentUrl ?? _state.currentUrl;
    _state = BankBrowserState(
      lifecycle: lifecycle ?? _state.lifecycle,
      profile: _profile,
      bank: bank,
      loadState: loadState ?? _state.loadState,
      currentUrl: nextUrl,
      origin: nextUrl == null
          ? _state.origin
          : securityPolicy.normalizedOrigin(nextUrl),
      canGoBack: canGoBack ?? _state.canGoBack,
      canGoForward: canGoForward ?? _state.canGoForward,
      lastSuccessfulLoad: lastSuccessfulLoad ?? _state.lastSuccessfulLoad,
      errorMessage: errorMessage,
    );
    notifyListeners();
    final uri = _state.currentUrl;
    if (uri != null &&
        securityPolicy.decide(uri, bank) == NavigationDecision.allow) {
      _observations.add(
        PageObservation(
          profileId: _profile.id,
          currentUrl: securityPolicy.sanitizedForPersistence(uri),
          origin: securityPolicy.normalizedOrigin(uri),
          navigationState: _state.lifecycle,
          loadState: _state.loadState,
          timestamp: DateTime.now(),
        ),
      );
    }
    final waiters = _loadWaiters.remove(_state.loadState);
    for (final completer in waiters ?? const <Completer<void>>[]) {
      if (!completer.isCompleted) completer.complete();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(close().catchError((Object _) {}));
    _cancelWaiters();
    unawaited(_observations.close());
    super.dispose();
  }

  void _cancelWaiters() {
    for (final completer in _navigationWaiters) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Browser closed'));
      }
    }
    for (final waiters in _loadWaiters.values) {
      for (final completer in waiters) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('Browser closed'));
        }
      }
    }
    _navigationWaiters.clear();
    _loadWaiters.clear();
  }
}
