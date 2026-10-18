import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/features/notification_import/data/notification_capture_service.dart';
import 'package:qesto/mobile/sources/mobile_source_attention_controller.dart';
import 'package:qesto/mobile/sources/mobile_source_status_page.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  CapturedNotification raw(int index) => CapturedNotification(
    packageName: 'bank.example',
    notificationKey: 'raw-$index',
    postedAt: DateTime(2026, 10, 4),
    title: 'Captured text',
    text: 'Not a parsed transaction',
  );

  test('unsupported platform does not invoke notification channels', () async {
    final gateway = _Gateway()..accessError = StateError('no channel');
    final controller = MobileSourceAttentionController(
      gateway: gateway,
      supported: false,
    );
    await controller.start();
    await controller.refresh();
    await controller.openPermissionSettings();
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(gateway.accessCalls, 0);
    expect(gateway.readCalls, 0);
    expect(gateway.settingsCalls, 0);
    expect(gateway.eventSubscriptions, 0);
    expect(controller.needsAttention, isFalse);
    expect(controller.error, isNull);
    controller.dispose();
    await gateway.close();
  });

  test(
    'host event listener can be reused without another subscription',
    () async {
      final gateway = _Gateway()..notifications = [raw(1)];
      final controller = MobileSourceAttentionController(
        gateway: gateway,
        supported: true,
      );
      await controller.start(listenEvents: false);
      expect(gateway.eventSubscriptions, 0);
      expect(controller.pendingCount, 1);
      gateway.notifications = [];
      await controller.refresh();
      expect(controller.pendingCount, 0);
      await controller.start();
      expect(gateway.eventSubscriptions, 0);
      controller.dispose();
      await gateway.close();
    },
  );

  test(
    'startup counts raw records without import or acknowledgement',
    () async {
      final gateway = _Gateway()..notifications = [raw(1), raw(2)];
      final controller = MobileSourceAttentionController(
        gateway: gateway,
        supported: true,
      );
      await controller.start();
      expect(controller.hasPermission, isTrue);
      expect(controller.permissionDenied, isFalse);
      expect(controller.pendingCount, 2);
      expect(controller.needsAttention, isTrue);
      expect(controller.isLoading, isFalse);
      expect(controller.lastUpdated, isNotNull);
      expect(gateway.notifications, hasLength(2));
      expect(gateway.writeCalls, 0);
      controller.dispose();
      await gateway.close();
    },
  );

  test('permission denial does not hide previously captured records', () async {
    final gateway = _Gateway()
      ..access = false
      ..notifications = [raw(1)];
    final controller = MobileSourceAttentionController(
      gateway: gateway,
      supported: true,
    );
    await controller.start();
    expect(controller.permissionDenied, isTrue);
    expect(controller.pendingCount, 1);
    expect(controller.needsAttention, isTrue);
    expect(gateway.readCalls, 1);
    controller.dispose();
    await gateway.close();
  });

  test(
    'access check error is visible without leaking provider details',
    () async {
      final gateway = _Gateway()
        ..accessError = StateError('sensitive account 123456')
        ..notifications = [raw(1)];
      final controller = MobileSourceAttentionController(
        gateway: gateway,
        supported: true,
      );
      await controller.start();
      expect(controller.hasPermission, isNull);
      expect(controller.error, contains('проверить доступ'));
      expect(controller.error, isNot(contains('123456')));
      expect(controller.pendingCount, 1);
      expect(controller.needsAttention, isTrue);
      gateway.accessError = null;
      await controller.refresh();
      expect(controller.error, isNull);
      expect(controller.hasPermission, isTrue);
      controller.dispose();
      await gateway.close();
    },
  );

  test(
    'read failure retains last count and successful retry clears it',
    () async {
      final gateway = _Gateway()..notifications = [raw(1), raw(2)];
      final controller = MobileSourceAttentionController(
        gateway: gateway,
        supported: true,
      );
      await controller.start();
      final previousUpdate = controller.lastUpdated;
      gateway.readError = StateError('private payload');
      await controller.refresh();
      expect(controller.pendingCount, 2);
      expect(controller.error, contains('последний доступный статус'));
      expect(controller.lastUpdated, previousUpdate);
      gateway
        ..readError = null
        ..notifications = [];
      await controller.refresh();
      expect(controller.error, isNull);
      expect(controller.pendingCount, 0);
      expect(controller.needsAttention, isFalse);
      controller.dispose();
      await gateway.close();
    },
  );

  test(
    'arrival event refreshes and drain completion can refresh again',
    () async {
      final gateway = _Gateway();
      final controller = MobileSourceAttentionController(
        gateway: gateway,
        supported: true,
      );
      await controller.start();
      gateway.notifications = [raw(1)];
      gateway.events.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(controller.pendingCount, 1);
      gateway.notifications = [];
      await controller.refresh();
      expect(controller.pendingCount, 0);
      expect(gateway.writeCalls, 0);
      controller.dispose();
      await gateway.close();
    },
  );

  test('resume refreshes permission after system settings', () async {
    final gateway = _Gateway()..access = false;
    final controller = MobileSourceAttentionController(
      gateway: gateway,
      supported: true,
    );
    await controller.start();
    await controller.openPermissionSettings();
    expect(gateway.settingsCalls, 1);
    expect(controller.permissionDenied, isTrue);
    gateway.access = true;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(controller.hasPermission, isTrue);
    expect(controller.needsAttention, isFalse);
    controller.dispose();
    await gateway.close();
  });

  test(
    'event during read queues a fresh snapshot rather than losing it',
    () async {
      final gateway = _Gateway();
      final controller = MobileSourceAttentionController(
        gateway: gateway,
        supported: true,
      );
      await controller.start();
      final pending = Completer<List<CapturedNotification>>();
      gateway.nextRead = pending.future;
      final first = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(controller.isLoading, isTrue);
      gateway.notifications = [raw(1), raw(2)];
      gateway.events.add(null);
      await Future<void>.delayed(Duration.zero);
      pending.complete([raw(1)]);
      await first;
      expect(controller.pendingCount, 2);
      expect(gateway.readCalls, 3);
      expect(controller.isLoading, isFalse);
      controller.dispose();
      await gateway.close();
    },
  );

  test('start is idempotent and dispose ignores an unfinished read', () async {
    final gateway = _Gateway();
    final controller = MobileSourceAttentionController(
      gateway: gateway,
      supported: true,
    );
    await controller.start();
    await controller.start();
    expect(gateway.eventSubscriptions, 1);
    expect(gateway.readCalls, 1);
    final pending = Completer<List<CapturedNotification>>();
    gateway.nextRead = pending.future;
    final refresh = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    pending.complete([raw(1)]);
    await refresh;
    expect(gateway.eventCancellations, 1);
    expect(controller.pendingCount, 0);
    await gateway.close();
  });

  test(
    'settings errors remain visible and settings retry can clear them',
    () async {
      final gateway = _Gateway()..settingsError = StateError('platform error');
      final controller = MobileSourceAttentionController(
        gateway: gateway,
        supported: true,
      );
      await controller.start();
      await controller.openPermissionSettings();
      expect(controller.error, contains('открыть настройки'));
      expect(controller.needsAttention, isTrue);
      expect(controller.isOpeningSettings, isFalse);
      gateway.settingsError = null;
      await controller.openPermissionSettings();
      expect(controller.error, isNull);
      expect(gateway.writeCalls, 0);
      controller.dispose();
      await gateway.close();
    },
  );

  test(
    'event stream error is not hidden by a successful manual read',
    () async {
      final gateway = _Gateway();
      final controller = MobileSourceAttentionController(
        gateway: gateway,
        supported: true,
      );
      await controller.start();
      gateway.events.addError(StateError('event failure'));
      await Future<void>.delayed(Duration.zero);
      await controller.refresh();
      expect(controller.error, contains('обновления уведомлений'));
      expect(controller.needsAttention, isTrue);
      controller.dispose();
      await gateway.close();
    },
  );

  test(
    'import failures remain visible until a later drain reports success',
    () async {
      final gateway = _Gateway();
      final controller = MobileSourceAttentionController(
        gateway: gateway,
        supported: true,
      );
      await controller.start();
      controller.reportImportFailures(2);
      expect(controller.failedCount, 2);
      expect(controller.needsAttention, isTrue);
      await controller.refresh();
      expect(controller.failedCount, 2);
      expect(gateway.writeCalls, 0);
      controller.reportImportFailures(0);
      expect(controller.failedCount, 0);
      expect(controller.needsAttention, isFalse);
      controller.reportImportFailures(-1);
      expect(controller.failedCount, 0);
      controller.dispose();
      controller.reportImportFailures(3);
      expect(controller.failedCount, 0);
      await gateway.close();
    },
  );

  test(
    'host event failure remains visible after a successful inbox refresh',
    () async {
      final gateway = _Gateway();
      final controller = MobileSourceAttentionController(
        gateway: gateway,
        supported: true,
      );
      await controller.start(listenEvents: false);
      controller.reportEventFailure();
      expect(controller.needsAttention, isTrue);
      expect(controller.error, contains('обновления уведомлений'));
      await controller.refresh();
      controller.reportImportFailures(0);
      expect(controller.pendingCount, 0);
      expect(controller.error, contains('обновления уведомлений'));
      expect(controller.needsAttention, isTrue);
      controller.dispose();
      controller.reportEventFailure();
      await gateway.close();
    },
  );

  test('unsupported host event failure is ignored', () async {
    final gateway = _Gateway();
    final controller = MobileSourceAttentionController(
      gateway: gateway,
      supported: false,
    );
    await controller.start(listenEvents: false);
    controller.reportEventFailure();
    expect(controller.error, isNull);
    expect(controller.needsAttention, isFalse);
    controller.dispose();
    controller.reportEventFailure();
    expect(gateway.accessCalls, 0);
    await gateway.close();
  });

  for (final brightness in Brightness.values) {
    testWidgets('source page fits narrow mobile in $brightness', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _Gateway()
        ..access = false
        ..notifications = [raw(1), raw(2)];
      final controller = MobileSourceAttentionController(
        gateway: gateway,
        supported: true,
      );
      await controller.start();
      var inboxOpened = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildQestoTheme(brightness: brightness),
          home: MobileSourceStatusPage(
            controller: controller,
            onOpenInbox: () => inboxOpened = true,
          ),
        ),
      );
      await tester.tap(
        find.byKey(const Key('mobile-source-permission-settings')),
      );
      await tester.pump();
      expect(gateway.settingsCalls, 1);
      await tester.scrollUntilVisible(
        find.byKey(const Key('mobile-source-open-inbox')),
        150,
      );
      await tester.pumpAndSettle();
      expect(find.text('Входящие уведомления: 2'), findsOneWidget);
      expect(find.textContaining('не подтверждённые'), findsOneWidget);
      await tester.tap(find.byKey(const Key('mobile-source-open-inbox')));
      expect(inboxOpened, isTrue);
      expect(tester.takeException(), isNull);
      controller.dispose();
      await gateway.close();
    });
  }

  testWidgets('unsupported status is explicit and has no permission button', (
    tester,
  ) async {
    final gateway = _Gateway();
    final controller = MobileSourceAttentionController(
      gateway: gateway,
      supported: false,
    );
    await controller.start();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: MobileSourceStatusPage(
          controller: controller,
          onOpenInbox: () {},
        ),
      ),
    );
    expect(find.text('Недоступно на этой платформе'), findsOneWidget);
    expect(
      find.byKey(const Key('mobile-source-permission-settings')),
      findsNothing,
    );
    expect(gateway.accessCalls, 0);
    controller.dispose();
    await gateway.close();
  });

  testWidgets(
    'desktop bank capability stays separate from unsupported notifications',
    (tester) async {
      final gateway = _Gateway();
      final controller = MobileSourceAttentionController(
        gateway: gateway,
        supported: false,
      );
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildQestoTheme(),
          home: MobileSourceStatusPage(
            controller: controller,
            onOpenInbox: () {},
            onOpenBankConnections: () => opened = true,
          ),
        ),
      );
      expect(find.text('Недоступно на этой платформе'), findsOneWidget);
      expect(
        find.byKey(const Key('mobile-source-permission-settings')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('mobile-source-bank-connections')));
      expect(opened, isTrue);
      expect(gateway.accessCalls, 0);
      expect(tester.takeException(), isNull);
      controller.dispose();
      await gateway.close();
    },
  );

  testWidgets('attention banner updates and opens the source route', (
    tester,
  ) async {
    final gateway = _Gateway();
    final controller = MobileSourceAttentionController(
      gateway: gateway,
      supported: true,
    );
    await controller.start();
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: Scaffold(
          body: MobileSourceAttentionBanner(
            controller: controller,
            onTap: () => opened = true,
          ),
        ),
      ),
    );
    expect(
      find.byKey(const Key('mobile-source-attention-banner')),
      findsNothing,
    );
    gateway
      ..access = false
      ..notifications = [raw(1)];
    await controller.refresh();
    await tester.pump();
    expect(find.text('Источники требуют внимания'), findsOneWidget);
    expect(find.textContaining('Входящих уведомлений: 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('mobile-source-attention-banner')));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
    controller.dispose();
    await gateway.close();
  });
}

