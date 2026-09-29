import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_cef/src/webview_inject_user_script.dart';

import 'webview.dart';

class WebviewManager extends ValueNotifier<bool> {
  static final WebviewManager _instance = WebviewManager._internal();

  factory WebviewManager() => _instance;

  late Completer<void> _creatingCompleter;

  final MethodChannel pluginChannel = const MethodChannel("webview_cef");

  final _webViews = <int, WebViewController>{};
  final _injectUserScripts = <int, InjectUserScripts?>{};

  final _tempWebViews = <int, WebViewController>{};
  final _tempInjectUserScripts = <int, InjectUserScripts?>{};
  final _earlyLifecycleEvents = <int, List<MethodCall>>{};
  final _lifecycleQueues = <int, Future<void>>{};
  static const _lifecycleMethods = {
    'urlChanged',
    'titleChanged',
    'onLoadStart',
    'onLoadEnd',
    'onCertificateError',
  };

  int nextIndex = 1;

  bool? _hasNativeKeySupport;

  get ready => _creatingCompleter.future;

  /// Returns true if the platform has native key event handling (e.g., GTK on desktop Linux).
  /// When false, Dart-side key handling should be used (e.g., eLinux).
  Future<bool> get hasNativeKeySupport async {
    _hasNativeKeySupport ??=
        await pluginChannel.invokeMethod<bool>('hasNativeKeySupport') ?? false;
    return _hasNativeKeySupport!;
  }

  WebViewController createWebView({
    Widget? loading,
    InjectUserScripts? injectUserScripts,
  }) {
    int browserIndex = nextIndex++;
    final controller =
        WebViewController(pluginChannel, browserIndex, loading: loading);
    _tempWebViews[browserIndex] = controller;
    _tempInjectUserScripts[browserIndex] = injectUserScripts;

    return controller;
  }

  void removeWebView(int browserId) {
    if (browserId > 0) {
      _webViews.remove(browserId);
      _injectUserScripts.remove(browserId);
      _earlyLifecycleEvents.remove(browserId);
    }
  }

  void discardPendingWebView(int index) {
    _tempWebViews.remove(index);
    _tempInjectUserScripts.remove(index);
    if (_tempWebViews.isEmpty) _earlyLifecycleEvents.clear();
  }

  WebviewManager._internal() : super(false);

  Future<void> initialize({required String rootCachePath}) async {
    if (value) return;
    _creatingCompleter = Completer<void>();
    try {
      await pluginChannel.invokeMethod('init', <Object>[rootCachePath]);
      pluginChannel.setMethodCallHandler(methodCallhandler);
      // Wait for the platform to complete initialization.
      await Future.delayed(const Duration(milliseconds: 300));
      _creatingCompleter.complete();
      value = true;
    } on PlatformException catch (e) {
      _creatingCompleter.completeError(e);
    }
    return _creatingCompleter.future;
  }

  @override
  Future<void> dispose() async {
    super.dispose();
    pluginChannel.setMethodCallHandler(null);
    _webViews.clear();
    _earlyLifecycleEvents.clear();
  }

  void onBrowserCreated(int browserIndex, int browserId) {
    _webViews[browserId] = _tempWebViews[browserIndex]!;
    _injectUserScripts[browserId] = _tempInjectUserScripts[browserIndex];

    _tempWebViews.remove(browserIndex);
    _tempInjectUserScripts.remove(browserIndex);
    final early =
        _earlyLifecycleEvents.remove(browserId) ?? const <MethodCall>[];
    for (final event in early) {
      unawaited(methodCallhandler(event).catchError((Object _) {}));
    }
    if (_tempWebViews.isEmpty) _earlyLifecycleEvents.clear();
  }

  Future<void> methodCallhandler(MethodCall call) async {
    if (_lifecycleMethods.contains(call.method) && call.arguments is Map) {
      final id = call.arguments['browserId'];
      if (id is! int) return;
      if (!_webViews.containsKey(id)) {
        // Native creation and page callbacks use separate platform messages.
        // A fast load can precede the create reply that registers its owner.
        if (_tempWebViews.isNotEmpty &&
            (_earlyLifecycleEvents.containsKey(id) ||
                _earlyLifecycleEvents.length < 8)) {
          final events = _earlyLifecycleEvents.putIfAbsent(id, () => []);
          if (events.length < 32) events.add(call);
        }
        return;
      }
      final previous = _lifecycleQueues[id] ?? Future<void>.value();
      final next = previous.catchError((Object _) {}).then((_) async {
        if (_webViews.containsKey(id)) await _dispatch(call);
      });
      _lifecycleQueues[id] = next;
      unawaited(next.then<void>((_) {
        if (identical(_lifecycleQueues[id], next)) _lifecycleQueues.remove(id);
      }, onError: (Object _, StackTrace __) {
        if (identical(_lifecycleQueues[id], next)) _lifecycleQueues.remove(id);
      }));
      return next;
    }
    return _dispatch(call);
  }

