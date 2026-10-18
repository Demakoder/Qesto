import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/desktop/desktop_app_shell.dart';
import 'package:qesto/desktop/widgets/desktop_chrome.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';
import 'package:qesto/mobile/sources/mobile_source_status_page.dart';

import 'fixtures/sample_user_financial_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final android = TargetPlatformVariant.only(TargetPlatform.android);
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const notifications = MethodChannel('ru.qesto.qesto/notifications');
  const events = MethodChannel('ru.qesto.qesto/notification_events');
  late List<MethodCall> nativeCalls;
  late List<MethodCall> eventCalls;
  late List<Object?> inbox;

  setUp(() {
    nativeCalls = [];
    eventCalls = [];
    inbox = [];
    messenger.setMockMethodCallHandler(notifications, (call) async {
      nativeCalls.add(call);
      return switch (call.method) {
        'hasAccess' => false,
        'readNotifications' => inbox,
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(events, (call) async {
      eventCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(notifications, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  testWidgets(
    'Android tablet keeps four-root mobile shell beyond desktop breakpoint',
    (tester) async {
      final repository = _RecordingRepository();
      await _boot(tester, const Size(1024, 1366), repository);
      expect(find.byKey(const Key('mobile-app-shell')), findsOneWidget);
      expect(find.byType(DesktopSidebar), findsNothing);
      final navigation = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(
        navigation.destinations.cast<NavigationDestination>().map(
          (destination) => destination.label,
        ),
        ['Обзор', 'Операции', 'Бюджет', 'Капитал'],
      );
      expect(
        find.byKey(const Key('mobile-source-attention-banner')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DesktopAppShell>(find.byType(DesktopAppShell))
            .mobileSourceAttention!
            .supported,
        isTrue,
      );
      expect(repository.writes, 0);
      expect(repository.deletions, 0);
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets(
    'Android denied permission and raw inbox attention reach all roots and sources',
    (tester) async {
      inbox = [_capturedRecord(1), _capturedRecord(2)];
      final repository = _RecordingRepository();
      await _boot(tester, const Size(390, 844), repository);
      final shell = tester.widget<DesktopAppShell>(
        find.byType(DesktopAppShell),
      );
      const codec = UserFinancialDataCodec();
      final before = codec.encode(
        shell.controller.mergeInto(sampleUserFinancialData),
      );
      for (final root in ['dashboard', 'transactions', 'budget', 'capital']) {
        await tester.tap(find.byKey(Key('mobile-root-$root')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('mobile-source-attention-banner')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Нет доступа к уведомлениям'),
          findsOneWidget,
        );
        expect(find.textContaining('Входящих уведомлений: 2'), findsOneWidget);
        expect(
          tester
              .widget<Badge>(
                find.byKey(const Key('mobile-source-attention-badge')),
              )
              .isLabelVisible,
          isTrue,
        );
      }
      await tester.tap(find.byKey(const Key('mobile-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mobile-more-sources')));
      await tester.pumpAndSettle();
      expect(find.byType(MobileSourceStatusPage), findsOneWidget);
      expect(
        find.text('Доступ к уведомлениям не предоставлен'),
        findsOneWidget,
      );
      expect(find.text('Входящие уведомления: 2'), findsOneWidget);
      expect(find.textContaining('не подтверждённые'), findsOneWidget);
      expect(
        find.byKey(const Key('mobile-source-bank-connections')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const Key('mobile-source-permission-settings')),
      );
      await tester.pumpAndSettle();
      expect(
        nativeCalls.where((call) => call.method == 'openSettings'),
        hasLength(1),
      );
      expect(eventCalls.where((call) => call.method == 'listen'), hasLength(1));
      expect(
        nativeCalls.where(
          (call) =>
              call.method == 'clearNotifications' ||
              call.method == 'removeNotification',
        ),
        isEmpty,
      );
      expect(
        codec.encode(shell.controller.mergeInto(sampleUserFinancialData)),
        before,
      );
      expect(repository.writes, 0);
      expect(repository.deletions, 0);
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets(
    'Android source banner opens supported source route without editing financial data',
    (tester) async {
      final repository = _RecordingRepository();
      await _boot(tester, const Size(390, 844), repository);
      await tester.tap(find.byKey(const Key('mobile-source-attention-banner')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('mobile-source-status-page')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-source-permission-settings')),
        findsOneWidget,
      );
      expect(find.text('Недоступно на этой платформе'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('mobile-source-attention-banner')),
        findsOneWidget,
      );
      expect(repository.writes, 0);
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets(
    'Android native event failure reaches source status through the host listener',
    (tester) async {
      final repository = _RecordingRepository();
      await _boot(tester, const Size(390, 844), repository);
      ServicesBinding.instance.channelBuffers.push(
        events.name,
        const StandardMethodCodec().encodeErrorEnvelope(
          code: 'native-event-failure',
          message: 'Native event channel temporarily disconnected',
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      final attention = tester
          .widget<DesktopAppShell>(find.byType(DesktopAppShell))
          .mobileSourceAttention!;
      expect(attention.error, contains('обновления уведомлений'));
      await attention.refresh();
      await tester.tap(find.byKey(const Key('mobile-source-attention-banner')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mobile-source-error')), findsOneWidget);
      expect(find.textContaining('обновления уведомлений'), findsOneWidget);
      expect(repository.writes, 0);
      expect(eventCalls.where((call) => call.method == 'listen'), hasLength(1));
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets(
    'narrow desktop shows unsupported source status without Android status channel calls',
    (tester) async {
      final repository = _RecordingRepository();
      await _boot(tester, const Size(390, 844), repository);
      final shell = tester.widget<DesktopAppShell>(
        find.byType(DesktopAppShell),
      );
      final attention = shell.mobileSourceAttention!;
      expect(attention.supported, isFalse);
      expect(
        find.byKey(const Key('mobile-source-attention-banner')),
        findsNothing,
      );
      expect(
        tester
            .widget<Badge>(
              find.byKey(const Key('mobile-source-attention-badge')),
            )
            .isLabelVisible,
        isFalse,
      );
      // The pre-existing importer may probe hasAccess during app startup.
      // The unsupported presentation controller and route must add no probes.
      final startupCalls = List<MethodCall>.of(nativeCalls);
      await attention.start(listenEvents: false);
      await attention.refresh();
      await attention.openPermissionSettings();
      await tester.tap(find.byKey(const Key('mobile-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mobile-more-sources')));
      await tester.pumpAndSettle();
      expect(find.text('Недоступно на этой платформе'), findsOneWidget);
      expect(
        find.byKey(const Key('mobile-source-bank-connections')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-source-permission-settings')),
        findsNothing,
      );
      expect(find.byKey(const Key('mobile-source-open-inbox')), findsNothing);
      expect(nativeCalls, startupCalls);
      expect(
        nativeCalls.where((call) => call.method == 'readNotifications'),
        isEmpty,
      );
      expect(repository.writes, 0);
      expect(repository.deletions, 0);
      expect(tester.takeException(), isNull);
    },
    variant: windows,
  );
}

Future<void> _boot(
  WidgetTester tester,
  Size size,
  _RecordingRepository repository,
) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    QestoApp(preferenceStore: MemoryKeyValueStore(), repository: repository),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'initial capability wiring');
}

Map<String, Object?> _capturedRecord(int index) => {
  'packageName': 'bank.example',
  'notificationKey': 'raw-$index',
  'postedAt': DateTime(2026, 10, 4).millisecondsSinceEpoch,
  'title': 'Captured message',
  'text': 'A raw inbox record, not a parsed monetary transaction',
};

class _RecordingRepository extends MockQestoRepository {
  _RecordingRepository()
    : super(delay: Duration.zero, financialData: sampleUserFinancialData);

  int writes = 0;
  int deletions = 0;

  @override
  Future<void> saveUserFinancialData(UserFinancialData data) async => writes++;

  @override
  Future<void> deleteUserFinancialData() async => deletions++;
}