class _Gateway implements NotificationCaptureGateway {
  _Gateway() {
    events = StreamController<void>.broadcast(
      onListen: () => eventSubscriptions += 1,
      onCancel: () => eventCancellations += 1,
    );
  }

  late final StreamController<void> events;
  bool access = true;
  List<CapturedNotification> notifications = [];
  Object? accessError;
  Object? readError;
  Object? settingsError;
  Future<List<CapturedNotification>>? nextRead;
  int accessCalls = 0;
  int readCalls = 0;
  int settingsCalls = 0;
  int writeCalls = 0;
  int eventSubscriptions = 0;
  int eventCancellations = 0;

  Future<void> close() => events.close();

  @override
  Stream<void> get notificationEvents => events.stream;

  @override
  Future<bool> hasAccess() async {
    accessCalls += 1;
    if (accessError case final failure?) throw failure;
    return access;
  }

  @override
  Future<void> openSettings() async {
    settingsCalls += 1;
    if (settingsError case final failure?) throw failure;
  }

  @override
  Future<List<CapturedNotification>> readNotifications() async {
    readCalls += 1;
    if (readError case final failure?) throw failure;
    final planned = nextRead;
    nextRead = null;
    return planned ?? List<CapturedNotification>.of(notifications);
  }

  @override
  Future<void> clearNotifications() async => writeCalls += 1;

  @override
  Future<void> removeNotification(
    String notificationKey, {
    required String expectedVersion,
  }) async => writeCalls += 1;
}
