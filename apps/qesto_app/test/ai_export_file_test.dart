import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/ai_export/data/ai_export_file.dart';
import 'package:qesto/features/ai_export/data/ai_export_file_native.dart'
    show saveWindowsAiExport, saveAndroidAiExport;
import 'package:qesto/features/ai_export/data/ai_export_ids.dart';
import 'package:qesto/features/ai_export/data/ai_export_service.dart';
import 'package:qesto/features/ai_export/data/ai_export_snapshot.dart';
import 'package:qesto/features/ai_export/domain/ai_export_models.dart';
import 'package:qesto/features/statistics/domain/models/statistics_models.dart';
import 'ai_export_test.dart' as fixtures;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Android channel UTF-8 bytes, cancellation, null and lost channel',
    () async {
      const channel = MethodChannel('ru.qesto.qesto/ai_export');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      for (final answer in [true, false]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'saveJson');
          expect(
            utf8.decode(call.arguments['bytes'] as Uint8List),
            '{"name":"Продукты"}',
          );
          return answer;
        });
        expect(
          await saveAndroidAiExport(
            '{"name":"Продукты"}',
            'qesto-ai-export-2026-09-23.json',
          ),
          answer ? AiExportFileResult.saved : AiExportFileResult.cancelled,
        );
      }
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      await expectLater(
        saveAndroidAiExport('{}', 'test.json'),
        throwsA(isA<AiExportFileException>()),
      );
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(
        saveAndroidAiExport('{}', 'test.json'),
        throwsA(isA<MissingPluginException>()),
      );
    },
  );
  test('cancel never writes; writer failure never reports success', () async {
    var writes = 0;
    expect(
      await saveWindowsAiExport(
        '{}',
        'qesto.json',
        choosePath: (_) async => null,
        writeFile: (_, _) async {
          writes++;
        },
      ),
      AiExportFileResult.cancelled,
    );
    expect(writes, 0);
    await expectLater(
      saveWindowsAiExport(
        '{}',
        'qesto.json',
        choosePath: (_) async => 'unused',
        writeFile: (_, _) async => throw const FileSystemException('denied'),
      ),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'UTF-8 atomic JSON file, overwrite and no remaining staging file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'qesto-ai-export-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final target = File('${directory.path}/выгрузка.json');
      for (final text in ['{"name":"Продукты ₽"}', '{"name":"Евро €"}']) {
        expect(
          await saveWindowsAiExport(
            text,
            'qesto.json',
            choosePath: (_) async => target.path,
          ),
          AiExportFileResult.saved,
        );
        expect(await target.readAsString(encoding: utf8), text);
        expect(jsonDecode(await target.readAsString()), contains('name'));
      }
      expect(await directory.list().length, 1);
    },
  );

  test(
    'service output reuses selection, stable IDs and safe filename',
    () async {
      final c = fixtures.exportFixtureController([
        fixtures.exportFixtureTransaction('PRIVATE'),
      ]);
      addTearDown(c.dispose);
      final snapshot = captureAiExportSnapshot(c);
      final selection = AiExportSelection(
        snapshot,
        AiExportSettings(
          period: StatisticsDateRange(DateTime(2026, 9), DateTime(2026, 9, 23)),
        ),
      );
      final secrets = fixtures.MemoryExportSecrets();
      final documents = <Map<String, dynamic>>[];
      for (var i = 0; i < 2; i++) {
        final service = AiExportService(
          ids: AiExportIdStore(secureStore: secrets),
          save: (json, name) async {
            expect(
              name,
              matches(RegExp(r'^qesto-ai-export-\d{4}-\d{2}-\d{2}\.json$')),
            );
            expect(json, contains('\n  "schemaVersion"'));
            documents.add(jsonDecode(json) as Map<String, dynamic>);
            return AiExportFileResult.saved;
          },
        );
        expect(await service.export(selection), AiExportFileResult.saved);
      }
      expect(documents[0]['transactions'], documents[1]['transactions']);
      expect(
        documents[0]['transactions'],
        hasLength(selection.transactions.length),
      );
      expect(documents[0]['accounts'], hasLength(selection.accounts.length));
      expect(
        documents[0]['categories'],
        hasLength(selection.categoryIds.length),
      );
    },
  );
}
