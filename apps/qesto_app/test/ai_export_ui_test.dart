import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/features/ai_export/data/ai_export_file.dart';
import 'package:qesto/features/ai_export/data/ai_export_service.dart';
import 'package:qesto/features/ai_export/domain/ai_export_models.dart';
import 'package:qesto/features/ai_export/presentation/ai_export_page.dart';
import 'ai_export_test.dart' as fixtures;

void main() {
  Future<void> open(
    WidgetTester tester, {
    double width = 1200,
    Brightness brightness = Brightness.light,
    AiExportAction? action,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 950);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final c = fixtures.exportFixtureController([
      fixtures.exportFixtureTransaction('september'),
      fixtures.exportFixtureTransaction('july', date: DateTime(2026, 7, 14)),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(brightness: brightness),
        home: Scaffold(
          body: AiExportPage(
            controller: c,
            onExport: action ?? (_) async => AiExportFileResult.cancelled,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> click(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('compact default, full choice, one shared export button', (
    tester,
  ) async {
    AiExportSelection? saved;
    await open(
      tester,
      action: (selection) async {
        saved = selection;
        return AiExportFileResult.saved;
      },
    );
    await click(tester, 'ai-export-open');
    expect(find.text('Лёгкий'), findsOneWidget);
    await click(tester, 'ai-export-detail-level');
    await tester.tap(find.text('Полный').last);
    await tester.pumpAndSettle();
    await click(tester, 'ai-export-save');
    expect(saved?.settings.detailLevel, AiExportDetailLevel.diagnostic);
    expect(saved?.transactions, hasLength(1));
  });

  for (final width in [360.0, 1200.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('AI placeholder and export dialog $width $brightness', (
        tester,
      ) async {
        var saves = 0;
        await open(
          tester,
          width: width,
          brightness: brightness,
          action: (_) async {
            saves++;
            return AiExportFileResult.saved;
          },
        );
        expect(find.text('ИИ-помощник Qesto'), findsOneWidget);
        expect(find.text('Финансовая картина'), findsNothing);
        expect(find.text('Изменение расходов'), findsNothing);
        expect(find.byType(TextField), findsNothing);
        await click(tester, 'ai-export-open');
        expect(find.byKey(const Key('ai-export-dialog')), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('ai-export-counts'))).data,
          contains('Операций: 1'),
        );
        for (final key in [
          'ai-export-hide-transactions',
          'ai-export-hide-accounts',
        ]) {
          expect(
            tester.widget<CheckboxListTile>(find.byKey(Key(key))).value,
            isTrue,
          );
        }
        expect(tester.takeException(), isNull);
        await click(tester, 'ai-export-cancel');
        expect(saves, 0);
        expect(find.byKey(const Key('ai-export-dialog')), findsNothing);
      });
    }
  }

  testWidgets(
    'period preview, privacy, custom picker and exact selected settings',
    (tester) async {
      AiExportSelection? saved;
      await open(
        tester,
        action: (s) async {
          saved = s;
          return AiExportFileResult.saved;
        },
      );
      await click(tester, 'ai-export-open');
      await tester.tap(find.text('Последние 30 дней').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 месяца').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('ai-export-counts'))).data,
        contains('Операций: 2'),
      );
      expect(find.text('01.07.2026 — 23.09.2026'), findsOneWidget);
      await click(tester, 'ai-export-hide-transactions');
      await click(tester, 'ai-export-hide-accounts');
      await tester.tap(find.text('3 месяца').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Произвольный период').last);
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '09/01/2026');
      await tester.enterText(fields.at(1), '09/23/2026');
      await tester.tap(find.text('Выбрать').last);
      await tester.pumpAndSettle();
      expect(find.text('Изменить даты'), findsOneWidget);
      await click(tester, 'ai-export-save');
      expect(saved!.transactions, hasLength(1));
      expect(saved!.settings.period.start, DateTime(2026, 9, 1));
      expect(saved!.settings.hideTransactionNames, isFalse);
      expect(saved!.settings.hideAccountNames, isFalse);
      expect(find.text('JSON-файл сохранён'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('busy blocks duplicates, cancel and safe error then retry', (
    tester,
  ) async {
    var calls = 0;
    var result = Completer<AiExportFileResult>();
    await open(
      tester,
      action: (_) {
        calls++;
        return result.future;
      },
    );
    await click(tester, 'ai-export-open');
    final button = find.byKey(const Key('ai-export-save'));
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    expect(calls, 1);
    expect(find.byKey(const Key('ai-export-progress')), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('ai-export-cancel')))
          .onPressed,
      isNull,
    );
    result.completeError(StateError('PRIVATE_PATH_AND_JSON'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не удалось подготовить JSON'), findsOneWidget);
    expect(find.textContaining('PRIVATE_PATH'), findsNothing);
    result = Completer<AiExportFileResult>();
    await tester.tap(button);
    await tester.pump();
    result.complete(AiExportFileResult.cancelled);
    await tester.pumpAndSettle();
    expect(find.text('Сохранение отменено. Файл не создан.'), findsOneWidget);
    expect(find.text('JSON-файл сохранён'), findsNothing);
    expect(calls, 2);
  });

  testWidgets('v2 default and explicit v1 compatibility choice', (
    tester,
  ) async {
    AiExportSelection? saved;
    await open(
      tester,
      action: (s) async {
        saved = s;
        return AiExportFileResult.cancelled;
      },
    );
    await click(tester, 'ai-export-open');
    await click(tester, 'ai-export-save');
    expect(saved!.settings.version, AiExportVersion.v2);
    await click(tester, 'ai-export-version');
    await tester.tap(find.text('v1 — совместимость').last);
    await tester.pumpAndSettle();
    await click(tester, 'ai-export-save');
    expect(saved!.settings.version, AiExportVersion.v1);
    expect(tester.takeException(), isNull);
  });
}
