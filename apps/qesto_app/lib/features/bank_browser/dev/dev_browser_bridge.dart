// ignore_for_file: prefer_interpolation_to_compose_strings, unnecessary_string_escapes, curly_braces_in_flow_control_structures

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../domain/bank_browser_models.dart';
import '../runtime/browser_controller.dart';
import '../sber/sber_connector_models.dart';
import '../sber/sber_page_detector.dart';

/// Loopback-only developer bridge. It exists only for an explicitly opened
/// DEV browser session and is removed when that session closes.
class DevBrowserBridge {
  DevBrowserBridge._();

  static final instance = DevBrowserBridge._();
  static const protocolVersion = 1;
  static const marker = 'QESTO_DEV_V1';

  HttpServer? _server;
  BrowserController? _browser;
  BankConnectorConfig? _bank;
  String? _token;
  File? _descriptor;
  DateTime? _startedAt;

  bool get isActive => _server != null && _browser != null;
  String? get descriptorPath => _descriptor?.path;

  Future<void> start({
    required BrowserController browser,
    required BankConnectorConfig bank,
  }) async {
    await stop();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _browser = browser;
    _bank = bank;
    _token = _randomToken();
    _startedAt = DateTime.now();
    server.listen(_handleRequest, onError: (_) {});
    final descriptor = _descriptorFile();
    _descriptor = descriptor;
    await descriptor.parent.create(recursive: true);
    await descriptor.writeAsString(
      jsonEncode({
        'version': protocolVersion,
        'pid': pid,
        'bankId': bank.bankId,
        'profileId': browser.profile.id,
        'bridgePort': server.port,
        'sessionId': _randomToken(length: 18),
        'token': _token,
        'startedAt': _startedAt!.toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _browser = null;
    _bank = null;
    _token = null;
    _startedAt = null;
    final descriptor = _descriptor;
    _descriptor = null;
    await server?.close(force: true);
    if (descriptor != null) {
      try {
        if (await descriptor.exists()) await descriptor.delete();
      } on Object {
        // Best-effort cleanup; the next session overwrites the descriptor.
      }
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.headers.add('Cache-Control', 'no-store');
    final remote = request.connectionInfo?.remoteAddress;
    if (remote == null ||
        (remote.address != InternetAddress.loopbackIPv4.address &&
            remote.address != InternetAddress.loopbackIPv6.address)) {
      await _respond(request, 403, {'error': 'LOOPBACK_ONLY'});
      return;
    }
    if (request.method != 'POST' || request.uri.path != '/v1/command') {
      await _respond(request, 404, {'error': 'NOT_FOUND'});
      return;
    }
    final expected = _token;
    final authorization = request.headers.value('authorization') ?? '';
    if (expected == null ||
        !_constantTimeEquals(authorization, 'Bearer ' + expected)) {
      await _respond(request, 401, {'error': 'UNAUTHORIZED'});
      return;
    }
    try {
      if ((request.contentLength) > 1024 * 1024) {
        throw const FormatException('Command body is too large');
      }
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('Command must be an object');
      }
      final command = decoded['command'];
      if (command is! String || command.trim().isEmpty) {
        throw const FormatException('Missing command');
      }
      final args = decoded['args'] is Map
          ? Map<String, dynamic>.from(decoded['args'] as Map)
          : <String, dynamic>{};
      final result = await _dispatch(
        command,
        args,
      ).timeout(const Duration(seconds: 35));
      await _respond(request, 200, {'ok': true, 'result': result});
    } on _DevBlockedAction catch (error) {
      await _respond(request, 403, {
        'ok': false,
        'error': 'BLOCKED_DANGEROUS_ACTION',
        'text': error.text,
        'reason': error.reason,
      });
    } on FormatException catch (error) {
      await _respond(request, 400, {'ok': false, 'error': error.message});
    } on TimeoutException {
      await _respond(request, 504, {
        'ok': false,
        'error': 'DEV_COMMAND_TIMEOUT',
      });
    } on Object catch (error) {
      await _respond(request, 500, {'ok': false, 'error': error.toString()});
    }
  }

  Future<Object?> _dispatch(String command, Map<String, dynamic> args) async {
    final browser = _browser;
    final bank = _bank;
    if (browser == null || bank == null || !isActive) {
      throw StateError('No active Qesto Bank Browser DEV session.');
    }
    switch (command.trim().toLowerCase()) {
      case 'status':
        return _status(browser, bank);
      case 'current-url':
        return (await browser.currentUrl())?.toString();
      case 'title':
        return await browser.title();
      case 'pages':
        return [
          {
            'frame': 'MAIN_FRAME',
            'url': (await browser.currentUrl())?.toString(),
          },
        ];
      case 'detect-page':
        final page = await const SberPageDetector().inspect(browser);
        return page == null
            ? 'UNKNOWN'
            : _pageTypeName(const SberPageDetector().detect(page));
      case 'snapshot':
        return _evalJson(browser, _snapshotScript(_intArg(args, 'limit', 120)));
      case 'dom':
      case 'source':
        return _evalString(browser, _domScript(args['selector'] as String?));
      case 'text':
        return _evalString(browser, _textScript(args['selector'] as String?));
      case 'query':
        return _evalJson(
          browser,
          _queryScript(args['selector'] as String?, false),
        );
      case 'query-all':
        return _evalJson(
          browser,
          _queryScript(args['selector'] as String?, true),
        );
      case 'attributes':
        return _evalJson(
          browser,
          _attributesScript(args['selector'] as String?),
        );
      case 'links':
        return _evalJson(browser, _linksScript(_intArg(args, 'limit', 100)));
      case 'buttons':
        return _evalJson(browser, _buttonsScript(_intArg(args, 'limit', 100)));
      case 'elements':
        final kind = args['kind'] as String?;
        if (kind != 'id' && kind != 'data-testid' && kind != 'data-test') {
          throw const FormatException(
            'elements requires kind=id|data-testid|data-test',
          );
        }
        return _evalJson(
          browser,
          _elementsScript(kind!, _intArg(args, 'limit', 200)),
        );
      case 'find':
        return _evalJson(
          browser,
          _findScript(args['text'] as String?, _intArg(args, 'limit', 50)),
        );
      case 'routes':
        return _evalJson(browser, _routesScript(_intArg(args, 'limit', 200)));
      case 'navigate':
        final raw = args['url'];
        if (raw is! String)
          throw const FormatException('navigate requires url');
        final uri = Uri.tryParse(raw);
        if (uri == null) throw const FormatException('Invalid URL');
        if (browser.securityPolicy.decide(uri, bank) !=
            NavigationDecision.allow) {
          throw _DevBlockedAction(
            uri.toString(),
            'Navigation is outside the bank origin allowlist',
          );
        }
        await browser.navigate(uri);
        return {'accepted': true, 'url': uri.toString()};
      case 'back':
        await browser.goBack();
        return true;
      case 'forward':
        await browser.goForward();
        return true;
      case 'reload':
        await browser.reload();
        return true;
      case 'click':
        final selector = args['selector'];
        if (selector is! String || selector.trim().isEmpty) {
          throw const FormatException('click requires selector');
        }
        final result = await _evalJson(browser, _safeClickScript(selector))
            .timeout(
              const Duration(seconds: 2),
              onTimeout: () => <String, Object?>{
                'ok': true,
                'scheduled': true,
                'timeout': true,
              },
            );
        if (result is Map && result['blocked'] == true) {
          throw _DevBlockedAction(
            result['text']?.toString() ?? selector,
            result['reason']?.toString() ?? 'financial mutation action',
          );
        }
        return result;
      case 'scroll':
        final direction = (args['direction'] as String? ?? 'down')
            .toLowerCase();
        if (direction != 'up' && direction != 'down') {
          throw const FormatException('scroll direction must be up|down');
        }
        final pixels = _intArg(args, 'pixels', 800).clamp(1, 5000).toInt();
        return _evalJson(
          browser,
          _scrollScript(direction == 'up' ? -pixels : pixels),
        );
      case 'scroll-to':
        final selector = args['selector'];
        if (selector is! String)
          throw const FormatException('scroll-to requires selector');
        return _evalJson(browser, _scrollToScript(selector));
      case 'wait':
        return _wait(browser, args);
      case 'wait-url':
        return _wait(browser, <String, dynamic>{
          ...args,
          'url': args['url'] ?? args['value'],
        });
      case 'wait-text':
        return _wait(browser, <String, dynamic>{
          ...args,
          'text': args['text'] ?? args['value'],
        });
      case 'wait-stable-dom':
        return _waitStableDom(browser, _intArg(args, 'timeoutMs', 10000));
      case 'mutations':
        return _mutations(
          browser,
          _intArg(args, 'seconds', 5).clamp(1, 30).toInt(),
        );
      case 'storage':
        final area = args['area'] as String?;
        if (area == 'keys') {
          return _evalJson(browser, _storageKeysScript());
        }
        if (area != 'local' && area != 'session') {
          throw const FormatException('storage requires area=local|session');
        }
        return _evalJson(
          browser,
          _storageScript(area!, args['values'] == true),
        );
      case 'run-extractor':
        final script = args['script'];
        if (script is! String || script.trim().isEmpty) {
          throw const FormatException('run-extractor requires script');
        }
        _validateExtractor(script);
        return _evalJson(
          browser,
          '(() => { /* ' + marker + ' */\n' + script + '\n})()',
        );
      case 'errors':
      case 'console':
      case 'network':
        return {
          'supported': false,
          'message':
              'CDP/network/console collection is not enabled in this CEF build.',
        };
      default:
        throw FormatException('Unknown command: $command');
    }
  }

  Future<Map<String, Object?>> _status(
    BrowserController browser,
    BankConnectorConfig bank,
  ) async {
    final url = await browser.currentUrl();
    final page = bank.bankId == 'sber'
        ? await const SberPageDetector().inspect(browser)
        : null;
    final pageType = page == null
        ? 'UNKNOWN'
        : _pageTypeName(const SberPageDetector().detect(page));
    return {
      'bank': bank.bankId,
      'profile': browser.profile.id,
      'browserRunning': browser.isRuntimeReady,
      'devMode': true,
      'currentUrl': url?.toString(),
      'origin': url == null
          ? null
          : browser.securityPolicy.normalizedOrigin(url),
      'title': await browser.title(),
      'authenticatedState': !{
        'LOGIN',
        'PIN_LOGIN',
        'UNKNOWN',
      }.contains(pageType),
      'pageType': pageType,
    };
  }

  Future<Object?> _wait(
    BrowserController browser,
    Map<String, dynamic> args,
  ) async {
    final timeout = _intArg(args, 'timeoutMs', 10000).clamp(100, 30000);
    final selector = args['selector'] as String?;
    final text = args['text'] as String?;
    final urlPart = args['url'] as String?;
    final end = DateTime.now().add(Duration(milliseconds: timeout));
    while (DateTime.now().isBefore(end)) {
      final value = await _evalJson(
        browser,
        _presenceScript(selector, text, urlPart),
      );
      if (value is Map && value['ok'] == true) return value;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return {'ok': false, 'timeout': true};
  }

  Future<Object?> _waitStableDom(
    BrowserController browser,
    int timeoutMs,
  ) async {
    final timeout = timeoutMs.clamp(250, 30000).toInt();
    final end = DateTime.now().add(Duration(milliseconds: timeout));
    String? previous;
    var stableSamples = 0;
    while (DateTime.now().isBefore(end)) {
      final metrics = await _evalJson(browser, _domMetricsScript());
      final signature = jsonEncode(metrics);
      if (signature == previous) {
        stableSamples += 1;
        if (stableSamples >= 3) {
          return {'ok': true, 'stableSamples': stableSamples};
        }
      } else {
        previous = signature;
        stableSamples = 0;
      }
      await Future<void>.delayed(const Duration(milliseconds: 160));
    }
    return {'ok': false, 'timeout': true};
  }

  Future<Object?> _mutations(BrowserController browser, int seconds) async {
    final before = await _evalJson(browser, _regionMetricsScript());
    await Future<void>.delayed(Duration(seconds: seconds));
    final after = await _evalJson(browser, _regionMetricsScript());
    return {'seconds': seconds, 'before': before, 'after': after};
  }

  Future<String?> _evalString(BrowserController browser, String script) async {
    final value = await browser.evaluateDevJavascript(script);
    return value is String ? value : value?.toString();
  }

  Future<Object?> _evalJson(BrowserController browser, String script) async {
    final value = await browser.evaluateDevJavascript(script);
    if (value is String) {
      try {
        return jsonDecode(value);
      } on Object {
        return value;
      }
    }
    return value;
  }

  Future<void> _respond(HttpRequest request, int status, Object body) async {
    request.response.statusCode = status;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  static int _intArg(Map<String, dynamic> args, String key, int fallback) {
    final value = args[key];
    return value is num ? value.toInt() : fallback;
  }

  static String _pageTypeName(SberPageType type) => switch (type) {
    SberPageType.pinLogin => 'PIN_LOGIN',
    SberPageType.accountDetails => 'ACCOUNT',
    SberPageType.dashboard => 'MAIN',
    SberPageType.transactions => 'OPERATIONS',
    SberPageType.accounts => 'ACCOUNTS',
    SberPageType.savings => 'SAVINGS',
    SberPageType.deposit => 'DEPOSIT',
    SberPageType.investments => 'INVESTMENTS',
    SberPageType.login => 'LOGIN',
    SberPageType.unknown => 'UNKNOWN',
  };

  static bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var mismatch = 0;
    for (var i = 0; i < left.length; i++) {
      mismatch |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
    }
    return mismatch == 0;
  }

  static String _randomToken({int length = 32}) {
    final random = Random.secure();
    return base64UrlEncode(
      List<int>.generate(length, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
  }

  static File _descriptorFile() {
    final root =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return File(
      root +
          Platform.pathSeparator +
          'Qesto' +
          Platform.pathSeparator +
          'dev' +
          Platform.pathSeparator +
          'session.json',
    );
  }

  static String _quote(Object? value) => jsonEncode(value ?? '');
  static String _selector(Object? selector) =>
      _quote(selector is String && selector.isNotEmpty ? selector : 'body');

  static String _snapshotScript(int limit) =>
      '(() => { /* ' +
      marker +
      ' */ const clean=v=>String(v||\"\").replace(/\\\\s+/g,\" \").trim(); const visible=n=>{const s=getComputedStyle(n),r=n.getBoundingClientRect();return s.display!==\"none\"&&s.visibility!==\"hidden\"&&r.width>0&&r.height>0;}; const pick=n=>({tag:n.tagName.toLowerCase(),text:clean(n.innerText||n.textContent).slice(0,500),id:n.id||\"\",testid:n.getAttribute(\"data-testid\")||\"\",test:n.getAttribute(\"data-test\")||\"\",aria:n.getAttribute(\"aria-label\")||\"\",href:(n.getAttribute(\"href\")||\"\").split(\"?\")[0],role:n.getAttribute(\"role\")||\"\",disabled:!!n.disabled}); const all=[...document.querySelectorAll(\"body *\")].filter(visible); const by=s=>all.filter(n=>n.matches(s)).slice(0,' +
      limit.toString() +
      ').map(pick); return JSON.stringify({url:location.href.split(\"?\")[0],title:document.title,headings:by(\"h1,h2,h3,h4\"),landmarks:by(\"main,nav,header,[role=main]\"),links:by(\"a\"),buttons:by(\"button,[role=button]\"),inputs:by(\"input,textarea,select\"),lists:by(\"ul,ol,[role=list]\"),ids:all.filter(n=>n.id).slice(0,' +
      limit.toString() +
      ').map(pick),testIds:all.filter(n=>n.getAttribute(\"data-testid\")||n.getAttribute(\"data-test\")).slice(0,' +
      limit.toString() +
      ').map(pick),text:clean(document.body&&document.body.innerText).slice(0,20000)}); })()';
  static String _domScript(String? selector) =>
      '(() => { /* ' +
      marker +
      ' */ const n=document.querySelector(' +
      _selector(selector) +
      '); return n ? (n.outerHTML || \"\") : \"\"; })()';
  static String _textScript(String? selector) =>
      '(() => { /* ' +
      marker +
      ' */ const n=document.querySelector(' +
      _selector(selector) +
      '); return n ? (n.innerText || n.textContent || \"\") : \"\"; })()';
  static String _queryScript(String? selector, bool all) =>
      '(() => { /* ' +
      marker +
      ' */ const describe=x=>{const r=x.getBoundingClientRect(); return {tag:x.tagName.toLowerCase(),text:(x.innerText||x.textContent||\"\").slice(0,1000),id:x.id||\"\",classes:typeof x.className===\"string\"?x.className.slice(0,500):\"\",href:(x.href||x.getAttribute(\"href\")||\"\").split(\"?\")[0],role:x.getAttribute(\"role\")||\"\",aria:x.getAttribute(\"aria-label\")||\"\",testid:x.getAttribute(\"data-testid\")||\"\",dataTest:x.getAttribute(\"data-test\")||\"\",disabled:!!x.disabled,rect:{x:Math.round(r.x),y:Math.round(r.y),width:Math.round(r.width),height:Math.round(r.height)}}}; const n=document.querySelectorAll(' +
      _selector(selector) +
      '); return JSON.stringify(' +
      (all ? '[...n].slice(0,500).map(describe)' : 'n[0]?describe(n[0]):null') +
      '); })()';
  static String _attributesScript(String? selector) =>
      '(() => { /* ' +
      marker +
      ' */ const n=document.querySelector(' +
      _selector(selector) +
      '); return JSON.stringify(n ? Object.fromEntries([...n.attributes].map(a=>[a.name,a.value])) : null); })()';
  static String _linksScript(int limit) =>
      '(() => { /* ' +
      marker +
      ' */ return JSON.stringify([...document.querySelectorAll(\"a\")].slice(0,' +
      limit.toString() +
      ').map(n=>({text:(n.innerText||\"\").trim(),href:(n.href||\"\").split(\"?\")[0],aria:n.getAttribute(\"aria-label\")||\"\",id:n.id||\"\",testid:n.getAttribute(\"data-testid\")||\"\"}))); })()';
  static String _buttonsScript(int limit) =>
      '(() => { /* ' +
      marker +
      ' */ return JSON.stringify([...document.querySelectorAll(\"button,[role=button]\")].slice(0,' +
      limit.toString() +
      ').map(n=>({text:(n.innerText||\"\").trim(),aria:n.getAttribute(\"aria-label\")||\"\",id:n.id||\"\",testid:n.getAttribute(\"data-testid\")||\"\",disabled:!!n.disabled}))); })()';
  static String _elementsScript(String kind, int limit) =>
      '(() => { /* ' +
      marker +
      ' */ const a=' +
      _quote(kind) +
      '; return JSON.stringify([...document.querySelectorAll(\"[\"+a+\"]\")].slice(0,' +
      limit.toString() +
      ').map(n=>({tag:n.tagName.toLowerCase(),value:n.getAttribute(a),text:(n.innerText||n.textContent||\"\").trim().slice(0,500)}))); })()';
  static String _findScript(String? text, int limit) =>
      '(() => { /* ' +
      marker +
      ' */ const q=' +
      _quote(text).toLowerCase() +
      '; return JSON.stringify([...document.querySelectorAll(\"body *\")].filter(n=>(n.innerText||n.textContent||\"\").toLowerCase().includes(q)).slice(0,' +
      limit.toString() +
      ').map(n=>({tag:n.tagName.toLowerCase(),text:(n.innerText||n.textContent||\"\").trim().slice(0,500),id:n.id||\"\",testid:n.getAttribute(\"data-testid\")||\"\"}))); })()';
  static String _routesScript(int limit) =>
      '(() => { /* ' +
      marker +
      ' */ const r=new Set(); for(const n of document.querySelectorAll(\"a[href]\")){try{const u=new URL(n.href);if(u.origin===location.origin&&u.pathname.startsWith(\"/app/\"))r.add(u.pathname);}catch(_){}} return JSON.stringify([...r].slice(0,' +
      limit.toString() +
      ')); })()';
  static String _safeClickScript(String selector) =>
      '(() => { /* ' +
      marker +
      ' */ const n=document.querySelector(' +
      _selector(selector) +
      '); if(!n)return JSON.stringify({ok:false,reason:\"not-found\"}); const text=(n.innerText||n.textContent||n.getAttribute(\"aria-label\")||\"\").replace(/\\\\s+/g,\" \").trim(); if(/перевести|оплатить|отправить|подтвердить|купить|продать|обменять|пополнить|снять|вывести|оформить|подать заявку|заказать|открыть продукт|закрыть (счет|вклад)|погасить|взять кредит|выпустить карту/i.test(text))return JSON.stringify({ok:false,blocked:true,text,reason:\"financial mutation action\"}); setTimeout(()=>n.click(),1000); return JSON.stringify({ok:true,text,scheduled:true}); })()';
  static String _scrollScript(int pixels) =>
      '(() => { /* ' +
      marker +
      ' */ const before=scrollY; scrollBy(0,' +
      pixels.toString() +
      '); return JSON.stringify({before,after:scrollY,moved:after!==before}); })()'
          .replaceAll('after!==before', 'scrollY!==before');
  static String _scrollToScript(String selector) =>
      '(() => { /* ' +
      marker +
      ' */ const n=document.querySelector(' +
      _selector(selector) +
      '); if(!n)return JSON.stringify({ok:false,reason:\"not-found\"}); n.scrollIntoView({block:\"center\"}); return JSON.stringify({ok:true}); })()';
  static String _presenceScript(String? selector, String? text, String? url) =>
      '(() => { /* ' +
      marker +
      ' */ const ok=' +
      (selector == null
          ? 'true'
          : '!!document.querySelector(' + _selector(selector) + ')') +
      ' && ' +
      (text == null
          ? 'true'
          : 'String(document.body&&document.body.innerText||\"\").toLowerCase().includes(' +
                _quote(text).toLowerCase() +
                ')') +
      ' && ' +
      (url == null
          ? 'true'
          : 'location.pathname.includes(' + _quote(url) + ')') +
      '; return JSON.stringify({ok,url:location.pathname}); })()';
  static String _domMetricsScript() =>
      '(() => { /* ' +
      marker +
      ' */ return JSON.stringify({url:location.pathname,title:document.title,nodes:document.querySelectorAll(\"body *\").length,text:(document.body&&document.body.innerText||\"\").length}); })()';
  static String _regionMetricsScript() =>
      '(() => { /* ' +
      marker +
      ' */ const labels=new Map(); for(const n of document.querySelectorAll(\"[id],[data-testid],[data-test],main,section,nav\")){const key=n.id||n.getAttribute(\"data-testid\")||n.getAttribute(\"data-test\")||n.tagName.toLowerCase(); labels.set(key,(labels.get(key)||0)+1);} return JSON.stringify({nodes:document.querySelectorAll(\"body *\").length,regions:[...labels.entries()].map(([region,count])=>({region,count})).slice(0,200)}); })()';
  static String _storageScript(String area, bool values) =>
      '(() => { /* ' +
      marker +
      ' */ const s=window.' +
      area +
      'Storage; const keys=[...Array(s.length)].map((_,i)=>s.key(i)).filter(Boolean); return JSON.stringify({area:' +
      _quote(area) +
      ',keys,values:' +
      (values ? 'Object.fromEntries(keys.map(k=>[k,s.getItem(k)]))' : 'null') +
      '}); })()';
  static String _storageKeysScript() =>
      '(() => { /* ' +
      marker +
      ' */ const read=s=>[...Array(s.length)].map((_,i)=>s.key(i)).filter(Boolean); return JSON.stringify({local:read(window.localStorage),session:read(window.sessionStorage)}); })()';

  static void _validateExtractor(String script) {
    if (RegExp(
      r'document\.cookie|fetch\s*\(|XMLHttpRequest|sendBeacon|\.submit\s*\(|'
      r'\b(?:window\.)?location(?:\.(?:href|assign|replace))?\s*=|'
      r'\b(?:window\.)?location\.(?:assign|replace)\s*\(|'
      r'\bhistory\.(?:pushState|replaceState)\s*\(|'
      r'\bwindow\.open\s*\(|\.click\s*\(',
    ).hasMatch(script)) {
      throw const FormatException(
        'Extractor is read-only; network/navigation/click mutations are blocked',
      );
    }
  }
}

class _DevBlockedAction implements Exception {
  const _DevBlockedAction(this.text, this.reason);
  final String text;
  final String reason;
}
