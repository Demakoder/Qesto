import '../runtime/browser_controller.dart';
import '../../../core/safety/financial_write_guard.dart';

/// Bounded DOM readiness, not a network-idle heuristic (banks may long-poll).
class SberReadiness {
  const SberReadiness({
    this.timeout = const Duration(seconds: 30),
    this.pollInterval = const Duration(milliseconds: 500),
  });

  final Duration timeout;
  final Duration pollInterval;

  Future<String> probe(BrowserController browser) async {
    FinancialWriteGuard.check();
    try {
      final state = await browser
          .evaluateConnectorJavascript(_readinessScript)
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      return state is String ? state : 'unknown';
    } on Exception {
      return 'unknown';
    }
  }

  Future<bool> wait(BrowserController browser) async {
    final elapsed = Stopwatch()..start();
    while (elapsed.elapsed < timeout) {
      final state = await probe(browser);
      if (state == 'ready') return true;
      if (state == 'auth' || state == 'blocked') return false;
      await Future<void>.delayed(pollInterval);
    }
    return false;
  }
}

const _readinessScript = r'''(() => {
  /* QESTO_SBER_READ_V1: page readiness without reload or request replay. */
  const visible = n => n && n.getBoundingClientRect().width > 0 &&
    n.getBoundingClientRect().height > 0 && getComputedStyle(n).visibility !== 'hidden';
  const text = String(document.body?.innerText || '').replace(/\s+/g, ' ').trim();
  const shown = selector => [...document.querySelectorAll(selector)].some(visible);
  if (shown('iframe[src*="captcha"],[data-testid*="captcha"]') ||
      /подтвердите,? что вы не робот|доступ временно ограничен|пройдите проверку безопасности/i.test(text)) return 'blocked';
  if (shown('input[type="password"]') || /введите (?:пин|pin)[ -]?код/i.test(text)) return 'auth';
  if (document.readyState === 'loading' || !text ||
      shown('[aria-busy="true"],[role="progressbar"],[class*="loader"],[class*="Loader"],[class*="spinner"],[class*="Spinner"]') ||
      /ид[её]т загрузка|загружаем (?:операции|данные|историю)/i.test(text)) return 'loading';
  if (location.pathname === '/app/operations' &&
      !shown('a[href*="/app/operations/details"],a[href*="/app/transfers/sberhub"],a[href*="/app/payments/sbp"],ul[aria-label*="Операции"] li') &&
      !/операци[ийя]+ не найден|нет операций|операций пока нет|у вас пока нет операций/i.test(text)) return 'loading';
  return 'ready';
})()''';
