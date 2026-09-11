// Run explicitly with `flutter test tool/mobile_preview_test.dart`.
// Only synthetic test data is rendered; never reads a user's profile.
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

void main() {
  testWidgets('render mobile overview and add sheet', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('ru.qesto.qesto/notification_events'),
      (_) async => null,
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final entry in {
      'Manrope': 'assets/fonts/manrope/Manrope-Variable.ttf',
      'IBM Plex Sans': 'assets/fonts/ibm_plex/IBMPlexSans-Variable.ttf',
      'IBM Plex Mono': 'assets/fonts/ibm_plex/IBMPlexMono-Regular.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
    const boundaryKey = Key('preview-boundary');
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
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(boundaryKey),
        );
        final bitmap = await boundary.toImage();
        final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '../../.codex_tmp/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        bitmap.dispose();
      });
    }

    await capture('mobile-overview');
    await tester.tap(find.byKey(const Key('mobile-add-data')));
    await tester.pumpAndSettle();
    await capture('mobile-add');
    expect(tester.takeException(), isNull);
  });
}
