import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/notification_import/data/notification_capture_service.dart';
import 'package:qesto/features/notification_import/services/automatic_notification_importer.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/synoball/synoball.dart';

import 'fixtures/sample_user_financial_data.dart';

void main() {
  BudgetController controller() => BudgetController(
    configuration: budgetConfiguration,
    financialData: sampleUserFinancialData.copyWith(
      accounts: [
        for (final account in sampleUserFinancialData.accounts)
          if (account.id == 'card-main')
            QestoAccount(
              id: account.id,
              userId: account.userId,
              title: 'Сбер •• 1234',
              balance: account.balance,
              currency: account.currency,
              type: account.type,
            )
          else
            account,
      ],
    ),
  );

  CapturedNotification purchase({
    String key = 'notification-auto',
    String version = '',
  }) => CapturedNotification(
    packageName: 'ru.sberbankmobile',
    notificationKey: key,
    deliveryVersion: version,
    postedAt: DateTime(2026, 8, 13, 14, 32),
    title: 'Покупка Burger King',
    text: '50 ₽ - Баланс: 10 000 ₽ Счёт карты МИР *1234',
  );

  test('recognised notification is persisted without confirmation', () async {
    final budget = controller();
    final initialCount = budget.transactions.length;
    final capture = _FakeCaptureService([
      purchase(),
      CapturedNotification(
        packageName: 'ru.sberbankmobile',
        notificationKey: 'unsupported',
        postedAt: DateTime(2026, 8, 13),
        title: 'Код подтверждения',
        text: 'Не является операцией',
      ),
    ]);
    final importer = AutomaticNotificationImporter(
      controller: budget,
      captureService: capture,
    );

    final result = await importer.drain();

    expect(result.created, 1);
    expect(result.unsupported, 1);
    expect(result.failed, 0);
    expect(budget.transactions, hasLength(initialCount + 1));
    expect(
      budget.transactions.where((item) => item.merchant == 'Burger King'),
      hasLength(1),
    );
    expect(budget.pendingCandidates, isEmpty);
    expect(capture.notifications, isEmpty);
  });

  test('retry after acknowledgement failure stays idempotent', () async {
    final budget = controller();
    final initialCount = budget.transactions.length;
    final capture = _FakeCaptureService([
      purchase(key: 'notification-retry'),
    ], failFirstRemoval: true);
    final importer = AutomaticNotificationImporter(
      controller: budget,
      captureService: capture,
    );

    final first = await importer.drain();
    final second = await importer.drain();

    expect(first.created, 1);
    expect(first.failed, 1);
    expect(second.created, 0);
    expect(second.merged, 1);
    expect(second.failed, 0);
    expect(budget.transactions, hasLength(initialCount + 1));
    expect(capture.notifications, isEmpty);
    final evidence = budget.synoballState.evidence.where(
      (item) => item.sourceType == SynoballSourceType.androidNotification,
    );
    expect(evidence, hasLength(1));
    expect(
      evidence.single.providerTransactionId,
      startsWith('notification-v2-'),
    );
  });

  for (final legacyDelivery in [false, true]) {
    test(
      'ack preserves a newer inbox revision (legacy: $legacyDelivery)',
      () async {
        final budget = controller();
        final old = purchase(version: legacyDelivery ? '' : 'revision-1');
        final newer = purchase(version: 'revision-2');
        final capture = _FakeCaptureService([old]);
        capture.beforeRemoval = () {
          capture.notifications
            ..clear()
            ..add(newer);
        };

        final importer = AutomaticNotificationImporter(
          controller: budget,
          captureService: capture,
        );
        final first = await importer.drain();
        expect(first.created, 1);
        expect(first.failed, 0);
        expect(capture.notifications, [newer]);

        capture.beforeRemoval = null;
        final second = await importer.drain();
        expect(second.created, 0);
        expect(second.merged, 1);
        expect(capture.notifications, isEmpty);
      },
    );
  }

  test(
    'discarding unsupported text also checks the delivery revision',
    () async {
      final old = CapturedNotification(
        packageName: 'ru.sberbankmobile',
        notificationKey: 'notification-auto',
        deliveryVersion: 'revision-1',
        postedAt: DateTime(2026, 8, 13),
        title: 'Новости',
        text: 'Не является операцией',
      );
      final newer = purchase(version: 'revision-2');
      final capture = _FakeCaptureService([old]);
      capture.beforeRemoval = () {
        capture.notifications
          ..clear()
          ..add(newer);
      };

      final result = await AutomaticNotificationImporter(
        controller: controller(),
        captureService: capture,
      ).drain();

      expect(result.unsupported, 1);
      expect(capture.notifications, [newer]);
    },
  );

  test(
    'banking SMS is marked as SMS evidence and income affects cash flow',
    () async {
      final budget = controller();
      final capture = _FakeCaptureService([
        CapturedNotification(
          packageName: 'com.google.android.apps.messaging',
          notificationKey: 'sms-income',
          postedAt: DateTime(2026, 8, 13, 14, 32),
          title: '900',
          text: 'Перевод от Анны 5 000 ₽. Карта *1234. Баланс 15 000 ₽',
        ),
      ]);

      final result = await AutomaticNotificationImporter(
        controller: budget,
        captureService: capture,
      ).drain();

      expect(result.created, 1);
      final imported = budget.transactions.firstWhere(
        (transaction) => transaction.title == 'Анны',
        orElse: () => budget.transactions.last,
      );
      expect(imported.type, TransactionType.income);
      expect(
        budget.synoballState.evidence.last.sourceType,
        SynoballSourceType.smsNotification,
      );
    },
  );
}

class _FakeCaptureService implements NotificationCaptureGateway {
  _FakeCaptureService(
    Iterable<CapturedNotification> notifications, {
    this.failFirstRemoval = false,
  }) : notifications = List.of(notifications);

  final List<CapturedNotification> notifications;
  final bool failFirstRemoval;
  var _removalFailed = false;
  void Function()? beforeRemoval;

  @override
  Stream<void> get notificationEvents => const Stream.empty();

  @override
  Future<bool> hasAccess() async => true;

  @override
  Future<List<CapturedNotification>> readNotifications() async =>
      List.of(notifications);

  @override
  Future<void> removeNotification(
    String notificationKey, {
    required String expectedVersion,
  }) async {
    if (failFirstRemoval && !_removalFailed) {
      _removalFailed = true;
      throw StateError('simulated acknowledgement failure');
    }
    beforeRemoval?.call();
    notifications.removeWhere(
      (item) =>
          item.notificationKey == notificationKey &&
          item.deliveryVersion == expectedVersion,
    );
  }

  @override
  Future<void> clearNotifications() async => notifications.clear();

  @override
  Future<void> openSettings() async {}
}
