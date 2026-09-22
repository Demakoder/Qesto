import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/design_system/qesto_expandable_tool.dart';
import 'package:qesto/design_system/qesto_window.dart';
import 'package:qesto/desktop/overview/desktop_overview_data.dart';
import 'package:qesto/desktop/overview/overview_expense_trend_chart.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final points = List.generate(
    31,
    (i) => OverviewTrendPoint(
      date: DateTime(2026, 8, i + 1),
      amount: (i + 1) * 123456789,
    ),
  );

  test('Graphite surfaces and readable semantic roles are distinct', () {
    final light = buildQestoTheme().extension<QestoSemanticColors>()!;
    final dark = buildQestoTheme(
      brightness: Brightness.dark,
    ).extension<QestoSemanticColors>()!;
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }

    expect(light.chartSurface, Colors.white);
    expect(dark.chartSurface.computeLuminance(), lessThan(.1));
    expect(dark.surface, isNot(dark.background));
    for (final colors in [light, dark]) {
      for (final foreground in [
        colors.text,
        colors.secondaryText,
        colors.positive,
        colors.negative,
      ]) {
        expect(contrast(foreground, colors.surface), greaterThanOrEqualTo(4.5));
      }
    }
  });

  test(
    'Measured axes, endpoints and hit testing stay inside local viewport',
    () {
      for (final width in [280.0, 480.0, 1024.0, 1280.0]) {
        for (final scale in [1.0, 1.5, 2.0]) {
          final scaler = TextScaler.linear(scale);
          final g = OverviewTrendGeometry.compute(
            Size(width, 285),
            points,
            'RUB',
            scaler,
          );
          expect(g.plot.left, greaterThan(0));
          expect(g.plot.right, lessThanOrEqualTo(width));
          for (final label in g.yLabels) {
            final p = OverviewTrendGeometry.label(label, scaler, Colors.black);
            expect(g.plot.left - p.width - 8, greaterThanOrEqualTo(0));
          }
          for (final i in g.xLabels.keys) {
            final bounds = g.xLabelBounds(i, points.length, scaler);
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(width));
            expect(bounds.bottom, lessThanOrEqualTo(285));
          }
          expect(g.indexAt(g.x(0, points.length), points.length), 0);
          expect(g.indexAt(g.x(30, points.length), points.length), 30);
        }
      }
    },
  );

  testWidgets('Theme switches and expansion preserve fields and chart state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final brightness = ValueNotifier(Brightness.light);
    addTearDown(brightness.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder(
        valueListenable: brightness,
        builder: (context, value, _) => MaterialApp(
          theme: buildQestoTheme(brightness: value),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 600,
                child: QestoExpandableTool(
                  title: 'Динамика',
                  builder: (context, expanded) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const TextField(key: Key('filter')),
                      Flexible(
                        fit: expanded ? FlexFit.tight : FlexFit.loose,
                        child: OverviewExpenseTrendChart(
                          points: points,
                          currency: 'RUB',
                          granularity: OverviewTrendGranularity.days,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('filter')), 'Подписки');
    final chartState = tester.state(find.byType(OverviewExpenseTrendChart));
    final fieldState = tester.state(find.byType(TextField));
    for (final theme in [Brightness.dark, Brightness.light]) {
      brightness.value = theme;
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TextField)), same(fieldState));
      expect(find.text('Подписки'), findsOneWidget);
      expect(find.byType(ColorFiltered), findsNothing);
      final chartContext = tester.element(find.byType(QestoChartSurface));
      expect(Theme.of(chartContext).brightness, theme);
      await tester.tap(find.byTooltip('Развернуть Динамика'));
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(OverviewExpenseTrendChart)),
        same(chartState),
      );
      for (final size in [const Size(1280, 900), const Size(1024, 600)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final chartRect = tester.getRect(find.byType(QestoChartSurface));
        expect(chartRect.bottom, lessThan(size.height));
        expect(chartRect.right, lessThan(size.width));
        final pointer = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await pointer.addPointer(location: chartRect.center);
        await pointer.moveTo(Offset(chartRect.right - 14, chartRect.center.dy));
        await tester.pump();
        final tooltip = find.textContaining('Расходы ');
        expect(tooltip, findsOneWidget);
        expect(
          tester.getRect(tooltip).right,
          lessThanOrEqualTo(chartRect.right),
        );
        await pointer.removePointer();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TextField)), same(fieldState));
      expect(
        tester.state(find.byType(OverviewExpenseTrendChart)),
        same(chartState),
      );
      expect(tester.takeException(), isNull);
    }
  });

  for (final dpr in [1.0, 1.5, 2.0]) {
    testWidgets('Cold app and resize retain real viewport at DPR $dpr', (
      tester,
    ) async {
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = Size(1024 * dpr, 768 * dpr);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        QestoApp(
          repository: const MockQestoRepository(delay: Duration.zero),
          preferenceStore: MemoryKeyValueStore(),
        ),
      );
      await tester.pumpAndSettle();
      for (final width in [1024.0, 1440.0, 1280.0, 700.0, 1024.0]) {
        tester.view.physicalSize = Size(width * dpr, 768 * dpr);
        await tester.pumpAndSettle();
        final ctx = tester.element(find.byType(Scaffold).first);
        expect(MediaQuery.sizeOf(ctx), Size(width, 768));
        expect(MediaQuery.devicePixelRatioOf(ctx), dpr);
        expect(tester.getSize(find.byType(Scaffold).first).width, width);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
