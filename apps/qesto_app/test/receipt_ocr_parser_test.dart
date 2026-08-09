import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/receipt_import/data/receipt_scanner_models.dart';
import 'package:qesto/features/receipt_import/services/receipt_ocr_parser.dart';

void main() {
  const parser = ReceiptOcrParser();

  test('распознаёт магазин и позиции из многострочного чека', () {
    final result = parser.parse(
      _document([
        'ООО "АГРОТОРГ"',
        'КАССОВЫЙ ЧЕК',
        '1. МОЛОКО 3,2%',
        '1 X 89,99',
        '89,99',
        '2. ХЛЕБ БОРОДИНСКИЙ 54,90',
        'ИТОГ 144,89',
        'ФН 9282440300999999',
      ]),
      expectedTotalMinor: 14489,
    );

    expect(result.merchant, 'АГРОТОРГ');
    expect(result.items, hasLength(2));
    expect(result.items[0].name, 'МОЛОКО 3,2%');
    expect(result.items[0].quantity, 1);
    expect(result.items[0].unitPriceMinor, 8999);
    expect(result.items[0].totalMinor, 8999);
    expect(result.items[1].name, 'ХЛЕБ БОРОДИНСКИЙ');
    expect(result.items[1].totalMinor, 5490);
  });

  test('понимает количество, цену и итог в одной строке', () {
    final result = parser.parse(
      _document([
        'МАГАЗИН ФРУКТЫ',
        'КАССОВЫЙ ЧЕК',
        'ЯБЛОКИ 0,750 X 129,90 97,43',
        'ИТОГО 97,43',
      ]),
      expectedTotalMinor: 9743,
    );

    expect(result.items, hasLength(1));
    expect(result.items.single.name, 'ЯБЛОКИ');
    expect(result.items.single.quantity, 0.75);
    expect(result.items.single.unitPriceMinor, 12990);
    expect(result.items.single.totalMinor, 9743);
  });

  test('не принимает итоги, оплату и фискальные строки за товары', () {
    final result = parser.parse(
      _document([
        'ООО РОМАШКА',
        'КАССОВЫЙ ЧЕК',
        'СОК ЯБЛОЧНЫЙ 120,00',
        'ИТОГ 120,00',
        'БЕЗНАЛИЧНЫМИ 120,00',
        'НДС 20% 20,00',
        'ФД 12345',
      ]),
      expectedTotalMinor: 12000,
    );

    expect(result.items, hasLength(1));
    expect(result.items.single.name, 'СОК ЯБЛОЧНЫЙ');
  });

  test('разбирает типичный русский вывод Tesseract', () {
    final result = parser.parse(
      _document([
        'ООО РОМАШКА',
        'КАССОВЫЙ ЧЕК',
        'НАИМЕНОВАНИЕ КОЛ-ВО ЦЕНА СТОИМОСТЬ',
        'МОЛОКО 3,2% ........ 89:99 А',
        'ХЛЕБ БОРОДИНСКИЙ',
        '1,000 х 54,90',
        '=54,90 Б',
        'ИТОГ: 144,89',
      ]),
      expectedTotalMinor: 14489,
    );

    expect(result.items, hasLength(2));
    expect(result.items[0].name, 'МОЛОКО 3,2%');
    expect(result.items[0].totalMinor, 8999);
    expect(result.items[1].name, 'ХЛЕБ БОРОДИНСКИЙ');
    expect(result.items[1].totalMinor, 5490);
  });
}

ExtractedReceiptDocument _document(List<String> values) {
  return ExtractedReceiptDocument(
    text: values.join('\n'),
    lines: [for (final value in values) ReceiptTextLine(text: value)],
  );
}
