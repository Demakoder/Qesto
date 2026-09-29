import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/statement_import/services/sberbank_statement_parser.dart';
import 'statement_parser_test.dart' show redactedSberStatementText;

const _controls = '''
ИТОГО ПО ОПЕРАЦИЯМ ЗА ПЕРИОД:
Остаток на 01.07.2026 5 707,60
Пополнение 1 040,00
Списание 737,48
Остаток на 31.07.2026 6 010,12
''';
String _source({String controls = _controls}) => redactedSberStatementText
    .replaceFirst('Расшифровка операций', '$controls\nРасшифровка операций');

void main() {
  const parser = SberbankStatementParser();
  test('statement identity uses the complete account, not its last four', () {
    final first = parser.parse(_source());
    final other = parser.parse(
      _source().replaceFirst(
        '40817 810 0 0000 0012345',
        '40817 810 0 9999 0012345',
      ),
    );
    expect(first.sourceAccountKey, isNotNull);
    expect(first.accountLastFour, other.accountLastFour);
    expect(first.sourceAccountKey, isNot(other.sourceAccountKey));
    expect(first.sourceAccountKey, isNot(contains('40817')));
  });
  test(
    'PDF printed controls reconcile exactly including transfers and refunds',
    () {
      final statement = parser.parse(_source());
      expect(statement.sourceRowCount, 4);
      expect(statement.inflowsMinor, 104000);
      expect(statement.outflowsMinor, 73748);
      expect(statement.controlTotals?.openingMinor, 570760);
      expect(statement.closingBalanceMinor, 601012);
      expect(statement.controlTotalsVerified, isTrue);
      expect(statement.hasReconciliationMismatch, isFalse);
    },
  );
  test('a skipped malformed row cannot pass document reconciliation', () {
    final statement = parser.parse(
      _source().replaceFirst(
        '07.07.2026 737816 MAGNIT TEST MOSCOW RUS. Операция по карте',
        'Повреждённая строка',
      ),
    );
    expect(statement.sourceRowCount, 4);
    expect(statement.transactions, hasLength(3));
    expect(statement.hasReconciliationMismatch, isTrue);
    expect(statement.controlTotalsVerified, isFalse);
  });
  test(
    'one kopeck discrepancy is detected and printed closing balance retained',
    () {
      final statement = parser.parse(
        _source(controls: _controls.replaceFirst('6 010,12', '6 010,13')),
      );
      expect(statement.hasReconciliationMismatch, isTrue);
      expect(statement.closingBalanceMinor, 601013);
    },
  );
  test('no controls means unavailable, not a made-up opening balance', () {
    final statement = parser.parse(redactedSberStatementText);
    expect(statement.controlTotals, isNull);
    expect(statement.controlTotalsVerified, isFalse);
    expect(statement.hasReconciliationMismatch, isFalse);
  });
  test('controls from different dates are not used as period anchors', () {
    final statement = parser.parse(
      _source(controls: _controls.replaceFirst('01.07.2026', '01.06.2026')),
    );
    expect(statement.controlTotals, isNull);
  });
}
