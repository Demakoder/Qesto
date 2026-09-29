import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/ai_export/data/ai_export_ids.dart';
import 'package:qesto/features/ai_export/data/ai_export_snapshot.dart';
import 'package:qesto/features/ai_export/domain/ai_export_models.dart';
import 'package:qesto/features/ai_export/domain/ai_export_v2.dart';
import 'package:qesto/features/statistics/domain/models/statistics_models.dart';
import 'package:qesto/synoball/core/models.dart';
import 'ai_export_test.dart' as f;
import 'ai_export_v2_test.dart' as v2;

void main() {
  for (final hidden in [true, false]) {
    test(
      'both detail levels preserve IDs, money, exceptions and privacy $hidden',
      () async {
        final rows = [
          f.exportFixtureTransaction('ordinary', tags: ['qesto-auto-category']),
          f.exportFixtureTransaction(
            'edited',
            tags: ['user-field:category', 'qesto-manual-category'],
          ),
          f.exportFixtureTransaction(
            'refund',
            tags: ['refund', 'legacy-type-refund'],
            direction: FinancialDirection.inflow,
          ),
          f.exportFixtureTransaction(
            'transfer',
            tags: ['qesto-internal-transfer', 'legacy-type-transfer'],
            transferDirection: 'outgoing',
          ),
          f.exportFixtureTransaction(
            'unknown',
            account: v2.virtual.id,
            tags: ['time-precision:approximate'],
          ),
        ];
        final c = v2.controller(
          rows,
          accounts: [v2.bank, v2.virtual],
          sources: [
            for (final row in rows)
              v2.evidence('e-${row.id}', row.id, SynoballSourceType.bankWeb),
          ],
        );
        addTearDown(c.dispose);
        final snapshot = captureAiExportSnapshot(c, now: v2.now);
        final before = jsonEncode(c.synoballState.toJson());
        final ids = await AiExportIdStore(
          secureStore: f.MemoryExportSecrets(),
        ).forProfile(snapshot.profileScope);
        final docs = <AiExportDetailLevel, Map<String, Object?>>{};
        for (final level in AiExportDetailLevel.values) {
          docs[level] = (await const AIExportV2Builder().build(
            AiExportSelection(
              snapshot,
              AiExportSettings(
                period: StatisticsDateRange(
                  DateTime(2026, 9),
                  DateTime(2026, 9, 24),
                ),
                detailLevel: level,
                hideAccountNames: hidden,
                hideTransactionNames: hidden,
              ),
            ),
            ids,
            generatedAt: v2.now,
          )).toJson();
        }
        final compact = docs[AiExportDetailLevel.compact]!;
        final full = docs[AiExportDetailLevel.diagnostic]!;
        expect(compact['detailLevel'], 'compact');
        expect(full['detailLevel'], 'diagnostic');
        expect(compact['dataQuality'], full['dataQuality']);
        expect(compact['selection'], full['selection']);
        expect(
          (compact['selection'] as Map).containsKey('historyCompleteness'),
          false,
        );
        expect(
          (compact['dataQuality'] as Map)['deduplicationProcessing'],
          'complete',
        );
        expect(
          (compact['dataQuality'] as Map).containsKey(
            'deduplicationCompleteness',
          ),
          false,
        );
        final a = compact['transactions'] as List,
            b = full['transactions'] as List;
        expect(a.length, b.length);
        for (var i = 0; i < a.length; i++) {
          for (final key in [
            'id',
            'accountId',
            'categoryId',
            'occurredDate',
            'name',
            'amount',
            'type',
            'direction',
            'cashFlowTreatment',
            'transfer',
            'refund',
          ]) {
            expect(a[i][key], b[i][key], reason: key);
          }
          expect(a[i].containsKey('canonical'), false);
          expect(a[i].containsKey('provenance'), false);
          expect(a[i].containsKey('deduplication'), false);
          expect(a[i]['confidence'], b[i]['confidence']['overall']);
          if (b[i]['userEdited'] == true) {
            expect(a[i]['userEditedFields'], b[i]['userEditedFields']);
          }
          if (b[i]['accountResolution'] == 'unresolved') {
            expect(a[i]['accountResolution'], 'unresolved');
          }
        }
        expect(
          utf8.encode(jsonEncode(compact)).length,
          lessThan(utf8.encode(jsonEncode(full)).length),
        );
        for (final doc in docs.values) {
          final text = jsonEncode(doc);
          expect(text.contains('PRIVATE_PROVIDER'), false);
          if (hidden) {
            expect(text.contains('PRIVATE_MERCHANT'), false);
            expect(text.contains('PRIVATE_ACCOUNT'), false);
          }
        }
        expect(jsonEncode(c.synoballState.toJson()), before);
      },
    );
  }
  test('compact defaults survive version switch and IDs remain stable', () {
    final settings = AiExportSettings(
      period: StatisticsDateRange(DateTime(2026, 9), DateTime(2026, 9, 24)),
    );
    expect(settings.detailLevel, AiExportDetailLevel.compact);
    final c = f.exportFixtureController([]);
    addTearDown(c.dispose);
    final selection = AiExportSelection(
      captureAiExportSnapshot(c),
      AiExportSettings(
        period: settings.period,
        detailLevel: AiExportDetailLevel.diagnostic,
      ),
    );
    expect(
      selection
          .forVersion(AiExportVersion.v1)
          .forVersion(AiExportVersion.v2)
          .settings
          .detailLevel,
      AiExportDetailLevel.diagnostic,
    );
  });
  test('provider ID is not a proof of confirmed uniqueness', () async {
    final c = v2.controller(
      [f.exportFixtureTransaction('row')],
      sources: [v2.evidence('e', 'row', SynoballSourceType.bankWeb)],
    );
    addTearDown(c.dispose);
    expect(
      captureAiExportSnapshot(c).canonical!.facts['row']!.deduplicationStatus,
      'source_identified',
    );
  });
}
