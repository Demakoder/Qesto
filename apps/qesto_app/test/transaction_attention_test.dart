import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/desktop/pages/desktop_statistics_page.dart';
import 'package:qesto/desktop/widgets/transaction_attention_panel.dart';
import 'package:qesto/desktop/widgets/desktop_chrome.dart';
import 'package:qesto/features/budget/add_expense_screen.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/statistics/domain/models/statistics_models.dart';
import 'package:qesto/features/statistics/presentation/state/statistics_controller.dart';
import 'package:qesto/synoball/core/models.dart';
import 'classification_test.dart' as fixture;

void main() {
  BudgetController controller() => fixture.classificationController(
    data: fixture.classificationData(
      rows: [
        fixture
            .classificationTransaction(
              'first',
              merchant: 'Неизвестный продавец',
            )
            .copyWith(
              categoryConfidence: .3,
              status: CanonicalTransactionStatus.pending,
            ),
        fixture
            .classificationTransaction('second', merchant: 'Магазин', day: 11)
            .copyWith(categoryConfidence: .3),
      ],
    ),
  );

  test('one operation can carry multiple reasons without duplicate rows', () {
    final budget = controller();
    addTearDown(budget.dispose);
    final statistics = StatisticsController(budgetController: budget);
    addTearDown(statistics.dispose);
    expect(
      statistics.snapshot.dataQuality.issues.length,
      4,
      reason: statistics.snapshot.dataQuality.issues
          .map((issue) => '${issue.transactionId}:${issue.type.name}')
          .join(', '),
    );
    final attention = attentionTransactions(statistics);
    expect(attention, hasLength(2));
    expect(
      attention.singleWhere((item) => item.transaction.id == 'first').issues,
      hasLength(3),
    );
  });

  testWidgets(
    'quality notice opens one editor and resolves only corrected reasons',
    (tester) async {
      tester.view.physicalSize = const Size(1250, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final budget = controller();
      addTearDown(budget.dispose);
      final statistics = StatisticsController(budgetController: budget);
      addTearDown(statistics.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildQestoTheme(),
          home: Scaffold(
            body: DesktopBudgetAnalysisPage(
              controller: budget,
              section: StatisticsSection.expenses,
              statisticsController: statistics,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('требуют внимания: 2'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('desktop-statistics-quality-notice')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('transaction-attention-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('attention-transaction-first')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('attention-transaction-second')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('attention-transaction-first')));
      await tester.pumpAndSettle();
      expect(
        find.text('Почему Qesto просит проверить операцию'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('expense-title-field')),
        'Проверенный магазин',
      );
      await tester.tap(
        find.byKey(const Key('expense-classification-confirm-switch')),
      );
      await tester.tap(find.byKey(const Key('expense-review-switch')));
      await tester.ensureVisible(find.text('Сохранить изменения'));
      await tester.tap(find.text('Сохранить изменения'));
      await tester.pumpAndSettle();
      expect(
        attentionTransactions(statistics),
        hasLength(1),
        reason: statistics.snapshot.dataQuality.issues
            .map((issue) => '${issue.transactionId}:${issue.type.name}')
            .join(', '),
      );
      expect(
        find.byKey(const Key('attention-transaction-first')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('attention-transaction-second')),
        findsOneWidget,
      );
      final correction = budget.synoballState.events.lastWhere(
        (event) => event.type == 'transaction.updated',
      );
      expect(correction.subjectId, 'first');
      expect(correction.payload['previousMerchant'], 'Неизвестный продавец');
      expect(correction.payload['newMerchant'], 'Проверенный магазин');
      await budget.updateTransaction(
        budget.transactions
            .singleWhere((item) => item.id == 'second')
            .copyWith(classificationConfidence: 1),
      );
      await tester.pumpAndSettle();
      expect(attentionTransactions(statistics), isEmpty);
      expect(statistics.snapshot.dataQuality.score, 100);
      expect(find.text('Всё проверено'), findsOneWidget);
      expect(find.textContaining('требуют внимания: 0'), findsNothing);
    },
  );

  testWidgets('notification center uses the same queue on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final budget = controller();
    addTearDown(budget.dispose);
    final statistics = StatisticsController(budgetController: budget);
    addTearDown(statistics.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showQestoNotificationCenter(
                  context,
                  statistics,
                  onOpenInbox: () async {},
                ),
                child: const Text('Уведомления'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Уведомления'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('notification-attention-entry')),
      findsOneWidget,
    );
    expect(find.text('2 операций требуют внимания'), findsOneWidget);
    await tester.tap(find.byKey(const Key('notification-attention-entry')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('transaction-attention-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('attention-transaction-first')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('bell badge follows the queue and disappears after correction', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final budget = controller();
    addTearDown(budget.dispose);
    final statistics = StatisticsController(budgetController: budget);
    addTearDown(statistics.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: statistics,
            builder: (context, _) => DesktopTopBar(
              title: 'Расходы',
              onSearch: () {},
              onAdd: () {},
              onNotifications: () {},
              notificationCount: attentionTransactions(statistics).length,
            ),
          ),
        ),
      ),
    );
    expect(find.text('2'), findsOneWidget);
    for (final transaction in budget.transactions.toList()) {
      await budget.updateTransaction(
        transaction.copyWith(
          isConfirmed: true,
          classificationConfidence: 1,
          merchant: 'Проверенный продавец',
          normalizedMerchant: 'проверенный продавец',
        ),
      );
    }
    await tester.pumpAndSettle();
    expect(attentionTransactions(statistics), isEmpty);
    expect(find.text('2'), findsNothing);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('deleting an operation updates an already open panel', (
    tester,
  ) async {
    final budget = controller();
    addTearDown(budget.dispose);
    final statistics = StatisticsController(budgetController: budget);
    addTearDown(statistics.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () =>
                    showTransactionAttentionPanel(context, statistics),
                child: const Text('Проверить'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Проверить'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('attention-transaction-first')),
      findsOneWidget,
    );
    await budget.deleteTransaction('first');
    expect(
      budget.transactions.map((item) => item.id),
      isNot(contains('first')),
    );
    expect(
      attentionTransactions(statistics).map((item) => item.transaction.id),
      isNot(contains('first')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attention-transaction-first')), findsNothing);
    expect(
      find.byKey(const Key('attention-transaction-second')),
      findsOneWidget,
    );
  });

  testWidgets(
    'editing a bank amount retains kopecks and stores the note separately',
    (tester) async {
      tester.view.physicalSize = const Size(1250, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = fixture
          .classificationTransaction('precise')
          .copyWith(
            amount: const Money(minorUnits: 486122, currency: 'RUB'),
            categoryConfidence: .3,
          );
      final budget = fixture.classificationController(
        data: fixture.classificationData(rows: [source]),
      );
      addTearDown(budget.dispose);
      final transaction = budget.transactions.single;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildQestoTheme(),
          home: AddExpenseScreen(
            controller: budget,
            period: budget.periods.single,
            initialTransaction: transaction,
          ),
        ),
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('expense-amount-field')),
            )
            .controller!
            .text,
        '4861,22',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Комментарий'),
        'Проверено вручную',
      );
      await tester.ensureVisible(find.text('Сохранить изменения'));
      await tester.tap(find.text('Сохранить изменения'));
      await tester.pumpAndSettle();
      final canonical = budget.synoballState.transactions.single;
      expect(canonical.amount.minorUnits, 486122);
      expect(canonical.rawDescription, source.rawDescription);
      expect(canonical.userNote, 'Проверено вручную');
      final persisted = CanonicalTransaction.fromJson(canonical.toJson());
      expect(persisted.userNote, canonical.userNote);
      expect(budget.transactions.single.comment, 'Проверено вручную');
      final reopened = fixture.classificationController(
        data: budget.mergeInto(fixture.classificationData(rows: [source])),
      );
      addTearDown(reopened.dispose);
      expect(reopened.transactions.single.amountMinor, 486122);
      expect(reopened.transactions.single.comment, 'Проверено вручную');
    },
  );

  testWidgets('missing account cannot be silently assigned during review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1250, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = fixture
        .classificationTransaction('missing')
        .copyWith(accountId: 'not-imported');
    final budget = fixture.classificationController(
      data: fixture.classificationData(rows: [source]),
    );
    addTearDown(budget.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: AddExpenseScreen(
          controller: budget,
          period: budget.periods.single,
          initialTransaction: budget.transactions.single,
        ),
      ),
    );
    await tester.ensureVisible(find.text('Сохранить изменения'));
    await tester.tap(find.text('Сохранить изменения'));
    await tester.pump();
    expect(find.text('Выберите счёт операции'), findsOneWidget);
    expect(budget.transactions.single.accountId, 'not-imported');
  });
}
