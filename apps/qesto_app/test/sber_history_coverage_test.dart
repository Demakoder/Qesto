import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/bank_browser/config/bank_connector_registry.dart';
import 'package:qesto/features/bank_browser/data/browser_profile_manager.dart';
import 'package:qesto/features/bank_browser/domain/bank_browser_models.dart';
import 'package:qesto/features/bank_browser/runtime/browser_controller.dart';
import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_extractors.dart';

Map<String, dynamic> _row(String id, String date) => {
  'id': id,
  'text': 'Магазин 10,25 ₽',
  'amount': '10,25 ₽',
  'dateIso': date,
};
final _range = SberSyncRange(
  from: DateTime(2026, 8),
  toExclusive: DateTime(2026, 9),
  label: 'August',
);

void main() {
  test('a re-rendered provider row replaces its pending observation', () async {
    final browser = _History([
      [
        {..._row('same', '2026-08-20'), 'text': 'Магазин 10,25 ₽ В обработке'},
      ],
      [_row('same', '2026-08-20'), _row('boundary', '2026-07-31')],
    ], moving: true);
    final result = await const SberExtractors().transactions(
      browser,
      range: _range,
      maxScrolls: 3,
    );
    expect(result.transactions, hasLength(1));
    expect(result.transactions.single.status, 'POSTED');
    expect(result.rawRowsSeen, 2);
    expect(result.transactions.single.amountMinor, 1025);
  });
  test('every observation from pagination polling is retained', () async {
    final browser = _History([
      [_row('first', '2026-08-30')],
      [_row('only-during-wait', '2026-08-20')],
      [_row('last', '2026-08-10'), _row('boundary', '2026-07-31')],
    ]);
    final result = await const SberExtractors().transactions(
      browser,
      range: _range,
      maxScrolls: 3,
    );
    expect(result.transactions.map((r) => r.sourceId).toSet(), {
      'first',
      'only-during-wait',
      'last',
    });
    expect(result.rawRowsSeen, 4);
    expect(result.rangeBoundaryReached, isTrue);
  });

  test('iteration cap without pagination button is still incomplete', () async {
    final browser = _History([
      [_row('first', '2026-08-30')],
    ], moving: true);
    final result = await const SberExtractors().transactions(
      browser,
      range: _range,
      maxScrolls: 1,
    );
    expect(result.rangeBoundaryReached, isFalse);
    expect(
      result.hasMoreRows,
      isTrue,
      reason: 'Absence of a button does not prove a complete scroll',
    );
  });

  test(
    'history returns to top before reading a restored scroll position',
    () async {
      final browser = _History([
        [_row('boundary', '2026-07-31')],
      ]);
      await const SberExtractors().transactions(browser, range: _range);
      expect(browser.resetBeforeFirstRead, isTrue);
    },
  );
}

class _History extends BrowserController {
  _History(this.frames, {this.moving = false})
    : super(
        profile: BankProfile(
          id: 'sber-test-history',
          bankId: 'sber',
          displayName: 'Test',
          createdAt: DateTime(2026),
          lastOpenedAt: DateTime(2026),
          lastKnownUrl: Uri.parse('https://online.sberbank.ru/app/operations'),
        ),
        bank: BankConnectorRegistry.sber,
        profileManager: BrowserProfileManager(),
        onNotice: (_) {},
      );
  final List<List<Map<String, dynamic>>> frames;
  final bool moving;
  var reads = 0;
  var reset = false;
  var resetBeforeFirstRead = false;
  @override
  Future<dynamic> evaluateConnectorJavascript(
    String script, {
    BrowserMode mode = BrowserMode.read,
  }) async {
    if (script.contains('page readiness without reload')) return 'ready';
    if (script.contains('leave the bank page in a predictable position')) {
      reset = true;
      return '1';
    }
    if (script.contains('visible transaction facts')) {
      if (reads == 0) resetBeforeFirstRead = reset;
      return jsonEncode(frames[(reads++).clamp(0, frames.length - 1)]);
    }
    if (script.contains('advance a visible read-only history list')) {
      return moving ? '1' : '0';
    }
    if (script.contains('expand only the read-only operation history')) {
      return '1';
    }
    return '0';
  }
}