  Future<void> _dispatch(MethodCall call) async {
    switch (call.method) {
      case "urlChanged":
        int browserId = call.arguments["browserId"] as int;
        _webViews[browserId]
            ?.listener
            ?.onUrlChanged
            ?.call(call.arguments["url"] as String);
        return;
      case "titleChanged":
        int browserId = call.arguments["browserId"] as int;
        _webViews[browserId]
            ?.listener
            ?.onTitleChanged
            ?.call(call.arguments["title"] as String);
        return;
      case "onConsoleMessage":
        int browserId = call.arguments["browserId"] as int;
        _webViews[browserId]?.listener?.onConsoleMessage?.call(
            call.arguments["level"] as int,
            call.arguments["message"] as String,
            call.arguments["source"] as String,
            call.arguments["line"] as int);
        return;
      case 'javascriptChannelMessage':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]?.onJavascriptChannelMessage?.call(
            call.arguments['channel'] as String,
            call.arguments['message'] as String,
            call.arguments['callbackId'] as String,
            call.arguments['frameId'] as String);
        return;
      case 'onTooltip':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]?.onToolTip?.call(call.arguments['text'] as String);
        return;
      case 'onCursorChanged':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]
            ?.onCursorChanged
            ?.call(call.arguments['type'] as int);
        return;
      case 'onFocusedNodeChangeMessage':
        int browserId = call.arguments['browserId'] as int;
        bool editable = call.arguments['editable'] as bool;
        _webViews[browserId]?.onFocusedNodeChangeMessage(editable);
        return;
      case 'onImeCompositionRangeChangedMessage':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]?.onImeCompositionRangeChangedMessage?.call(
            call.arguments['x'] as int,
            call.arguments['y'] as int,
            call.arguments['height'] as int);
        return;
      case 'onLoadStart':
        int browserId = call.arguments["browserId"] as int;
        String urlId = call.arguments["urlId"] as String;

        await _injectUserScriptIfNeeds(
            browserId,
            _injectUserScripts[browserId]?.retrieveLoadStartInjectScripts() ??
                []);

        final controller = _webViews[browserId];
        if (controller != null)
          controller.listener?.onLoadStart?.call(controller, urlId);
        return;
      case 'onLoadEnd':
        int browserId = call.arguments["browserId"] as int;
        String urlId = call.arguments["urlId"] as String;

        await _injectUserScriptIfNeeds(
            browserId,
            _injectUserScripts[browserId]?.retrieveLoadEndInjectScripts() ??
                []);

        final controller = _webViews[browserId];
        if (controller != null)
          controller.listener?.onLoadEnd?.call(controller, urlId);
        return;
      case 'onCertificateError':
        int browserId = call.arguments['browserId'] as int;
        _webViews[browserId]?.listener?.onCertificateError?.call(
              call.arguments['origin'] as String,
            );
        return;
      default:
    }
  }

  Future<void> _injectUserScriptIfNeeds(
      int browserId, List<UserScript> scripts) async {
    if (scripts.isEmpty) return;

    await _webViews[browserId]?.ready;

    for (final script in scripts) {
      await _webViews[browserId]?.executeJavaScript(script.script);
    }
  }

  Future<void> setCookie(String domain, String key, String val) async {
    assert(value);
    return pluginChannel.invokeMethod('setCookie', [domain, key, val]);
  }

  Future<void> deleteCookie(String domain, String key) async {
    assert(value);
    return pluginChannel.invokeMethod('deleteCookie', [domain, key]);
  }

  Future<dynamic> visitAllCookies() async {
    assert(value);
    return pluginChannel.invokeMethod('visitAllCookies');
  }

  Future<dynamic> visitUrlCookies(String domain, bool isHttpOnly) async {
    assert(value);
    return pluginChannel.invokeMethod('visitUrlCookies', [domain, isHttpOnly]);
  }

  Future<void> quit() async {
    //only call this method when you want to quit the app
    assert(value);
    return pluginChannel.invokeMethod('quit');
  }
}
