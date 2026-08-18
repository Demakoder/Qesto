import 'dart:io';
import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/statement_import/domain/bank_statement_models.dart';
import 'package:qesto/features/statement_import/services/universal_excel_statement_adapter.dart';
import 'package:qesto/features/statistics/domain/models/statistics_models.dart';
import 'package:qesto/features/statistics/domain/services/statistics_calculation_service.dart';

void main() {
  test('Excel adapter rejects an archive expansion bomb before decoding', () {
    final bytes = Uint8List(68);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, 0x02014b50, Endian.little);
    data.setUint32(24, 101 * 1024 * 1024, Endian.little);
    data.setUint32(46, 0x06054b50, Endian.little);
    data.setUint16(56, 1, Endian.little);
    data.setUint32(58, 46, Endian.little);
    data.setUint32(62, 0, Endian.little);

    expect(
      () => const UniversalExcelStatementAdapter().parse(
        bytes: bytes,
        fileName: 'bomb.xlsx',
      ),
      throwsA(
        isA<UnsupportedBankStatementException>().having(
          (error) => error.message,
          'message',
          contains('100 МБ'),
        ),
      ),
    );
  });

  test('universal Excel adapter normalizes ordinary income and expenses', () {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.updateCell(CellIndex.indexByString('A1'), TextCellValue('Дата'));
    sheet.updateCell(CellIndex.indexByString('B1'), TextCellValue('Описание'));
    sheet.updateCell(CellIndex.indexByString('C1'), TextCellValue('Расход'));
    sheet.updateCell(CellIndex.indexByString('D1'), TextCellValue('Доход'));
    sheet.updateCell(
      CellIndex.indexByString('A2'),
      DateCellValue(year: 2026, month: 8, day: 10),
    );
    sheet.updateCell(
      CellIndex.indexByString('B2'),
      TextCellValue('Супермаркет'),
    );
    sheet.updateCell(CellIndex.indexByString('C2'), DoubleCellValue(1250.50));
    sheet.updateCell(
      CellIndex.indexByString('A3'),
      DateCellValue(year: 2026, month: 8, day: 11),
    );
    sheet.updateCell(CellIndex.indexByString('B3'), TextCellValue('Зарплата'));
    sheet.updateCell(CellIndex.indexByString('D3'), DoubleCellValue(90000));
    sheet.updateCell(
      CellIndex.indexByString('A4'),
      DateCellValue(year: 2026, month: 8, day: 12),
    );
    sheet.updateCell(CellIndex.indexByString('B4'), TextCellValue('Аптека'));
    sheet.updateCell(
      CellIndex.indexByString('C4'),
      const FormulaCellValue('=1000+250'),
    );

    final bytes = Uint8List.fromList(workbook.save()!);
    final statement = const UniversalExcelStatementAdapter().parse(
      bytes: bytes,
      fileName: 'обычная таблица.xlsx',
      referenceDate: DateTime(2026, 8, 13),
    );

    expect(statement.transactions, hasLength(3));
    expect(statement.transactions[0].amountMinor, -125050);
    expect(statement.transactions[0].isIncoming, isFalse);
    expect(statement.transactions[1].amountMinor, 9000000);
    expect(statement.transactions[1].isIncoming, isTrue);
    expect(statement.transactions[2].amountMinor, -125000);
    expect(
      statement.transactions.every((item) => item.currency == 'RUB'),
      isTrue,
    );
  });

  test(
    'monthly matrix preserves hierarchy, separates capital and infers year',
    () {
      final workbook = Excel.createExcel();
      final sheet = workbook['Расходы'];
      for (var month = 1; month <= 12; month++) {
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: month + 2, rowIndex: 1),
          DateCellValue(year: 2000, month: month, day: 1),
        );
      }
      sheet.updateCell(
        CellIndex.indexByString('A3'),
        TextCellValue('Транспорт'),
      );
      sheet.updateCell(
        CellIndex.indexByString('C3'),
        TextCellValue('Итого за месяц:'),
      );
      sheet.updateCell(
        CellIndex.indexByString('C4'),
        TextCellValue('Общественный транспорт'),
      );
      sheet.updateCell(
        CellIndex.indexByString('A6'),
        TextCellValue('Инвестиции'),
      );
      sheet.updateCell(
        CellIndex.indexByString('C6'),
        TextCellValue('Итого за месяц:'),
      );
      sheet.updateCell(CellIndex.indexByString('C7'), TextCellValue('Крипта'));
      for (var month = 1; month <= 12; month++) {
        final column = month + 2;
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 2),
          DoubleCellValue(100),
        );
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 3),
          DoubleCellValue(100),
        );
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 5),
          DoubleCellValue(1000),
        );
        sheet.updateCell(
          CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 6),
          DoubleCellValue(1000),
        );
      }

      final bytes = Uint8List.fromList(workbook.save()!);
      const adapter = UniversalExcelStatementAdapter();
      final inferred = adapter.parse(
        bytes: bytes,
        fileName: 'агрегаты.xlsx',
        referenceDate: DateTime(2026, 8, 13),
      );

      expect(inferred.transactions, hasLength(24));
      expect(
        inferred.transactions.every((item) => item.operationDate.year == 2025),
        isTrue,
      );
      final publicTransport = inferred.transactions.where(
        (item) => item.description.startsWith('Общественный транспорт'),
      );
      expect(publicTransport, hasLength(12));
      expect(
        publicTransport.every(
          (item) => item.category.categoryId == 'transport',
        ),
        isTrue,
      );
      final crypto = inferred.transactions.where(
        (item) => item.description.startsWith('Крипта'),
      );
      expect(crypto, hasLength(12));
      expect(
        crypto.every(
          (item) =>
              item.kind == StatementTransactionKind.investment &&
              item.capitalKind == StatementCapitalKind.investment,
        ),
        isTrue,
      );
      expect(
        inferred.transactions.any((item) => item.description.contains('Итого')),
        isFalse,
      );

      final overridden = adapter.parse(
        bytes: bytes,
        fileName: 'агрегаты.xlsx',
        referenceDate: DateTime(2026, 8, 13),
        yearOverride: 2024,
      );
      expect(
        overridden.transactions.every(
          (item) => item.operationDate.year == 2024,
        ),
        isTrue,
      );
    },
  );

  test(
    'Copy 4 keeps its financial meaning',
    () {
      final root = Platform.environment['QESTO_EXCEL_FIXTURE_DIR'];
      final file = File('$root${Platform.pathSeparator}Копия 4.xlsx');
      final statement = const UniversalExcelStatementAdapter().parse(
        bytes: file.readAsBytesSync(),
        fileName: 'Копия 4.xlsx',
        referenceDate: DateTime(2026, 8, 13),
      );
      expect(statement.periodStart.year, 2025);
      expect(statement.periodEnd.year, 2025);
      expect(
        statement.transactions.any(
          (item) => item.description.contains('Итого'),
        ),
        isFalse,
      );
      final capital = statement.transactions.where(
        (item) =>
            item.kind == StatementTransactionKind.investment ||
            item.kind == StatementTransactionKind.savings,
      );
      expect(
        capital.fold<int>(0, (sum, item) => sum + item.amountMinor.abs()),
        32160300,
      );
      expect(
        statement.transactions
            .where((item) => item.kind == StatementTransactionKind.expense)
            .fold<int>(0, (sum, item) => sum + item.amountMinor.abs()),
        78363700,
      );
      expect(
        statement.transactions
            .where((item) => item.kind == StatementTransactionKind.income)
            .fold<int>(0, (sum, item) => sum + item.amountMinor.abs()),
        108356775,
      );
      final publicTransport = statement.transactions.where(
        (item) => item.description.startsWith('Общественный транспорт'),
      );
      expect(publicTransport, isNotEmpty);
      expect(
        publicTransport.every(
          (item) => item.category.categoryId == 'transport',
        ),
        isTrue,
      );
      final statisticsTransactions = statement.transactions
          .map(
            (item) => BudgetTransaction(
              id: item.id,
              userId: 'user-1',
              accountId: 'excel-account',
              date: item.operationDate,
              amount: item.roundedRubles,
              currency: item.currency,
              type: switch (item.kind) {
                StatementTransactionKind.expense => TransactionType.expense,
                StatementTransactionKind.income => TransactionType.income,
                StatementTransactionKind.transfer => TransactionType.transfer,
                StatementTransactionKind.refund => TransactionType.refund,
                StatementTransactionKind.savings =>
                  TransactionType.savingsTransfer,
                StatementTransactionKind.investment =>
                  TransactionType.investment,
              },
              categoryId: item.category.categoryId,
            ),
          )
          .toList();
      const statistics = StatisticsCalculationService();
      final visible = statistics.filterTransactions(
        transactions: statisticsTransactions,
        query: StatisticsQuery(
          period: StatisticsDateRange(DateTime(2025), DateTime(2025, 12, 31)),
        ),
        range: StatisticsDateRange(DateTime(2025), DateTime(2025, 12, 31)),
        accounts: const [
          QestoAccount(
            id: 'excel-account',
            userId: 'user-1',
            title: 'Импорт из Excel',
            balance: 0,
            currency: 'RUB',
            type: AccountType.other,
          ),
        ],
      );
      expect(visible, hasLength(statement.transactions.length));
      expect(statistics.expenses(visible), 783637);
    },
    skip: Platform.environment['QESTO_EXCEL_FIXTURE_DIR'] == null
        ? 'real workbook verification is opt-in'
        : false,
  );

  test(
    'universal Excel adapter reads every supplied workbook variant',
    () {
      final root = Platform.environment['QESTO_EXCEL_FIXTURE_DIR'];
      expect(root, isNotNull);
      final files = Directory(root!).listSync().whereType<File>().where((file) {
        final name = file.uri.pathSegments.last.toLowerCase();
        return RegExp(
          r'^копия (?:[0-9]|1[0-9]|2[0-2])\.(xlsx|xlsm)$',
        ).hasMatch(name);
      }).toList()..sort((a, b) => a.path.compareTo(b.path));
      expect(files, hasLength(23));

      const adapter = UniversalExcelStatementAdapter();
      final counts = <String, int>{};
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        final statement = adapter.parse(
          bytes: file.readAsBytesSync(),
          fileName: name,
          referenceDate: DateTime(2026, 8, 13),
        );
        counts[name] = statement.transactions.length;
        expect(statement.transactions, isNotEmpty, reason: name);
        expect(
          statement.transactions.every((item) => item.amountMinor != 0),
          isTrue,
          reason: name,
        );
        if (name.toLowerCase() == 'копия 4.xlsx') {
          expect(statement.periodStart.year, 2025);
          expect(statement.periodEnd.year, 2025);
          expect(
            statement.transactions.any(
              (item) => item.description.contains('Итого'),
            ),
            isFalse,
          );
          final capital = statement.transactions.where(
            (item) =>
                item.kind == StatementTransactionKind.investment ||
                item.kind == StatementTransactionKind.savings,
          );
          expect(
            capital.fold<int>(0, (sum, item) => sum + item.amountMinor.abs()),
            32160300,
          );
          expect(
            statement.transactions
                .where((item) => item.kind == StatementTransactionKind.expense)
                .fold<int>(0, (sum, item) => sum + item.amountMinor.abs()),
            78363700,
          );
          final publicTransport = statement.transactions.where(
            (item) => item.description.startsWith('Общественный транспорт'),
          );
          expect(publicTransport, isNotEmpty);
          expect(
            publicTransport.every(
              (item) => item.category.categoryId == 'transport',
            ),
            isTrue,
          );
        }
      }
      // ignore: avoid_print
      print('Excel adapter fixture counts: $counts');
    },
    skip: Platform.environment['QESTO_EXCEL_FIXTURE_DIR'] == null
        ? 'real workbook verification is opt-in'
        : false,
  );
}
