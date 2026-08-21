import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/statement_import/services/universal_excel_statement_adapter.dart';

void main() {
  const minimumTransactions = <String, int>{
    'Копия 0.xlsx': 180,
    'Копия 1.xlsx': 100,
    'Копия 2.xlsx': 45,
    'Копия 3.xlsx': 170,
    'Копия 4.xlsx': 150,
    'Копия 5.xlsm': 1000,
    'Копия 6.xlsx': 250,
    'Копия 7.xlsx': 350,
    'Копия 8.xlsx': 390,
    'Копия 9.xlsx': 110,
    'Копия 10.xlsx': 70,
    'Копия 11.xlsx': 290,
    'Копия 12.xlsx': 300,
    'Копия 13.xlsx': 250,
    'Копия 14.xlsx': 60,
    'Копия 15.xlsx': 70,
    'Копия 16.xlsx': 250,
    'Копия 17.xlsx': 1400,
    'Копия 18.xlsx': 180,
    'Копия 19.xlsx': 30,
    'Копия 20.xlsx': 680,
    'Копия 21.xlsx': 1000,
    'Копия 22.xlsx': 550,
  };
  const expectedYears = <String, Set<int>>{
    'Копия 0.xlsx': {2026},
    'Копия 1.xlsx': {2025},
    'Копия 2.xlsx': {2026},
    'Копия 3.xlsx': {2025},
    'Копия 4.xlsx': {2025},
    'Копия 5.xlsm': {2025},
    'Копия 6.xlsx': {2026},
    'Копия 7.xlsx': {2025, 2026},
    'Копия 8.xlsx': {2026},
    'Копия 9.xlsx': {2025},
    'Копия 10.xlsx': {2025},
    'Копия 11.xlsx': {2025, 2026},
    'Копия 12.xlsx': {2024, 2025},
    'Копия 13.xlsx': {2018, 2019, 2026},
    'Копия 14.xlsx': {2026},
    'Копия 15.xlsx': {2025, 2026},
    'Копия 16.xlsx': {2024, 2025},
    'Копия 17.xlsx': {2024, 2025},
    'Копия 18.xlsx': {2026},
    'Копия 19.xlsx': {2024, 2025},
    'Копия 20.xlsx': {2025},
    'Копия 21.xlsx': {2023, 2024, 2025, 2026, 2027},
    'Копия 22.xlsx': {2026},
  };
  const expectedKinds = <String, Set<String>>{
    'Копия 1.xlsx': {'expense', 'income'},
    'Копия 2.xlsx': {'expense', 'income'},
    'Копия 3.xlsx': {'expense', 'income', 'investment', 'savings'},
    'Копия 4.xlsx': {'expense', 'income', 'investment', 'savings'},
    'Копия 5.xlsm': {'expense', 'income'},
    'Копия 7.xlsx': {'expense', 'investment', 'savings'},
    'Копия 15.xlsx': {'expense', 'income', 'investment'},
    'Копия 17.xlsx': {'expense', 'income', 'investment', 'savings'},
    'Копия 21.xlsx': {'expense', 'income', 'savings'},
    'Копия 22.xlsx': {'expense', 'income', 'investment', 'savings'},
  };

  test(
    'Excel corpus preserves meaningful operations across supplied workbooks',
    () {
      final root = Platform.environment['QESTO_EXCEL_FIXTURE_DIR'];
      final output = Platform.environment['QESTO_EXCEL_AUDIT_OUTPUT'];
      final filter = Platform.environment['QESTO_EXCEL_CORPUS_FILTER'];
      final filterNames = filter
          ?.split(',')
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toSet();
      final files =
          Directory(root!).listSync().whereType<File>().where((file) {
            final name = file.uri.pathSegments.last;
            return RegExp(
                  r'^Копия \d+\.(xlsx|xlsm)$',
                  caseSensitive: false,
                ).hasMatch(name) &&
                (filterNames == null || filterNames.contains(name));
          }).toList()..sort((left, right) {
            int number(File file) => int.parse(
              RegExp(r'\d+').firstMatch(file.uri.pathSegments.last)!.group(0)!,
            );
            return number(left).compareTo(number(right));
          });

      expect(files, hasLength(filterNames?.length ?? 23));
      const adapter = UniversalExcelStatementAdapter();
      final reports = <Map<String, Object?>>[];
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        final statement = adapter.parse(
          bytes: file.readAsBytesSync(),
          fileName: name,
          referenceDate: DateTime(2026, 8, 20),
        );
        expect(
          statement.transactions.length,
          greaterThanOrEqualTo(minimumTransactions[name]!),
          reason: '$name потерял часть заполненных денежных строк',
        );
        expect(
          statement.transactions.map((item) => item.operationDate.year).toSet(),
          expectedYears[name],
          reason:
              '$name получил неверный год из шаблонных дат или соседних листов',
        );
        final actualKinds = statement.transactions
            .map((item) => item.kind.name)
            .toSet();
        expect(
          actualKinds,
          containsAll(expectedKinds[name] ?? const <String>{}),
          reason:
              '$name потерял финансовый смысл доходов, расходов или капитала',
        );
        for (final item in statement.transactions) {
          expect(item.amountMinor, isNot(0), reason: name);
          expect(
            item.description,
            isNot(
              matches(
                RegExp(
                  r'^(№|п/п|Доля, %|Предполагаемые|Фактические|Разница|-)($| ·)',
                ),
              ),
            ),
            reason: '$name превратил техническую колонку в транзакцию',
          );
        }
        final kinds = <String, Map<String, int>>{};
        final years = <String, int>{};
        final months = <String, int>{};
        final categories = <String, int>{};
        for (final item in statement.transactions) {
          final bucket = kinds.putIfAbsent(
            item.kind.name,
            () => <String, int>{'count': 0, 'amountMinor': 0},
          );
          bucket['count'] = bucket['count']! + 1;
          bucket['amountMinor'] =
              bucket['amountMinor']! + item.amountMinor.abs();
          final year = '${item.operationDate.year}';
          years[year] = (years[year] ?? 0) + 1;
          final month =
              '${item.operationDate.year}-${item.operationDate.month.toString().padLeft(2, '0')}';
          months[month] = (months[month] ?? 0) + 1;
          final category = item.category.categoryId;
          categories[category] = (categories[category] ?? 0) + 1;
        }
        reports.add({
          'file': name,
          'count': statement.transactions.length,
          'periodStart': statement.periodStart.toIso8601String(),
          'periodEnd': statement.periodEnd.toIso8601String(),
          'kinds': kinds,
          'years': years,
          'months': months,
          'categories': categories,
          'transactions': [
            for (final item in statement.transactions)
              {
                'date': item.operationDate.toIso8601String(),
                'amountMinor': item.amountMinor,
                'kind': item.kind.name,
                'capitalKind': item.capitalKind?.name,
                'description': item.description,
                'bankCategory': item.bankCategory,
                'category': item.category.categoryId,
                'authorizationCode': item.authorizationCode,
              },
          ],
        });
        expect(statement.transactions, isNotEmpty, reason: name);
      }
      if (output != null) {
        File(output).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(reports),
        );
      }
    },
    skip: Platform.environment['QESTO_EXCEL_FIXTURE_DIR'] == null
        ? 'real workbook verification is opt-in'
        : false,
  );
}
