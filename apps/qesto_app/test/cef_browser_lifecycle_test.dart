import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/bank_browser/config/bank_connector_registry.dart';
import 'package:qesto/features/bank_browser/data/browser_profile_manager.dart';
import 'package:qesto/features/bank_browser/domain/bank_browser_models.dart';
import 'package:qesto/features/bank_browser/runtime/browser_controller.dart';
import 'package:webview_cef/webview_cef.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('webview_cef');
  final calls = <MethodCall>[];
  Completer<List<int>>? createGate;
  Completer<void>? closeGate;
  Completer<void>? createCalled;
  var browserId = 100;
  setUp(() {
    calls.clear();
    createGate = null;
    closeGate = null;
    createCalled = Completer<void>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'create':
          if (!createCalled!.isCompleted) createCalled!.complete();
          return createGate == null
              ? [++browserId, browserId]
              : await createGate!.future;
        case 'close':
          await closeGate?.future;
          return null;
        case 'canGoBack':
        case 'canGoForward':
        case 'hasNativeKeySupport':
          return false;
        default:
          return null;
      }
    });
  });
  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  Future<BrowserController> browser() async {
    final root = await Directory.systemTemp.createTemp('qesto-cef-mock-');
    addTearDown(() => root.delete(recursive: true));
    final profiles = BrowserProfileManager(rootDirectory: root);
    return BrowserController(
      profile: await profiles.createProfile(BankConnectorRegistry.sber),
      bank: BankConnectorRegistry.sber,
      profileManager: profiles,
      onNotice: (_) {},
    );
  }

  test(
    'closing during native creation waits for native close and never resurrects',
    () async {
      final controller = await browser();
      createGate = Completer<List<int>>();
      closeGate = Completer<void>();
      final opening = controller.open(
        presentationMode: BrowserPresentationMode.background,
      );
      await createCalled!.future;
      var closed = false;
      final closing = controller.close().then((_) => closed = true);
      createGate!.complete([++browserId, browserId]);
      await opening;
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(controller.isRuntimeReady, isFalse);
      expect(closed, isFalse);
      expect(calls.where((c) => c.method == 'close'), hasLength(1));
      closeGate!.complete();
      await closing;
      await controller.close();
      expect(controller.state.lifecycle, BankBrowserLifecycle.closed);
      expect(calls.where((c) => c.method == 'close'), hasLength(1));
      expect(
        () => controller.waitForLoadState(BankBrowserLoadState.finished),
        throwsStateError,
      );
      controller.dispose();
    },
  );

  test('a fast native load completion is not overwritten by open', () async {
    final controller = await browser();
    createGate = Completer<List<int>>();
    final opening = controller.open();
    await createCalled!.future;
    ++browserId;
    // Deliver before the create result deterministically, not with a timing
    // sleep that passed by luck when the test machine was idle.
    await WebviewManager().methodCallhandler(
      MethodCall('onLoadEnd', {
        'browserId': browserId,
        'urlId': BankConnectorRegistry.sber.startUrl.toString(),
      }),
    );
    createGate!.complete([browserId, browserId]);
    await opening;
    await controller
        .waitForLoadState(BankBrowserLoadState.finished)
        .timeout(const Duration(seconds: 1));
    expect(controller.state.lifecycle, BankBrowserLifecycle.ready);
    await controller.close();
    controller.dispose();
  });

  test('late native load after close is safely ignored', () async {
    final controller = await browser();
    await controller.open();
    await controller.close();
    await WebviewManager().methodCallhandler(
      MethodCall('onLoadEnd', {
        'browserId': browserId,
        'urlId': BankConnectorRegistry.sber.startUrl.toString(),
      }),
    );
    expect(controller.state.lifecycle, BankBrowserLifecycle.closed);
    controller.dispose();
  });

  test('close immediately rejects load/navigation waiters', () async {
    final controller = await browser();
    await controller.open();
    final navigation = expectLater(
      controller.waitForNavigation(),
      throwsStateError,
    );
    final loading = expectLater(
      controller.waitForLoadState(BankBrowserLoadState.finished),
      throwsStateError,
    );
    await controller.close();
    await Future.wait([navigation, loading]);
    controller.dispose();
  });

  test(
    'background viewport is sized but never receives keyboard focus',
    () async {
      final controller = await browser();
      await controller.open(
        presentationMode: BrowserPresentationMode.background,
      );
      expect(controller.isRuntimeReady, isTrue);
      expect(
        calls
            .where((c) => c.method == 'setClientFocus')
            .map((c) => (c.arguments as List).last),
        [false],
      );
      expect(calls.where((c) => c.method == 'setSize'), isNotEmpty);
      await controller.close();
      controller.dispose();
    },
  );

  testWidgets(
    'Flutter dialog takes focus from CEF and typing never reaches webview',
    (tester) async {
      final manager = WebviewManager();
      late WebViewController controller;
      await tester.runAsync(() async {
        await manager.initialize(rootCachePath: 'unused-mock-profile');
        controller = manager.createWebView();
        await controller.initialize(
          'https://example.invalid',
          profilePath: 'unused',
          allowedOrigins: ['https://example.invalid'],
        );
      });
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Scaffold(body: controller.webviewWidget),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        calls
            .where((c) => c.method == 'setClientFocus')
            .map((c) => (c.arguments as List).last),
        contains(true),
      );
      unawaited(
        showDialog<void>(
          context: nav.currentContext!,
          builder: (_) =>
              const AlertDialog(content: TextField(autofocus: true)),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls.lastWhere((c) => c.method == 'setClientFocus').arguments, [
        browserId,
        false,
      ]);
      calls.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.pump();
      expect(calls.where((c) => c.method == 'sendKeyEvent'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(controller.dispose);
      expect(tester.takeException(), isNull);
    },
  );
}
