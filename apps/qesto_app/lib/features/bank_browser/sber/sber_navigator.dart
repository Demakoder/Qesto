import 'dart:convert';
import '../runtime/browser_controller.dart';
import 'sber_readiness.dart';

class SberNavigator {
  const SberNavigator({this.readiness = const SberReadiness()});

  final SberReadiness readiness;

  /// Uses the bank's observed usedResource protocol, never an external URL.
  Future<bool> openProductHistory(
    BrowserController browser,
    String resource,
    List<String> expectedSuffixes,
  ) async {
    if (!RegExp(r'^card:\d+$').hasMatch(resource) || expectedSuffixes.isEmpty) {
      return false;
    }
    if (!await readiness.wait(browser)) return false;
    // Never synthesize a full-page bank navigation. Only follow an actual
    // read-only product-history link exposed by the current bank UI.
    final clicked = await browser.evaluateConnectorJavascript('''(() => {
      /* QESTO_SBER_READ_V1: observed product history link only. */
      const matches = [...document.querySelectorAll('a[href]')].filter(n => {
        const u = new URL(n.getAttribute('href'), location.href);
        return u.origin === location.origin && u.pathname === '/app/operations' &&
          u.searchParams.get('usedResource') === ${jsonEncode(resource)} &&
          n.getBoundingClientRect().width > 0 && n.getBoundingClientRect().height > 0;
      });
      if (matches.length !== 1) return '0';
      matches[0].click(); return '1';
    })()''');
    if (clicked != '1' || !await readiness.wait(browser)) return false;
    var stable = 0;
    for (var attempt = 0; attempt < 24; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final ready = await browser.evaluateConnectorJavascript('''(() => {
        /* QESTO_SBER_READ_V1 */
        const n = document.querySelector('[data-filter="product"]');
        const t = n && n.innerText || '';
        return new URL(location.href).searchParams.get('usedResource') === ${jsonEncode(resource)} &&
          ${jsonEncode(expectedSuffixes)}.some(s => t.includes(s)) &&
          !document.querySelector('[aria-busy="true"]') ? '1' : '0';
      })()''');
      stable = ready == '1' ? stable + 1 : 0;
      if (stable >= 3) return true;
    }
    return false;
  }

  Future<bool> openDashboard(BrowserController browser) => _open(
    browser,
    const ['главная', 'на главную'],
    hrefHints: const ['/app/main', '/main'],
  );

  Future<bool> openAccounts(BrowserController browser) => _open(
    browser,
    const [
      'все счета',
      'все счета и карты',
      'счета и карты',
      'счета',
      'мои счета',
    ],
    hrefHints: const ['/app/wallet', '/app/accounts'],
  );

  Future<bool> openTransactions(BrowserController browser) async {
    if (!await readiness.wait(browser)) return false;
    final opened = await browser.evaluateConnectorJavascript(
      _historyLinkScript,
    );
    if (opened != '1') return false;
    // Follow the SPA's History → More link once. Reloading this URL directly
    // discards route state and can leave the bank on an endless loading shell.
    for (var attempt = 0; attempt < 60; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final ready = await browser.evaluateConnectorJavascript('''(() => {
        /* QESTO_SBER_READ_V1 */
        const n = document.querySelector('[data-filter="product"]');
        return location.pathname === '/app/operations' &&
          !new URL(location.href).searchParams.has('usedResource') && n &&
          !/\\d{4}/.test(n.innerText || '') ? '1' : '0';
      })()''');
      if (ready == '1') return readiness.wait(browser);
      final state = await readiness.probe(browser);
      if (state == 'auth' || state == 'blocked') return false;
    }
    return false;
  }

  Future<bool> _open(
    BrowserController browser,
    List<String> labels, {
    List<String> hrefHints = const [],
  }) async {
    if (!await readiness.wait(browser)) return false;
    final encoded = labels.map(_quote).join(',');
    final encodedHints = hrefHints.map(_quote).join(',');
    final raw = await browser
        .evaluateConnectorJavascript('''(() => {
        /* QESTO_SBER_READ_V1: click only an unambiguous read-only navigation item. */
        const labels = [$encoded];
        const hrefHints = [$encodedHints];
        const visible = (node) => {
          const style = getComputedStyle(node);
          return style.display !== 'none' && style.visibility !== 'hidden' &&
            node.getBoundingClientRect().width > 0 && node.getBoundingClientRect().height > 0;
        };
        const text = (node) => String(node.innerText || node.getAttribute('aria-label') || '').replace(/\\s+/g, ' ').trim().toLowerCase();
        const candidates = Array.from(document.querySelectorAll('a,button,[role="link"],[role="button"]')).filter(visible);
        const hrefMatches = candidates.filter((node) => {
          const href = String(node.getAttribute('href') || '').split('?')[0].toLowerCase();
          return hrefHints.some((hint) => href === hint || href.startsWith(hint + '/'));
        });
        const score = (node) => {
          const value = text(node);
          let best = 10000;
          labels.forEach((label, index) => {
            if (value === label) best = Math.min(best, index);
            else if (value.startsWith(label + ' ') || value.endsWith(' ' + label)) best = Math.min(best, 100 + index);
            else if (value.includes(label)) best = Math.min(best, 200 + index);
          });
          return best;
        };
        if (hrefMatches.length > 0) {
          hrefMatches.sort((left, right) => score(left) - score(right) || text(left).length - text(right).length);
          setTimeout(() => hrefMatches[0].click(), 500);
          return '1';
        }
        const matches = candidates.filter((node) => {
          const value = text(node);
          return labels.some((label) => value === label || value.startsWith(label + ' ') || value.endsWith(' ' + label));
        });
        if (matches.length !== 1) return '0';
        setTimeout(() => matches[0].click(), 500);
        return '1';
      })()''')
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (raw != '1') return false;
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return true;
  }

  static String _quote(String value) => "'${value.replaceAll("'", "\\'")}'";
}

const _historyLinkScript = r'''(() => {
  /* QESTO_SBER_READ_V1: open History More through the bank SPA. */
  const clean = s => String(s || '').replace(/\s+/g, ' ').trim();
  const links = [...document.querySelectorAll('a[href]')].filter(n => {
    const u = new URL(n.getAttribute('href'), location.href);
    return u.origin === location.origin && u.pathname === '/app/operations' &&
      !u.searchParams.has('usedResource') && n.getBoundingClientRect().width > 0 &&
      n.getBoundingClientRect().height > 0;
  });
  const history = links.filter(n => /^история(?: операций)?$/i.test(
    clean(n.closest('section')?.querySelector('h1,h2,h3,h4')?.innerText)) &&
    /^(ещ[её]|все операции)$/i.test(clean(n.innerText)));
  const matches = history.length ? history : links;
  if (matches.length !== 1) return '0';
  matches[0].click(); return '1';
})()''';
