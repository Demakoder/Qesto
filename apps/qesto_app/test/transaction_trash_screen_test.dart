import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/trash/transaction_trash_screen.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(1400, 900)]) {
    testWidgets('trash can be opened, searched and restored at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(id: 'u', name: 'User', defaultCurrency: 'RUB'),
          referenceDate: DateTime(2026, 9, 6),
          transactions: [
            BudgetTransaction(
              id: 't',
              userId: 'u',
              accountId: 'a',
              date: DateTime(2026, 9, 6),
              amount: 100,
              exactAmountMinor: 10025,
              currency: 'RUB',
              type: TransactionType.expense,
              merchant: 'Coffee',
            ),
          ],
        ),
      );
      await controller.deleteTransaction('t');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: size.width < 500 ? Brightness.dark : Brightness.light,
          ),
          home: Scaffold(body: TransactionTrashEntry(controller: controller)),
        ),
      );
      await tester.tap(find.byKey(const Key('open-transaction-trash')));
      await tester.pumpAndSettle();
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.textContaining('100,25'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('trash-search')), 'missing');
      await tester.pump();
      expect(find.text('Ничего не найдено'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('trash-search')), '');
      await tester.pump();
      if (size.width < 500) {
        await tester.tap(find.byKey(const Key('restore-trash-t')));
      } else {
        await tester.tap(find.byKey(const Key('restore-all-trash')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Отмена'));
        await tester.pumpAndSettle();
        expect(controller.trashedTransactions, hasLength(1));
        await tester.tap(find.byKey(const Key('restore-all-trash')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Восстановить'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Корзина пуста'), findsOneWidget);
      expect(controller.transactions.single.amountMinor, 10025);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'failed restoration save remains retryable without another restore event',
    (tester) async {
      var fail = false;
      var saves = 0;
      final controller = BudgetController(
        configuration: budgetConfiguration,
        onChanged: () async {
          if (fail) throw StateError('synthetic save failure');
          saves++;
        },
        financialData: UserFinancialData(
          user: const QestoUser(id: 'u', name: 'User', defaultCurrency: 'RUB'),
          referenceDate: DateTime(2026, 9, 6),
          transactions: [
            BudgetTransaction(
              id: 't',
              userId: 'u',
              accountId: 'a',
              date: DateTime(2026, 9, 6),
              amount: 100,
              currency: 'RUB',
              type: TransactionType.expense,
              merchant: 'Coffee',
            ),
          ],
        ),
      );
      await controller.deleteTransaction('t');
      fail = true;
      await tester.pumpWidget(
        MaterialApp(home: TransactionTrashScreen(controller: controller)),
      );
      await tester.tap(find.byKey(const Key('restore-trash-t')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Не удалось сохранить'), findsOneWidget);
      expect(saves, 1);
      fail = false;
      await tester.tap(find.byKey(const Key('retry-trash-save')));
      await tester.pumpAndSettle();
      expect(saves, 2);
      expect(controller.transactions, hasLength(1));
      expect(
        controller.synoballState.events.where(
          (event) => event.type == 'transaction.restored',
        ),
        hasLength(1),
      );
      expect(find.byKey(const Key('retry-trash-save')), findsNothing);
    },
  );
}
