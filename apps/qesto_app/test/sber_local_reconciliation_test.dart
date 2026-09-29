import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_extractors.dart';
import 'package:qesto/features/budget/services/cash_flow_calculation_service.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/statement_import/services/sberbank_statement_parser.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

/// Opt-in local diagnostic. Inputs and row-level output must remain in an
/// ignored directory; no private bank fixture is embedded in this test.
void main() {
  final directory = Platform.environment['QESTO_SBER_RECONCILIATION_DIR'];
  test(
    'local PDF/web row manifest and exact sums',
    () async {
      final root = Directory(directory!);
      // Resolve symlinks too: an opt-in must not accidentally publish private
      // observations into a tracked fixture directory.
      final ignoredRoot = Directory(
        '../../.codex_tmp',
      ).resolveSymbolicLinksSync();
      final resolved = root.resolveSymbolicLinksSync();
      expect(
        resolved.toLowerCase().startsWith(
          '${ignoredRoot.toLowerCase()}${Platform.pathSeparator}',
        ),
        isTrue,
        reason:
            'Private output must stay below the ignored .codex_tmp directory',
      );
      final manifest = <String, dynamic>{};
      final source = File('${root.path}/pdf-layout.txt').readAsStringSync();
      final pdf = const SberbankStatementParser().parse(source);
      final range = SberSyncRange(
        from: pdf.periodStart,
        toExclusive: pdf.periodEnd.add(const Duration(days: 1)),
        label: 'Local PDF period',
      );
      final pdfRows = pdf.transactions;
      final pdfIncome = pdfRows
          .where((r) => r.isIncoming)
          .fold<int>(0, (n, r) => n + r.amountMinor.abs());
      final pdfExpense = pdfRows
          .where((r) => !r.isIncoming)
          .fold<int>(0, (n, r) => n + r.amountMinor.abs());
      // Independently read the bank's printed controls, not the app parser's
      // computed output. Fail instead of silently accepting a different layout.
      final plain = File('${root.path}/pdf-plain.txt').readAsStringSync();
      final header = plain
          .split('ИТОГО ПО ОПЕРАЦИЯМ ЗА ПЕРИОД:')
          .last
          .split('Расшифровка операций')
          .first;
      final balances = RegExp(
        r'Остаток на \d{2}\.\d{2}\.\d{4}\s+([\d\s]+,\d{2})',
      ).allMatches(header).toList();
      expect(balances, hasLength(2));
      final openingMinor = _printedMinor(balances.first.group(1)!);
      final closingMinor = _printedMinor(balances.last.group(1)!);
      final printedIncome = _printedMinor(
        RegExp(r'Пополнение\s+([\d\s]+,\d{2})').firstMatch(header)!.group(1)!,
      );
      final printedExpense = _printedMinor(
        RegExp(r'Списание\s+([\d\s]+,\d{2})').firstMatch(header)!.group(1)!,
      );
      final printedRowCount = RegExp(
        r'^\d{2}\.\d{2}\.\d{4}\s+\d{2}:\d{2}\s',
        multiLine: true,
      ).allMatches(plain).length;
      expect(pdfRows.length, printedRowCount);
      expect(pdfIncome, printedIncome);
      expect(pdfExpense, printedExpense);
      expect(openingMinor + pdfIncome - pdfExpense, closingMinor);
      // The application's own document-level control now has to agree with
      // the independently parsed bank header too.
      final plainParsed = const SberbankStatementParser().parse(plain);
      expect(plainParsed.controlTotalsVerified, isTrue);
      expect(plainParsed.closingBalanceMinor, closingMinor);
      manifest['pdf'] = {
        'from': range.from.toIso8601String(),
        'toExclusive': range.toExclusive.toIso8601String(),
        'count': pdfRows.length,
        'incomeMinor': pdfIncome,
        'expenseMinor': pdfExpense,
        'netMinor': pdfIncome - pdfExpense,
        'openingMinor': openingMinor,
        'closingMinor': closingMinor,
        'rows': [
          for (final r in pdfRows)
            {
              'id': r.id,
              'date': r.operationDate.toIso8601String(),
              'processingDate': r.processingDate.toIso8601String(),
              'amountMinor': r.amountMinor.abs(),
              'incoming': r.isIncoming,
              'balanceMinor': r.balanceMinor,
              'merchant': r.merchant,
              'category': r.bankCategory,
              'kind': r.kind.name,
            },
        ],
      };
      final raw =
          (jsonDecode(File('${root.path}/web-rows.json').readAsStringSync())
                  as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
      const extractor = SberExtractors();
      final normalized = extractor.normalizeTransactionRows(raw, range: range);
      final decisions = extractor.diagnoseTransactionRows(raw, range: range);
      final perRow = [
        for (var i = 0; i < raw.length; i++)
          {
            'index': i,
            'source': raw[i],
            'outcome': decisions[i].outcome.name,
            'accepted': extractor.normalizeTransactionRows([
              raw[i],
            ], range: range).isNotEmpty,
          },
      ];
      final webIncome = normalized
          .where((r) => r.isIncome)
          .fold<int>(0, (n, r) => n + r.amountMinor.abs());
      final webExpense = normalized
          .where((r) => !r.isIncome)
          .fold<int>(0, (n, r) => n + r.amountMinor.abs());
      manifest['web'] = {
        'rawRows': raw.length,
        'count': normalized.length,
        'acceptedBeforeFingerprintDedup': perRow
            .where((r) => r['accepted'] == true)
            .length,
        'incomeMinor': webIncome,
        'expenseMinor': webExpense,
        'netMinor': webIncome - webExpense,
        'rows': [
          for (final r in normalized)
            {
              'sourceId': r.sourceId,
              'fingerprint': r.fingerprint,
              'date': r.date.toIso8601String(),
              'amountMinor': r.amountMinor.abs(),
              'incoming': r.isIncome,
              'merchant': r.merchant,
              'operationType': r.operationType,
              'status': r.status,
              'internal': r.isInternalTransfer,
            },
        ],
        'observations': perRow,
      };

      // Dry-run the actual adapter -> Synoball -> read model -> Cash Flow path.
      // No repository or save callback is attached; live user data is untouched.
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'offline-audit',
            name: 'Offline',
            defaultCurrency: 'RUB',
          ),
          referenceDate: pdf.periodEnd,
        ),
      );
      addTearDown(controller.dispose);
      final snapshot = SberSyncSnapshot(
        observedAt: pdf.periodEnd,
        accounts: const [],
        transactions: normalized,
        oldestTransaction: normalized.lastOrNull?.date,
        newestTransaction: normalized.firstOrNull?.date,
        pendingCount: normalized.where((r) => r.status == 'PENDING').length,
        pageType: SberPageType.transactions,
      );
      final imported = await controller.importSberSnapshot(snapshot);
      final flow = const CashFlowCalculationService().calculate(
        transactions: controller.transactions,
        from: range.from,
        toExclusive: range.toExclusive,
        currency: 'RUB',
      );
      final contributing = normalized.where(
        (r) =>
            !r.isInternalTransfer &&
            r.status != 'PENDING' &&
            r.status != 'CANCELLED',
      );
      expect(
        imported.unresolvedCount,
        0,
        reason: 'This fixture has distinct provider observations',
      );
      expect(
        flow.externalInflowsMinor,
        contributing
            .where((r) => r.isIncome)
            .fold<int>(0, (n, r) => n + r.amountMinor),
      );
      expect(
        flow.externalOutflowsMinor,
        contributing
            .where((r) => !r.isIncome)
            .fold<int>(0, (n, r) => n + r.amountMinor),
      );
      manifest['dryRun'] = {
        'found': imported.found,
        'new': imported.newCount,
        'review': imported.unresolvedCount,
        'stored': controller.transactions.length,
        'incomeMinor': flow.externalInflowsMinor,
        'expenseMinor': flow.externalOutflowsMinor,
        'netMinor': flow.netCashFlowMinor,
        'internalTransfersExcludedRubles': flow.internalTransfersExcluded,
        'ignored': flow.ignoredTransactions,
      };
      final replay = await controller.importSberSnapshot(snapshot);
      manifest['dryRun']['replayNew'] = replay.newCount;
      expect(
        replay.newCount,
        0,
        reason: 'Identical source replay must not add monetary effects',
      );
      File(
        '${root.path}/manifest.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));
      // Aggregate console output only. Full provenance stays local.
      debugPrint(
        jsonEncode({
          for (final entry in manifest.entries)
            entry.key: Map<String, dynamic>.from(entry.value as Map)
              ..remove('rows')
              ..remove('observations'),
        }),
      );
      expect(pdfRows, isNotEmpty);
      expect(raw, isNotEmpty);
      expect(imported.found, normalized.length);
      expect(imported.newCount + imported.unresolvedCount, normalized.length);
    },
    skip: directory == null
        ? 'Requires explicit ignored local reconciliation inputs'
        : false,
  );
}

int _printedMinor(String value) {
  final parts = value.replaceAll(RegExp(r'\s'), '').split(',');
  return int.parse(parts[0]) * 100 + int.parse(parts[1]);
}
