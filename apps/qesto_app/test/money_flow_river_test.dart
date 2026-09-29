import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/desktop/widgets/money_flow_river.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'Onest': 'assets/fonts/white_silver/Onest-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });

  MoneyFlowCategory category(int amount, {List<int>? purchases}) =>
      MoneyFlowCategory(
        id: '$amount',
        label: '$amount',
        amount: amount,
        color: Colors.teal,
        iconKey: 'other',
        purchases: [
          for (final value in purchases ?? [amount])
            MoneyFlowPurchase(label: '$value', amount: value),
        ],
      );

  test('one shared scale keeps 25k, 20k, 10k and 5k proportional', () {
    const total = 60000;
    const flowHeight = 480.0;
    final heights = [
      for (final amount in [25000, 20000, 10000, 5000])
        moneyFlowThickness(amount, total, flowHeight),
    ];

    expect(heights, [200, 160, 80, 40]);
    expect(heights.reduce((a, b) => a + b), flowHeight);
    expect(heights.first / heights.last, 5);
  });

  test('purchases use their parent category share of the same total', () {
    const total = 60000;
    const flowHeight = 480.0;
    final categoryHeight = moneyFlowThickness(25000, total, flowHeight);
    final purchases = [
      10000,
      8000,
      7000,
    ].map((amount) => moneyFlowThickness(amount, total, flowHeight));

    expect(purchases.reduce((a, b) => a + b), categoryHeight);
    expect(moneyFlowThickness(5000, total, flowHeight), 40);
  });

  test('small branch adds height rather than taking a fixed 34 px share', () {
    final data = [
      category(29349),
      category(26518),
      category(21025),
      category(11160),
      category(8265),
      category(4641),
      category(5530),
    ];
    final height = moneyFlowRiverHeight(data, compact: false);
    final drawable = height - 62 - 10 * (data.length - 1);
    final total = data.fold<int>(0, (sum, item) => sum + item.amount);

    expect(height, greaterThan(470));
    expect(moneyFlowThickness(4641, total, drawable), greaterThanOrEqualTo(26));
    expect(
      moneyFlowThickness(26518, total, drawable) /
          moneyFlowThickness(5530, total, drawable),
      closeTo(26518 / 5530, 0.0001),
    );
  });

  testWidgets('the river renders the screenshot-sized flow without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final values = [29349, 26518, 21025, 11160, 8265, 4641, 5530];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: Colors.white,
              child: MoneyFlowRiver(
                income: 106485,
                expenses: 100955,
                categories: [
                  for (final value in values)
                    category(value, purchases: [value ~/ 2, value - value ~/ 2]),
                ],
                currency: 'RUB',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(MoneyFlowRiver)).height,
      moneyFlowRiverHeight([
        for (final value in values) category(value),
      ], compact: false),
    );
    if (Platform.environment['QESTO_MONEY_FLOW_RENDER'] == '1') {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = File('../../.codex_tmp/money-flow-river-after.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
  });
}
