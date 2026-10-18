// Real mobile widgets; exclusively synthetic fixture data, never user storage.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/statistics/domain/models/statistics_models.dart';
import 'package:qesto/mobile/analytics/mobile_analysis_page.dart';
import 'package:qesto/mobile/analytics/mobile_upcoming_page.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';
import '../test/fixtures/mobile_stage4_data.dart';

const boundaryKey = Key('stage4-preview');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final e in {
      'Onest': 'assets/fonts/white_silver/Onest-Variable.ttf',
      'Prata': 'assets/fonts/white_silver/Prata-Regular.ttf',
      'Noto Serif Display':
          'assets/fonts/white_silver/NotoSerifDisplay-Italic.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(e.key)..addFont(rootBundle.load(e.value))).load();
    }
  });
  testWidgets(
    'Stage 4 mobile render matrix and eight screens',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final messenger = tester.binding.defaultBinaryMessenger;
      const channel = MethodChannel('ru.qesto.qesto/notifications');
      const events = MethodChannel('ru.qesto.qesto/notification_events');
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'hasAccess' => true,
          'readNotifications' => <Object?>[],
          _ => null,
        },
      );
      messenger.setMockMethodCallHandler(events, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      addTearDown(() => messenger.setMockMethodCallHandler(events, null));
      Future<void> app(String kind) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: QestoApp(
              key: UniqueKey(),
              preferenceStore: MemoryKeyValueStore(),
              repository: MockQestoRepository(
                delay: Duration.zero,
                financialData: stage4Data(kind),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        tester.view.physicalSize = Size(width, 844);
        await app('typical');
        await capture(tester, 'overview-${width.toInt()}');
        if (width == 390) await capture(tester, '01-overview');
        await tester.tap(find.byKey(const Key('mobile-root-budget')));
        await tester.pumpAndSettle();
        await capture(tester, 'budget-${width.toInt()}');
        if (width == 390) await capture(tester, '02-budget');
      }
      tester.view.physicalSize = const Size(390, 844);
      for (final kind in stage4Cases.where((k) => k != 'typical')) {
        await app(kind);
        await capture(tester, 'overview-$kind');
        await tester.tap(find.byKey(const Key('mobile-root-budget')));
        await tester.pumpAndSettle();
        await capture(tester, 'budget-$kind');
      }
      final c = BudgetController(
        configuration: budgetConfiguration,
        financialData: stage4Data('typical'),
      );
      addTearDown(c.dispose);
      Future<void> show(Widget screen) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              key: UniqueKey(),
              debugShowCheckedModeBanner: false,
              theme: buildQestoTheme(),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).push<void>(MaterialPageRoute(builder: (_) => screen)),
                    child: const Text('Preview'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();
      }

      MobileAnalysisPage analysis(StatisticsSection section) =>
          MobileAnalysisPage(
            controller: c,
            section: section,
            onOpenFilteredTransactions: (_) {},
          );
      await show(analysis(StatisticsSection.expenses));
      await capture(tester, '03-expenses');
      await tester.tap(find.byKey(const Key('mobile-analysis-filters')));
      await tester.pumpAndSettle();
      await capture(tester, '07a-filter-sheet');
      final chip = find.widgetWithText(FilterChip, 'Продукты');
      await tester.tap(chip);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('statistics-apply-filters')));
      await tester.pumpAndSettle();
      await capture(tester, '07b-active-filters');
      await tester.tap(find.byKey(const Key('mobile-reset-filters')));
      await tester.pumpAndSettle();
      final chart = find.byKey(const Key('mobile-analysis-chart'));
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      await tester.dragFrom(
        tester.getTopLeft(chart) + const Offset(50, 95),
        const Offset(140, 0),
      );
      await tester.pumpAndSettle();
      await capture(tester, '08-chart-touch');
      await show(analysis(StatisticsSection.cashFlow));
      await capture(tester, '04-cash-flow');
      await show(analysis(StatisticsSection.rhythm));
      await capture(tester, '05-rhythm');
      await show(
        MobileUpcomingPage(
          controller: c,
          asOf: DateTime(2026, 7, 19),
          onOpenFilteredTransactions: (_) {},
        ),
      );
      await capture(tester, '06-upcoming');
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

Future<void> capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: name);
  for (final e in find.byType(AppBar).evaluate()) {
    e.findRenderObject()?.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final dir = Directory('docs/mobile/stage4-20261006');
    await dir.create(recursive: true);
    final bitmap = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey))
        .toImage();
    try {
      final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      bitmap.dispose();
    }
  });
}
