// Explicit diagnostic: flutter test tool/mobile_foundation_preview_test.dart
// The renders use only synthetic fixtures and an in-memory preference store.
// No installed application, real notification inbox or user profile is read.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';

import '../test/fixtures/sample_user_financial_data.dart';

const _previewBoundary = Key('mobile-foundation-preview-boundary');
const _outputDirectory = 'docs/mobile/foundation-20261004';
const _roots = <String, String>{
  'dashboard': '01-overview',
  'transactions': '02-transactions',
  'budget': '03-budget',
  'capital': '04-capital',
};

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
      await (FontLoader(entry.key)
            ..addFont(rootBundle.load(entry.value)))
          .load();
    }
  });

  Future<void> mountMobile(
    WidgetTester tester,
    Size size, {
    bool notificationAccess = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('ru.qesto.qesto/notifications'),
      (call) async => switch (call.method) {
        'hasAccess' => notificationAccess,
        'readNotifications' => <Object?>[],
        _ => null,
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('ru.qesto.qesto/notification_events'),
      (_) async => null,
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(
        const MethodChannel('ru.qesto.qesto/notifications'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('ru.qesto.qesto/notification_events'),
        null,
      );
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: _previewBoundary,
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
    expect(find.byKey(const Key('mobile-app-shell')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'initial mobile shell');
  }

  Future<void> openRoot(WidgetTester tester, String root) async {
    await tester.tap(find.byKey(Key('mobile-root-$root')));
    await tester.pumpAndSettle();
    // A lazily visited Navigator can need a later paint after its initial
    // route becomes active. Do not confuse a first-frame capture with the
    // user's settled screen, and verify actions are actually hittable.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('mobile-more')).hitTestable(),
      findsOneWidget,
      reason: '$root: More action',
    );
    expect(
      find.byTooltip('Поиск').hitTestable(),
      findsOneWidget,
      reason: '$root: search action',
    );
    expect(
      find.byTooltip('Уведомления').hitTestable(),
      findsOneWidget,
      reason: '$root: notifications action',
    );
    expect(tester.takeException(), isNull, reason: 'mobile root $root');
  }

  Future<void> capture(WidgetTester tester, String filename) async {
    // Headless toImage can reuse an incomplete font/glyph paint cache for a
    // lazily created Navigator's first AppBar. Repaint the existing toolbar
    // actions without changing widgets, layout, state or financial data.
    // These captures are diagnostic renders, not real-device verification.
    for (final action in [
      find.byTooltip('Поиск'),
      find.byTooltip('Уведомления'),
      find.byKey(const Key('mobile-more')),
    ]) {
      if (action.evaluate().length == 1) {
        tester.renderObject(action).markNeedsPaint();
      }
    }
    await tester.pump();
    await tester.runAsync(() async {
      final directory = Directory(_outputDirectory);
      await directory.create(recursive: true);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_previewBoundary),
      );
      final bitmap = await boundary.toImage();
      try {
        final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
        await File('${directory.path}/$filename.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        bitmap.dispose();
      }
    });
  }

  testWidgets(
    'render the four foundation roots and secondary More entry',
    (tester) async {
      await mountMobile(tester, const Size(390, 844));
      for (final root in _roots.entries) {
        await openRoot(tester, root.key);
        await capture(tester, root.value);
      }
      await tester.tap(find.byKey(const Key('mobile-more')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'secondary More entry');
      await capture(tester, '05-more');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mobile-app-shell')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'back from More');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'four roots remain reachable at 360px without a Drawer',
    (tester) async {
      await mountMobile(tester, const Size(360, 800));
      expect(find.byType(Drawer), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
      for (final root in _roots.keys) {
        await openRoot(tester, root);
        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(bar.destinations, hasLength(4));
      }
      await tester.tap(find.byKey(const Key('mobile-add-data')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add-data-manual')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'global add action');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'render source attention on a root when notification permission is denied',
    (tester) async {
      await mountMobile(
        tester,
        const Size(390, 844),
        notificationAccess: false,
      );
      expect(
        find.byKey(const Key('mobile-source-attention-banner')),
        findsOneWidget,
      );
      final badge = tester.widget<Badge>(
        find.byKey(const Key('mobile-source-attention-badge')),
      );
      expect(badge.isLabelVisible, isTrue);
      await capture(tester, '06-source-attention');
      await tester.tap(
        find.byKey(const Key('mobile-source-attention-banner')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('mobile-source-status-page')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: 'source attention route');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
