import 'dart:typed_data';
import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/statement_import/services/universal_excel_statement_adapter.dart';

void main() {
  void cell(Sheet sheet, int row, int column, CellValue value) =>
      sheet.updateCell(
        CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
        value,
      );

  test('calendar imports day cells, skips totals, and respects each month', () {
    final book = Excel.createExcel();
    final sheet = book['Расходы 2026'];
    for (final (offset, month) in [(0, 'январь'), (6, 'февраль')]) {
      cell(sheet, offset, 0, TextCellValue(month));
      for (var day = 1; day <= 31; day++) {
        cell(sheet, offset + 1, day, IntCellValue(day));
      }
      cell(sheet, offset + 2, 0, TextCellValue('Продукты'));
      cell(sheet, offset + 2, 1, IntCellValue(100));
      cell(sheet, offset + 2, 2, FormulaCellValue('120+30'));
      cell(sheet, offset + 2, 31, IntCellValue(200));
      cell(sheet, offset + 2, 32, IntCellValue(450));
      cell(sheet, offset + 3, 0, TextCellValue('Итого в день'));
      cell(sheet, offset + 3, 1, IntCellValue(100));
    }
    final parsed = const UniversalExcelStatementAdapter().parse(
      bytes: Uint8List.fromList(book.encode()!),
      fileName: 'calendar.xlsx',
      referenceDate: DateTime(2026, 9, 10),
    );
    expect(parsed.transactions.length, 5);
    expect(parsed.outflowsMinor, 70000);
    expect(
      parsed.transactions.where((t) => t.operationDate.month == 2).length,
      2,
    );
    expect(
      parsed.transactions.every((t) => !t.description.contains('агрегировано')),
      isTrue,
    );
  });

  test(
    'dashboard and annual totals cannot duplicate detailed transactions',
    () {
      final book = Excel.createExcel();
      for (final name in [
        'Операции',
        'Дашборт',
        'Итоги года 2026',
        'total',
        'План-факт',
      ]) {
        final sheet = book[name];
        cell(sheet, 0, 0, TextCellValue('Дата'));
        cell(sheet, 0, 1, TextCellValue('Описание'));
        cell(sheet, 0, 2, TextCellValue('Расход'));
        cell(sheet, 1, 0, DateCellValue(year: 2026, month: 9, day: 1));
        cell(sheet, 1, 1, TextCellValue('Продукты'));
        cell(sheet, 1, 2, IntCellValue(100));
      }
      final parsed = const UniversalExcelStatementAdapter().parse(
        bytes: Uint8List.fromList(book.encode()!),
        fileName: 'book.xlsx',
      );
      expect(parsed.transactions.length, 1);
      expect(parsed.outflowsMinor, 10000);
    },
  );

  test('large monthly amounts are money, not new Excel-date headers', () {
    final book = Excel.createExcel();
    final sheet = book['Расходы 2026'];
    cell(sheet, 0, 0, TextCellValue('Категория'));
    cell(sheet, 0, 1, TextCellValue('Январь'));
    cell(sheet, 0, 2, TextCellValue('Февраль'));
    cell(sheet, 1, 0, TextCellValue('Жилье'));
    cell(sheet, 1, 1, IntCellValue(45000));
    cell(sheet, 1, 2, IntCellValue(46000));
    cell(sheet, 2, 0, TextCellValue('Интернет'));
    cell(sheet, 2, 1, IntCellValue(500));
    cell(sheet, 2, 2, IntCellValue(600));
    final parsed = const UniversalExcelStatementAdapter().parse(
      bytes: Uint8List.fromList(book.encode()!),
      fileName: 'book.xlsx',
    );
    expect(parsed.transactions.length, 4);
    expect(parsed.outflowsMinor, 9210000);
  });

  test('monthly capital snapshots are not treated as monthly income', () {
    final book = Excel.createExcel();
    final sheet = book['Доходы 2026'];
    cell(sheet, 0, 0, TextCellValue('Категория'));
    cell(sheet, 0, 1, TextCellValue('Январь'));
    cell(sheet, 0, 2, TextCellValue('Февраль'));
    cell(sheet, 1, 0, TextCellValue('Зарплата'));
    cell(sheet, 1, 1, IntCellValue(100));
    cell(sheet, 1, 2, IntCellValue(200));
    cell(sheet, 4, 0, TextCellValue('Капитал'));
    cell(sheet, 6, 0, TextCellValue('Категория'));
    cell(sheet, 6, 1, TextCellValue('Январь'));
    cell(sheet, 6, 2, TextCellValue('Февраль'));
    cell(sheet, 7, 0, TextCellValue('Брокерский счёт'));
    cell(sheet, 7, 1, IntCellValue(10000));
    cell(sheet, 7, 2, IntCellValue(12000));
    cell(sheet, 8, 0, TextCellValue('Дивиденды'));
    cell(sheet, 8, 1, IntCellValue(10));
    cell(sheet, 8, 2, IntCellValue(20));
    final parsed = const UniversalExcelStatementAdapter().parse(
      bytes: Uint8List.fromList(book.encode()!),
      fileName: 'book.xlsx',
    );
    expect(parsed.transactions.length, 4);
    expect(parsed.inflowsMinor, 33000);
  });
}
