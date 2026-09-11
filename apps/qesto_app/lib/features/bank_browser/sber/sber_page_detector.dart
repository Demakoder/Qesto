import 'dart:convert';

import '../domain/bank_browser_models.dart';
import '../runtime/browser_controller.dart';
import 'sber_connector_models.dart';

class SberPageSnapshot {
  const SberPageSnapshot({
    required this.url,
    required this.title,
    required this.text,
    required this.pinMarkers,
    required this.loginMarkers,
  });

  final Uri url;
  final String title;
  final String text;
  final List<String> pinMarkers;
  final List<String> loginMarkers;

  double get pinConfidence {
    var score = 0.0;
    if (pinMarkers.any((value) => value == 'pin-heading')) score += 0.45;
    if (pinMarkers.any((value) => value == 'keypad')) score += 0.35;
    if (pinMarkers.any((value) => value == 'pin-input')) score += 0.2;
    return score.clamp(0, 1).toDouble();
  }
}

class SberPageDetector {
  const SberPageDetector();

  static const marker = 'QESTO_SBER_READ_V1';

  Future<SberPageSnapshot?> inspect(BrowserController browser) async {
    final url = await browser.currentUrl();
    if (url == null ||
        browser.securityPolicy.decide(url, browser.bank) !=
            NavigationDecision.allow) {
      return null;
    }
    browser.setMode(BrowserMode.read);
    final raw = await browser.evaluateConnectorJavascript(_inspectionScript);
    if (raw is! String || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return SberPageSnapshot(
        url: url,
        title: json['title'] as String? ?? '',
        text: json['text'] as String? ?? '',
        pinMarkers: _strings(json['pinMarkers']),
        loginMarkers: _strings(json['loginMarkers']),
      );
    } on Object {
      return null;
    }
  }

  SberPageType detect(SberPageSnapshot value) {
    final path = value.url.path.toLowerCase();
    final text = '${value.title} ${value.text}'.toLowerCase();
    if (value.pinConfidence >= 0.8) return SberPageType.pinLogin;
    if (_containsAny(text, const ['войти', 'логин', 'пароль', 'авторизация']) &&
        !_containsAny(text, const ['счета', 'операции', 'баланс'])) {
      return SberPageType.login;
    }
    // Sber renders a route-identical shell while its SPA is still booting.
    // Do not treat /app/main (or any other route) as authenticated while the
    // only visible content is a loading placeholder; extractors would then
    // see an empty DOM and could incorrectly report a successful sync.
    if (_containsAny(text, const ['идёт загрузка', 'идет загрузка'])) {
      return SberPageType.unknown;
    }
    if (value.text.trim().isEmpty &&
        value.pinMarkers.isEmpty &&
        value.loginMarkers.isEmpty) {
      return SberPageType.unknown;
    }
    // The main dashboard contains cards titled "Накопления", "Кредиты"
    // and other product names. Route identity is stronger than those shared
    // labels, otherwise /app/main is misclassified as a product page. Keep it
    // after login detection so a session-expired shell cannot look authorized.
    if (path == '/app/main' || path == '/main') {
      return SberPageType.dashboard;
    }
    if (path.contains('/app/cta/details/')) {
      return SberPageType.accountDetails;
    }
    if (path == '/app/wallet' || path == '/app/accounts') {
      return SberPageType.accounts;
    }
    // Route identity must win over transaction descriptions. An operations
    // list can contain words such as "Накопления" or "Инвестиции" and must
    // never be mistaken for those product sections.
    if (_containsAny(path, const ['operation', 'transaction', 'history'])) {
      return SberPageType.transactions;
    }
    if (_containsAny(path, const ['invest', 'broker']) ||
        _containsAny(text, const [
          'инвестиции',
          'брокерский счет',
          'портфель',
        ])) {
      return SberPageType.investments;
    }
    if (_containsAny(path, const ['deposit', 'vklad']) ||
        _containsAny(text, const ['вклады', 'депозиты'])) {
      return SberPageType.deposit;
    }
    if (_containsAny(path, const ['saving', 'nakop']) ||
        _containsAny(text, const ['накопления', 'накопительный счет'])) {
      return SberPageType.savings;
    }
    if (_containsAny(text, const [
      'история операций',
      'операции',
      'транзакции',
    ])) {
      return SberPageType.transactions;
    }
    if (_containsAny(path, const ['account', 'card']) ||
        _containsAny(text, const ['счета', 'карты', 'баланс'])) {
      return SberPageType.accounts;
    }
    if (_containsAny(text, const ['добрый день', 'мои финансы', 'главная'])) {
      return SberPageType.dashboard;
    }
    return SberPageType.unknown;
  }

  static bool _containsAny(String source, Iterable<String> values) =>
      values.any(source.contains);

  static List<String> _strings(Object? value) =>
      (value as List? ?? const []).whereType<String>().toList(growable: false);
}

const _inspectionScript = '''(() => {
  /* QESTO_SBER_READ_V1: metadata only; no cookies, storage or network. */
  const clean = (value) => String(value || '').replace(/\\s+/g, ' ').trim();
  const visible = (node) => {
    if (!node) return false;
    const style = getComputedStyle(node);
    return style.display !== 'none' && style.visibility !== 'hidden' &&
      node.getBoundingClientRect().width > 0 && node.getBoundingClientRect().height > 0;
  };
  const text = clean(document.body && document.body.innerText).slice(0, 12000);
  const all = Array.from(document.querySelectorAll('button,[role="button"],input,[class*="key"],[class*="pin"]'))
    .filter(visible);
  const labels = all.map((node) => clean(node.getAttribute('aria-label') || node.getAttribute('data-testid') || node.innerText));
  const lower = labels.map((value) => value.toLowerCase());
  const pinMarkers = [];
  if (lower.some((value) => /пин|pin|быстр(ый|ого) вход/.test(value))) pinMarkers.push('pin-heading');
  if (all.filter((node) => /button|key/i.test(node.tagName + ' ' + (node.className || '') + ' ' + (node.getAttribute('data-testid') || ''))).length >= 6) pinMarkers.push('keypad');
  if (all.some((node) => /pin|пин/i.test(node.getAttribute('name') || '') || /pin|пин/i.test(node.getAttribute('aria-label') || ''))) pinMarkers.push('pin-input');
  const loginMarkers = [];
  if (/логин|пароль|войти|авторизац/i.test(text)) loginMarkers.push('login');
  return JSON.stringify({ title: clean(document.title), text, pinMarkers, loginMarkers });
})()''';
