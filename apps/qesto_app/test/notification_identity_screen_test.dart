import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/notification_import/data/notification_capture_service.dart';
import 'package:qesto/features/notification_import/presentation/notification_import_screen.dart';
import 'package:qesto/features/notification_import/services/automatic_notification_importer.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

void main() {
  for (final failSave in [false, true]) {
    testWidgets(
      'reused slot review keeps cents and inbox until save (failure=$failSave)',
      (tester) async {
        var rejectSave = false;
        late BudgetController budget;
        budget = BudgetController(
          configuration: budgetConfiguration,
          financialData: UserFinancialData(
            user: const QestoUser(
              id: 'user',
              name: 'Test',
              defaultCurrency: 'RUB',
            ),
            referenceDate: DateTime(2026, 9, 6),
            accounts: const [
              QestoAccount(
                id: 'card',
                userId: 'user',
                title: 'Сбер •• 1234',
                balance: 1000,
                currency: 'RUB',
                type: AccountType.bankCard,
              ),
            ],
          ),
          onChanged: () async {
            if (rejectSave && budget.transactions.length == 2) {
              rejectSave = false;
              throw StateError('synthetic storage failure');
            }
          },
        );
        addTearDown(budget.dispose);
        CapturedNotification purchase(
          String amount,
          int hour,
          String version,
        ) => CapturedNotification(
          packageName: 'ru.sberbankmobile',
          notificationKey: 'slot',
          deliveryVersion: version,
          postedAt: DateTime(2026, 9, 6, hour),
          title: 'Покупка Burger King',
          text: '$amount ₽ - Баланс: 10 000 ₽ Счёт карты МИР *1234',
        );
        final capture = _Capture([purchase('50', 12, 'v1')]);
        final importer = AutomaticNotificationImporter(
          controller: budget,
          captureService: capture,
        );
        expect((await importer.drain()).created, 1);
        capture.items.add(purchase('200,50', 13, 'v2'));
        expect((await importer.drain()).created, 0);
        expect(budget.pendingCandidates, hasLength(1));
        expect(capture.items, hasLength(1));
        await tester.pumpWidget(
          MaterialApp(
            home: NotificationImportScreen(
              controller: budget,
              captureService: capture,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Добавить'));
        await tester.pumpAndSettle();
        expect(find.text('Это отдельная операция?'), findsOneWidget);
        expect(budget.transactions, hasLength(1));
        rejectSave = failSave;
        await tester.tap(find.text('Подтвердить операцию'));
        await tester.pumpAndSettle();
        if (failSave) {
          expect(capture.items, hasLength(1));
          expect(
            find.textContaining('Не удалось сохранить или однозначно'),
            findsOneWidget,
          );
          await tester.tap(find.text('Добавить'));
          await tester.pumpAndSettle();
        }
        expect(budget.transactions, hasLength(2));
        expect(
          budget.transactions.map((t) => t.amountMinor),
          containsAll([5000, 20050]),
        );
        expect(capture.items, isEmpty);
        expect(budget.pendingCandidates, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _Capture extends NotificationCaptureService {
  _Capture(this.items);
  final List<CapturedNotification> items;
  @override
  Future<bool> hasAccess() async => true;
  @override
  Stream<void> get notificationEvents => const Stream.empty();
  @override
  Future<List<CapturedNotification>> readNotifications() async =>
      List.of(items);
  @override
  Future<void> removeNotification(
    String notificationKey, {
    required String expectedVersion,
  }) async {
    items.removeWhere(
      (n) =>
          n.notificationKey == notificationKey &&
          n.deliveryVersion == expectedVersion,
    );
  }
}
