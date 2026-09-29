import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/bank_browser/config/bank_connector_registry.dart';
import 'package:qesto/features/bank_browser/data/browser_profile_manager.dart';
import 'package:qesto/features/bank_browser/domain/bank_browser_models.dart';
import 'package:qesto/features/bank_browser/runtime/browser_controller.dart';
import 'package:qesto/features/bank_browser/sber/sber_navigator.dart';
import 'package:qesto/features/bank_browser/sber/sber_readiness.dart';

void main() {
  const readiness = SberReadiness(
    timeout: Duration(milliseconds: 80),
    pollInterval: Duration(milliseconds: 1),
  );
  test('waits through loading and transient unknown observations', () async {
    final browser = _Browser(['loading', 'unknown', 'loading', 'ready']);
    expect(await readiness.wait(browser), isTrue);
    expect(browser.probes, 4);
    expect(browser.clicks, 0);
  });
  test('stalled loading returns bounded failure without reload', () async {
    final browser = _Browser(['loading']);
    expect(await readiness.wait(browser), isFalse);
    expect(browser.clicks, 0);
  });
  for (final state in ['auth', 'blocked']) {
    test('$state stops before any history click', () async {
      final browser = _Browser([state]);
      expect(
        await const SberNavigator(
          readiness: readiness,
        ).openTransactions(browser),
        isFalse,
      );
      expect(browser.probes, 1);
      expect(browser.clicks, 0);
    });
  }
  test('history uses one SPA click and never a direct navigation', () async {
    final browser = _Browser(['ready']);
    expect(
      await const SberNavigator(readiness: readiness).openTransactions(browser),
      isTrue,
    );
    expect(browser.clicks, 1);
  });
  test(
    'missing product-history link does not synthesize a deep link',
    () async {
      final browser = _Browser(['ready']);
      expect(
        await const SberNavigator(
          readiness: readiness,
        ).openProductHistory(browser, 'card:1234', ['1234']),
        isFalse,
      );
      expect(browser.clicks, 0);
    },
  );
}

class _Browser extends BrowserController {
  _Browser(this.states)
    : super(
        profile: BankProfile(
          id: 'test',
          bankId: 'sber',
          displayName: 'Test',
          createdAt: DateTime(2026),
          lastOpenedAt: DateTime(2026),
        ),
        bank: BankConnectorRegistry.sber,
        profileManager: BrowserProfileManager(),
        onNotice: (_) {},
      );
  final List<String> states;
  int probes = 0;
  int clicks = 0;
  @override
  Future<void> navigate(Uri uri) async =>
      throw StateError('Unexpected direct navigation');
  @override
  Future<dynamic> evaluateConnectorJavascript(
    String script, {
    BrowserMode mode = BrowserMode.read,
  }) async {
    if (script.contains('page readiness without reload')) {
      final index = probes++;
      return states[index < states.length ? index : states.length - 1];
    }
    if (script.contains('open History More through the bank SPA')) {
      clicks++;
      return '1';
    }
    if (script.contains("location.pathname === '/app/operations'")) return '1';
    return '0';
  }
}
