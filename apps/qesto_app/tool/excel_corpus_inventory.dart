// Opt-in local diagnostics. The JSON contains private financial data: use an
// ignored output path. Run via flutter test tool/excel_corpus_inventory.dart.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/statement_import/services/universal_excel_statement_adapter.dart';

void main() {
  test(
    'export local Excel source-coordinate inventory',
    () async {
      final directory = Directory(
        Platform.environment['QESTO_EXCEL_FIXTURE_DIR']!,
      );
      final output = Platform.environment['QESTO_EXCEL_AUDIT_OUTPUT']!;
      final files =
          directory
              .listSync()
              .whereType<File>()
              .where(
                (file) => RegExp(r'Копия (\d+)\.xls[xm]$').hasMatch(file.path),
              )
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      final reports = <Object>[];
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        final parsed = const UniversalExcelStatementAdapter().parse(
          bytes: await file.readAsBytes(),
          fileName: name,
          referenceDate: DateTime(2026, 8, 20),
        );
        reports.add({
          'file': name,
          'count': parsed.transactions.length,
          'transactions': [
            for (final t in parsed.transactions)
              {
                'authorizationCode': t.authorizationCode,
                'amountMinor': t.amountMinor,
                'date': t.operationDate.toIso8601String(),
                'kind': t.kind.name,
                'description': t.description,
                'bankCategory': t.bankCategory,
                'category': t.category.categoryId,
              },
          ],
        });
      }
      await File(
        output,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(reports));
      expect(reports.length, 23);
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip:
        Platform.environment['QESTO_EXCEL_FIXTURE_DIR'] == null ||
        Platform.environment['QESTO_EXCEL_AUDIT_OUTPUT'] == null,
  );
}
