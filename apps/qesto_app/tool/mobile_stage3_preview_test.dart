// Diagnostic renders only: synthetic data, fake native inbox/OCR and no user storage.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/desktop/desktop_app_shell.dart';
import 'package:qesto/features/bank_screenshot_import/data/bank_screenshot_scanner_service.dart';
import 'package:qesto/features/bank_screenshot_import/domain/bank_screenshot_models.dart';
import 'package:qesto/features/bank_screenshot_import/presentation/bank_screenshot_import_screen.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/budget/transaction_editor_screen.dart';
import 'package:qesto/features/notification_import/data/notification_capture_service.dart';
import 'package:qesto/mobile/sources/mobile_source_attention_controller.dart';
import 'package:qesto/mobile/sources/mobile_source_status_page.dart';
import 'package:qesto/mobile/transactions/mobile_attention_queue.dart';
import 'package:qesto/mobile/transactions/mobile_transaction_detail.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';
import '../test/fixtures/sample_user_financial_data.dart';

const boundaryKey = Key('stage3-preview');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'Onest': 'assets/fonts/white_silver/Onest-Variable.ttf',
      'Prata': 'assets/fonts/white_silver/Prata-Regular.ttf',
      'Noto Serif Display':
          'assets/fonts/white_silver/NotoSerifDisplay-Italic.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });
  testWidgets(
    'Stage 3 real widgets render at phone size with fixture data',
    (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var access = true;
      const channel = MethodChannel('ru.qesto.qesto/notifications');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'hasAccess' => access,
          'readNotifications' => <Object?>[],
          _ => null,
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('ru.qesto.qesto/notification_events'),
        (_) async => null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(
          const MethodChannel('ru.qesto.qesto/notification_events'),
          null,
        );
      });
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: QestoApp(
            preferenceStore: MemoryKeyValueStore(),
            repository: MockQestoRepository(
              delay: Duration.zero,
              financialData: sampleUserFinancialData,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mobile-root-transactions')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      final controller = tester
          .widget<DesktopAppShell>(find.byType(DesktopAppShell))
          .controller;
      await capture(tester, '01-operations');
      final c = BudgetController(
        configuration: budgetConfiguration,
        financialData: sampleUserFinancialData,
      );
      addTearDown(c.dispose);
      final id = controller.transactions.first.id;
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
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => screen),
                    ),
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

      await show(MobileTransactionDetail(controller: c, transactionId: id));
      await capture(tester, '02-transaction-detail');
      await show(
        TransactionEditorScreen(
          controller: c,
          initialTransaction: c.transactions.firstWhere((t) => t.id == id),
        ),
      );
      await capture(tester, '03-transaction-editor');
      await c.updateTransaction(
        c.transactions.first.copyWith(
          isConfirmed: false,
          classificationConfidence: .2,
        ),
      );
      await show(
        MobileAttentionQueue(controller: c, onOpenTransaction: (_) {}),
      );
      await capture(tester, '04-attention');
      final source = MobileSourceAttentionController(
        gateway: const NotificationCaptureService(),
        supported: true,
      );
      await source.start(listenEvents: false);
      addTearDown(source.dispose);
      await show(
        MobileSourceStatusPage(controller: source, onOpenInbox: () {}),
      );
      await capture(tester, '05-sources');
      access = false;
      await source.refresh();
      await tester.pumpAndSettle();
      await capture(tester, '06-permission-denied');
      await show(
        BankScreenshotImportScreen(controller: c, scanner: PreviewScanner()),
      );
      await tester.tap(find.byKey(const Key('pick-bank-screenshots')));
      await tester.pumpAndSettle();
      await capture(tester, '07-import-review');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

Future<void> capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: name);
  // Repaint lazy AppBars to avoid a headless first-frame glyph cache artifact.
  for (final e in find.byType(AppBar).evaluate()) {
    e.findRenderObject()?.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final dir = Directory('docs/mobile/stage3-20261005');
    await dir.create(recursive: true);
    final bitmap = await tester
        .renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey))
        .toImage();
    try {
      final data = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
    } finally {
      bitmap.dispose();
    }
  });
}

class PreviewScanner implements BankScreenshotScannerGateway {
  @override
  bool get isSupported => true;
  @override
  Future<List<ExtractedBankScreenshot>> pickAndRecognize() async => [
    ExtractedBankScreenshot(
      imageHash: 'stage3-fixture',
      capturedAt: DateTime(2026, 10, 5),
      lines: const [
        BankScreenshotTextLine(text: 'PYATEROCHKA', top: 10, left: 10),
        BankScreenshotTextLine(text: '499,97 ₽', top: 10, left: 400),
        BankScreenshotTextLine(
          text: 'Оплата товаров и услуг',
          top: 30,
          left: 10,
        ),
        BankScreenshotTextLine(
          text: 'Платёжный счёт: 9 501 ₽',
          top: 50,
          left: 10,
        ),
      ],
    ),
  ];
}
