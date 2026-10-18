import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/budget/mobile_selection_toolbar.dart';
import 'package:qesto/mobile/transactions/mobile_attention_queue.dart';
import 'package:qesto/mobile/transactions/mobile_pending_review.dart';
import 'package:qesto/synoball/core/models.dart';
import 'package:qesto/features/statistics/presentation/state/statistics_controller.dart';
import 'mobile_transaction_editor_test.dart' show editorBudget, bootEditor;

void main() {
  testWidgets(
    'attention route borrows the exact origin period and returns controller ownership',
    (tester) async {
      final c = editorBudget();
      addTearDown(c.dispose);
      await c.updateTransaction(
        c.transactions.single.copyWith(
          isConfirmed: false,
          classificationConfidence: .2,
        ),
      );
      final origin = StatisticsController(budgetController: c)
        ..setCustomPeriod(DateTime(2026, 10, 3), DateTime(2026, 10, 3));
      addTearDown(origin.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MobileAttentionQueue(
            controller: c,
            statistics: origin,
            onOpenTransaction: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('attention-operation')), findsNothing);
      origin.setCustomPeriod(DateTime(2026, 10, 4), DateTime(2026, 10, 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('attention-operation')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      // Queue disposal must not dispose the read model owned by its origin.
      origin.setCustomPeriod(DateTime(2026, 10, 5), DateTime(2026, 10, 5));
      expect(origin.query.period.start.day, 5);
    },
  );
  testWidgets('editor Save remains above keyboard on a narrow phone', (
    tester,
  ) async {
    final c = editorBudget();
    addTearDown(c.dispose);
    await bootEditor(tester, c);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('transaction-save'));
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(844 - 320));
    expect(save.hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('transaction-comment')),
      150,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('transaction-editor')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(
      find.byKey(const Key('transaction-comment')),
      'Клавиатура',
    );
    await tester.pumpAndSettle();
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'attention queue reads controller changes without copied operations',
    (tester) async {
      final c = editorBudget();
      addTearDown(c.dispose);
      final t = c.transactions.single;
      await c.updateTransaction(
        t.copyWith(isConfirmed: false, classificationConfidence: .2),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MobileAttentionQueue(controller: c, onOpenTransaction: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('attention-operation')), findsOneWidget);
      await c.updateTransaction(
        c.transactions.single.copyWith(
          isConfirmed: true,
          classificationConfidence: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('attention-operation')), findsNothing);
      expect(find.text('Все операции проверены'), findsOneWidget);
    },
  );

  testWidgets(
    'bulk delete retries persistence and restores the same canonical ID/cents',
    (tester) async {
      var fail = true;
      final c = editorBudget(
        onChanged: () async {
          if (fail) throw StateError('disk');
        },
      );
      addTearDown(c.dispose);
      var cleared = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileSelectionToolbar(
              controller: c,
              ids: const {'operation'},
              onClear: () => cleared++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('В корзину'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('В корзину').last);
      await tester.pumpAndSettle();
      expect(cleared, 0);
      expect(c.trashedTransactions.single.id, 'operation');
      expect(find.text('Повторить'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(cleared, 1);
      await c.restoreTrashedTransactions(['operation']);
      expect(c.transactions.single.id, 'operation');
      expect(c.transactions.single.amountMinor, 12345);
    },
  );

  testWidgets(
    'pending voice review Back is read-only; confirm retry is idempotent',
    (tester) async {
      var fail = false;
      final c = editorBudget(
        onChanged: () async {
          if (fail) throw StateError('disk');
        },
      );
      addTearDown(c.dispose);
      final id = await c.addVoiceCandidate(
        transcript: 'Продукты 12 рублей',
        amountMinor: 1234,
        currency: 'RUB',
        accountId: 'card',
        occurredAt: DateTime(2026, 10, 5),
        merchant: 'Голосовой',
        categoryId: 'groceries',
      );
      final before = jsonEncode(c.synoballState.toJson());
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobilePendingReviewBanner(
              controller: c,
              onOpenTransaction: (id) => opened = id,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('mobile-pending-review-banner')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(jsonEncode(c.synoballState.toJson()), before);
      await tester.tap(find.byKey(const Key('mobile-pending-review-banner')));
      await tester.pumpAndSettle();
      fail = true;
      await tester.tap(find.text('Подтвердить операцию'));
      await tester.pumpAndSettle();
      expect(find.text('Повторить'), findsOneWidget);
      expect(opened, isNull);
      fail = false;
      await tester.tap(find.text('Повторить'));
      await tester.pumpAndSettle();
      expect(opened, isNotNull);
      expect(c.pendingCandidates, isEmpty);
      expect(
        c.synoballState.transactions.where((t) => t.id == opened),
        hasLength(1),
      );
      expect(
        c.synoballState.transactions
            .firstWhere((t) => t.id == opened)
            .amount
            .minorUnits,
        1234,
      );
      expect(
        c.synoballState.candidates
            .singleWhere((candidate) => candidate.id == id)
            .status,
        CandidateStatus.confirmed,
      );
    },
  );
}
