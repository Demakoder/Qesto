import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/ai_export/data/ai_export_ids.dart';
import 'package:qesto/features/ai_export/data/ai_export_snapshot.dart';
import 'package:qesto/features/ai_export/domain/ai_export_models.dart';
import 'package:qesto/features/ai_export/domain/ai_export_v2.dart';
import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_extractors.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/statistics/domain/models/statistics_models.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/synoball/reconciliation/bank_web_identity_quality.dart';
import 'package:qesto/synoball/core/models.dart';
import 'ai_export_test.dart' as fixtures;

/// Opt-in local source replay. Private inputs/outputs MUST remain in .codex_tmp.
/// Never loads native repositories, saves live data or connects to a bank.
void main() {
  final directory = Platform.environment['QESTO_AI_REPLAY_DIR'];
  test(
    'replay supplied six groups through real controller, compare both exports',
    () async {
      final root = Directory(directory!).absolute;
      final allowed = Directory(
        '../../.codex_tmp',
      ).absolute.resolveSymbolicLinksSync();
      expect(
        root.resolveSymbolicLinksSync().startsWith(
          '$allowed${Platform.pathSeparator}',
        ),
        isTrue,
      );
      Map<String, dynamic> read(String name) =>
          jsonDecode(File('${root.path}/$name').readAsStringSync())
              as Map<String, dynamic>;
      final data = const UserFinancialDataCodec().decode(
        File('${root.path}/financial-snapshot.json').readAsStringSync(),
      );
      final pairs =
          jsonDecode(
                File(
                  '${root.path}/proven-pairs-private.json',
                ).readAsStringSync(),
              )
              as List;
      final rows = [
        for (final pair in pairs) Map<String, dynamic>.from(pair['row'] as Map),
      ];
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: data,
      );
      addTearDown(controller.dispose);
      final originalCount = controller.transactions.length;
      final entity = 'ent-${data.user.id}';
      final connection = data.synoballState!.ingestionRecords
          .firstWhere((r) => r.connectionId != null)
          .connectionId;
      expect(
        bankWebIdentityAmbiguities(controller.synoballState, entity),
        hasLength(6),
      );
      final facts = const SberExtractors().normalizeTransactionRows(
        rows,
        range: SberSyncRange(
          from: DateTime(2026, 8, 4),
          toExclusive: DateTime(2026, 9, 25),
          label: 'local replay',
        ),
      );
      final snapshot = SberSyncSnapshot(
        connectionId: connection,
        observedAt: DateTime(2026, 9, 24),
        accounts: const [],
        transactions: facts,
        oldestTransaction: DateTime(2026, 8, 17),
        newestTransaction: DateTime(2026, 8, 25),
        pendingCount: 0,
        pageType: SberPageType.transactions,
      );
      await controller.importSberSnapshot(snapshot);
      final once = controller.transactions.length;
      final repairedData = controller.mergeInto(data);
      for (final pair in pairs) {
        final old = controller.synoballState.transactions
            .where((t) => t.id == pair['legacyId'])
            .firstOrNull;
        final modern = controller.synoballState.transactions
            .where((t) => t.id == pair['modernId'])
            .firstOrNull;
        if (modern != null) {
          final fact = facts
              .where((f) => f.legacyTransactionIds.contains(old?.id))
              .firstOrNull;
          // ignore: avoid_print
          print({
            'legacy': old?.id,
            'modern': modern.id.substring(0, 27),
            'fact': fact != null,
            'sameDescription': fact?.description == old?.rawDescription,
            'sameDate': fact?.date == old?.occurredAt,
            'sameMoney': fact?.amountMinor == old?.amount.minorUnits,
            'oldTags': old?.tags,
            'status': old?.status.name,
            'override': old?.userCategoryOverride,
            'receipt': old?.receiptId != null,
          });
        }
      }
      await controller.importSberSnapshot(snapshot);
      expect(controller.transactions.length, once);
      expect(originalCount - once, 11);
      expect(
        bankWebIdentityAmbiguities(controller.synoballState, entity),
        hasLength(1),
      );
      for (final pair in pairs) {
        expect(
          controller.synoballState.transactions.any(
            (t) => t.id == pair['legacyId'],
          ),
          isTrue,
        );
        expect(
          controller.synoballState.transactions.any(
            (t) => t.id == pair['modernId'],
          ),
          isFalse,
        );
      }
      final exportSnapshot = captureAiExportSnapshot(
        controller,
        now: DateTime.utc(2026, 9, 24, 14, 8, 49),
      );
      final secrets = fixtures.MemoryExportSecrets();
      final key = Platform.environment['QESTO_AI_REPLAY_EXPORT_KEY'];
      if (key == null) {
        throw StateError('Export key must be supplied in memory');
      }
      secrets.values[AiExportIdStore.storageKey] = key;
      final ids = await AiExportIdStore(
        secureStore: secrets,
      ).forProfile(entity);
      final docs = <AiExportDetailLevel, Map<String, Object?>>{};
      final sizes = <String, int>{};
      for (final mode in AiExportDetailLevel.values) {
        final selection = AiExportSelection(
          exportSnapshot,
          AiExportSettings(
            period: StatisticsDateRange(
              DateTime(2026, 8, 4),
              DateTime(2026, 9, 24),
            ),
            detailLevel: mode,
            hideAccountNames: false,
            hideTransactionNames: false,
          ),
        );
        final doc = (await const AIExportV2Builder().build(
          selection,
          ids,
          generatedAt: DateTime.utc(2026, 9, 24, 15),
        )).toJson();
        docs[mode] = doc;
        final bytes = utf8.encode(
          const JsonEncoder.withIndent('  ').convert(doc),
        );
        sizes[mode.name] = bytes.length;
        File('${root.path}/${mode.name}.json').writeAsBytesSync(bytes);
      }
      final compact = docs[AiExportDetailLevel.compact]!,
          diagnostic = docs[AiExportDetailLevel.diagnostic]!;
      List rowsOf(Map<String, Object?> doc) => doc['transactions'] as List;
      expect(
        rowsOf(compact).map((t) => t['id']).toList(),
        rowsOf(diagnostic).map((t) => t['id']).toList(),
      );
      expect(
        rowsOf(compact).map((t) => t['amount']).toList(),
        rowsOf(diagnostic).map((t) => t['amount']).toList(),
      );
      final aliases = read('export-ids.json')['transactions'] as Map;
      final actual = rowsOf(compact).map((t) => t['id']).toSet();
      for (final id in controller.transactions.map((t) => t.id)) {
        expect(
          actual.contains(aliases[id]),
          isTrue,
          reason: 'Existing canonical pseudonym changed',
        );
      }
      final totals = <String, int>{};
      for (final t in rowsOf(compact)) {
        final key = '${t['direction']}:${t['amount']['currency']}';
        final amount = Money.fromJson(
          Map<String, dynamic>.from(t['amount'] as Map),
        );
        totals.update(
          key,
          (v) => v + amount.minorUnits,
          ifAbsent: () => amount.minorUnits,
        );
      }
      final report = {
        'before': originalCount,
        'after': once,
        'repairedPairs': 11,
        'remainingGroups': 1,
        'sizes': sizes,
        'totalsMinor': totals,
        'dataQuality': compact['dataQuality'],
        'unresolvedTransactions': rowsOf(
          compact,
        ).where((t) => t['accountResolution'] == 'unresolved').length,
      };
      File(
        '${root.path}/replay-report.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      File(
        '${root.path}/repaired-financial-snapshot.json',
      ).writeAsStringSync(const UserFinancialDataCodec().encode(repairedData));
      // Only aggregate diagnostics, never financial names or keys, reach test logs.
      // ignore: avoid_print
      print(jsonEncode(report));
    },
    skip: directory == null ? 'Private corpus not supplied' : false,
  );
}
