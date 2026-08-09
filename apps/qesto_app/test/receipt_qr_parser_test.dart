import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/receipt_import/domain/receipt_models.dart';
import 'package:qesto/features/receipt_import/services/receipt_qr_parser.dart';
import 'package:qesto/features/receipt_import/services/receipt_transaction_matcher.dart';

void main() {
  const parser = ReceiptQrParser();
  const matcher = ReceiptTransactionMatcher();

  group('ReceiptQrParser', () {
    test('разбирает фискальный QR покупки', () {
      final receipt = parser.parse(
        't=20260809T1430&s=1250.50&fn=9282440300999999&'
        'i=123456&fp=987654321&n=1',
      );

      expect(receipt.purchasedAt, DateTime(2026, 8, 9, 14, 30));
      expect(receipt.amountMinor, 125050);
      expect(receipt.roundedRubles, 1251);
      expect(receipt.kind, FiscalReceiptKind.expense);
      expect(receipt.fingerprint, '9282440300999999:123456:987654321');
    });

    test('разбирает URL, сумму с запятой и чек возврата', () {
      final receipt = parser.parse(
        'https://example.test/check?t=20260809T143015&s=84%2C99&'
        'fn=9282440300999999&i=42&fp=77&n=2',
      );

      expect(receipt.purchasedAt, DateTime(2026, 8, 9, 14, 30, 15));
      expect(receipt.amountMinor, 8499);
      expect(receipt.kind, FiscalReceiptKind.refund);
    });

    test('отклоняет нефискальный QR', () {
      expect(
        () => parser.parse('https://qesto.ru'),
        throwsA(isA<FormatException>()),
      );
    });

    test('отклоняет неподдерживаемый тип расчёта', () {
      expect(
        () => parser.parse('t=20260809T1430&s=100&fn=1&i=2&fp=3&n=3'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ReceiptTransactionMatcher', () {
    final receipt = parser.parse(
      't=20260809T1430&s=1250.50&fn=9001&i=42&fp=77&n=1',
    );

    test('находит ближайшую операцию по дате, сумме и типу', () {
      final result = matcher.findMatches(
        receipt: receipt,
        transactions: [
          _transaction('later', DateTime(2026, 8, 10), 1251),
          _transaction('exact', DateTime(2026, 8, 9, 15), 1251),
          _transaction('wrong-amount', DateTime(2026, 8, 9), 1250),
          _transaction(
            'wrong-type',
            DateTime(2026, 8, 9),
            1251,
            type: TransactionType.income,
          ),
        ],
      );

      expect(result.map((item) => item.id), ['exact', 'later']);
    });

    test('не предлагает уже привязанный чек и определяет дубль', () {
      final imported = _transaction(
        'imported',
        DateTime(2026, 8, 9),
        1251,
        tags: [receipt.transactionTag],
      );

      expect(
        matcher.findMatches(receipt: receipt, transactions: [imported]),
        isEmpty,
      );
      expect(
        matcher.isImported(receipt: receipt, transactions: [imported]),
        isTrue,
      );
    });
  });
}

BudgetTransaction _transaction(
  String id,
  DateTime date,
  int amount, {
  TransactionType type = TransactionType.expense,
  List<String> tags = const [],
}) => BudgetTransaction(
  id: id,
  userId: 'user',
  accountId: 'account',
  date: date,
  amount: amount,
  currency: 'RUB',
  type: type,
  categoryId: 'groceries',
  merchant: id,
  tags: tags,
);
