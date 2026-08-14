import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/notification_import/data/notification_capture_service.dart';
import 'package:qesto/features/notification_import/services/automatic_notification_importer.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

import 'fixtures/sample_user_financial_data.dart';

void main() {
  BudgetController controller() => BudgetController(
    configuration: budgetConfiguration,
    financialData: sampleUserFinancialData,
  );

  CapturedNotification purchase({String key = 'notification-auto'}) =>
      CapturedNotification(
        packageName: 'ru.sberbankmobile',
        notificationKey: key,
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
    expect(capture.notifications.map((item) => item.notificationKey), [
      'unsupported',
    ]);
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
      (item) => item.providerTransactionId == 'notification-retry',
    );
    expect(evidence, hasLength(1));
  });
}

class _FakeCaptureService implements NotificationCaptureGateway {
  _FakeCaptureService(
    Iterable<CapturedNotification> notifications, {
    this.failFirstRemoval = false,
  }) : notifications = List.of(notifications);

  final List<CapturedNotification> notifications;
  final bool failFirstRemoval;
  var _removalFailed = false;

  @override
  Stream<void> get notificationEvents => const Stream.empty();

  @override
  Future<bool> hasAccess() async => true;

  @override
  Future<List<CapturedNotification>> readNotifications() async =>
      List.of(notifications);

  @override
  Future<void> removeNotification(String notificationKey) async {
    if (failFirstRemoval && !_removalFailed) {
      _removalFailed = true;
      throw StateError('simulated acknowledgement failure');
    }
    notifications.removeWhere(
      (item) => item.notificationKey == notificationKey,
    );
  }

  @override
  Future<void> clearNotifications() async => notifications.clear();

  @override
  Future<void> openSettings() async {}
}
