import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/budget/transaction_editor_screen.dart';
import 'package:qesto/mobile/transactions/mobile_transaction_detail.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

BudgetController editorBudget({
  TransactionType type = TransactionType.expense,
  TransferDirection? direction,
  Future<void> Function()? onChanged,
}) => BudgetController(
  configuration: budgetConfiguration,
  onChanged: onChanged,
  financialData: UserFinancialData(
    user: const QestoUser(id: 'user', name: 'Test', defaultCurrency: 'RUB'),
    referenceDate: DateTime(2026, 10, 5),
    accounts: const [
      QestoAccount(
        id: 'card',
        userId: 'user',
        title: 'Карта',
        balance: 1000,
        currency: 'RUB',
        type: AccountType.bankCard,
      ),
      QestoAccount(
        id: 'savings',
        userId: 'user',
        title: 'Накопительный',
        balance: 2000,
        currency: 'RUB',
        type: AccountType.savings,
      ),
    ],
    transactions: [
      BudgetTransaction(
        id: 'operation',
        userId: 'user',
        accountId: 'card',
        date: DateTime(2026, 10, 4, 13, 24),
        amount: 124,
        exactAmountMinor: 12345,
        currency: 'RUB',
        type: type,
        transferDirection: direction,
        categoryId: 'groceries',
        subcategoryId: 'Супермаркеты',
        merchant: 'Продавец',
        title: 'Продавец',
        description: 'Bank evidence untouched',
        tags: [
          if (type == TransactionType.transfer && direction == null)
            'qesto-internal-transfer',
        ],
      ),
    ],
  ),
);

Future<void> bootEditor(
  WidgetTester tester,
  BudgetController c, {
  bool draft = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open editor'),
            onPressed: () => Navigator.of(context).push<BudgetTransaction>(
              MaterialPageRoute<BudgetTransaction>(
                builder: (_) => TransactionEditorScreen(
                  controller: c,
                  initialTransaction: c.transactions.single,
                  draftOnly: draft,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

void main() {
  for (final type in TransactionType.values) {
    final directions = type == TransactionType.transfer
        ? [null, TransferDirection.incoming, TransferDirection.outgoing]
        : <TransferDirection?>[null];
    for (final direction in directions) {
      for (final amount in ['125', '125,67']) {
        testWidgets(
          '$type $direction editor preserves canonical semantics ($amount)',
          (tester) async {
            final c = editorBudget(type: type, direction: direction);
            addTearDown(c.dispose);
            final before = c.synoballState.transactions.single;
            await bootEditor(tester, c);
            expect(
              find.text(transactionTypeLabel(c.transactions.single)),
              findsOneWidget,
            );
            await tester.enterText(
              find.byKey(const Key('transaction-amount')),
              amount,
            );
            await tester.enterText(
              find.byKey(const Key('transaction-merchant')),
              'Исправленное название',
            );
            await tester.tap(find.byKey(const Key('transaction-save')));
            await tester.pumpAndSettle();
            final after = c.synoballState.transactions.single;
            expect(after.id, before.id);
            expect(after.direction, before.direction);
            expect(after.transferDirection, before.transferDirection);
            expect(after.eventType, before.eventType);
            expect(
              after.tags.where((tag) => tag.startsWith('legacy-type-')),
              before.tags.where((tag) => tag.startsWith('legacy-type-')),
            );
            expect(after.amount.minorUnits, amount == '125' ? 12500 : 12567);
            expect(after.merchantName, 'Исправленное название');
            expect(after.rawDescription, before.rawDescription);
            expect(after.occurredAt, before.occurredAt);
            expect(c.transactions.single.type, type);
            expect(find.byType(TransactionEditorScreen), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
  test('fraction parser never rounds or accepts ambiguous/negative values', () {
    expect(parseMinorAmount('1 234,56'), 123456);
    expect(parseMinorAmount('0.01'), 1);
    for (final value in ['1,234', '-10', '0', '', '1.2.3', '1e4']) {
      expect(parseMinorAmount(value), isNull);
    }
  });
  testWidgets('draft correction and cancel do not mutate canonical data', (
    tester,
  ) async {
    final c = editorBudget(type: TransactionType.income);
    addTearDown(c.dispose);
    final before = jsonEncode(c.synoballState.toJson());
    await bootEditor(tester, c, draft: true);
    await tester.enterText(
      find.byKey(const Key('transaction-merchant')),
      'Draft correction',
    );
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Отменить изменения?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionEditorScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('transaction-save')));
    await tester.pumpAndSettle();
    expect(jsonEncode(c.synoballState.toJson()), before);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Android Back discards only after confirmation; clean Back is immediate',
    (tester) async {
      final c = editorBudget();
      addTearDown(c.dispose);
      final before = jsonEncode(c.synoballState.toJson());
      await bootEditor(tester, c);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Отменить изменения?'), findsNothing);
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('transaction-amount')),
        '500,10',
      );
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Не сохранять'));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionEditorScreen), findsNothing);
      expect(jsonEncode(c.synoballState.toJson()), before);
    },
  );
  testWidgets(
    'save error stays in editor, retry and double save keep same canonical ID',
    (tester) async {
      var fail = true;
      var calls = 0;
      final c = editorBudget(
        onChanged: () async {
          calls++;
          if (fail) throw StateError('disk failure');
        },
      );
      addTearDown(c.dispose);
      await bootEditor(tester, c);
      await tester.enterText(
        find.byKey(const Key('transaction-amount')),
        '600,25',
      );
      await tester.tap(find.byKey(const Key('transaction-save')));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionEditorScreen), findsOneWidget);
      expect(find.byKey(const Key('transaction-editor-error')), findsOneWidget);
      fail = false;
      // A queued second callback is ignored while the first save is active.
      final save = tester
          .widget<FilledButton>(find.byKey(const Key('transaction-save')))
          .onPressed!;
      save();
      save();
      await tester.pumpAndSettle();
      expect(c.synoballState.transactions, hasLength(1));
      expect(c.synoballState.transactions.single.amount.minorUnits, 60025);
      expect(calls, 2);
    },
  );
  testWidgets(
    'account, category, subcategory, note and labels save through existing controller',
    (tester) async {
      final c = editorBudget();
      addTearDown(c.dispose);
      await c.saveUserTag(name: 'Проверить', colorValue: 0xff006b6b);
      await bootEditor(tester, c);
      final account = find.byKey(const Key('transaction-account'));
      await tester.ensureVisible(account);
      await tester.tap(account);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Накопительный').last);
      await tester.pumpAndSettle();
      final category = find.byKey(
        const ValueKey('transaction-category-groceries'),
      );
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Кафе и рестораны').last);
      await tester.pumpAndSettle();
      final note = find.byKey(const Key('transaction-comment'));
      await tester.ensureVisible(note);
      await tester.enterText(note, 'Моя заметка');
      await tester.ensureVisible(find.text('Проверить'));
      await tester.tap(find.text('Проверить'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('transaction-save')));
      await tester.pumpAndSettle();
      final t = c.synoballState.transactions.single;
      expect(t.accountId, 'savings');
      expect(t.effectiveCategory, 'cafes');
      expect(t.subcategoryId, isNull);
      expect(t.userNote, 'Моя заметка');
      expect(
        c.tagsForTransaction(c.transactions.single).single.name,
        'Проверить',
      );
      expect(t.rawDescription, 'Bank evidence untouched');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'detail delete uses canonical trash and restore keeps identity/cents',
    (tester) async {
      final c = editorBudget(type: TransactionType.refund);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Detail'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => MobileTransactionDetail(
                      controller: c,
                      transactionId: c.transactions.single.id,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Detail'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('mobile-transaction-delete')),
        250,
      );
      await tester.tap(find.byKey(const Key('mobile-transaction-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('В корзину').last);
      await tester.pumpAndSettle();
      expect(c.transactions, isEmpty);
      expect(c.trashedTransactions.single.id, 'operation');
      await c.restoreTrashedTransactions(['operation']);
      expect(c.transactions.single.amountMinor, 12345);
      expect(c.transactions.single.type, TransactionType.refund);
    },
  );
  test('manual fractional expense retries with a stable form ID', () async {
    var fail = true;
    final c = editorBudget(
      onChanged: () async {
        if (fail) throw StateError('disk');
      },
    );
    addTearDown(c.dispose);
    Future<void> save() => c.addExpense(
      period: c.periods.last,
      amount: 51,
      exactAmountMinor: 5055,
      transactionId: 'manual-draft',
      date: DateTime(2026, 10, 5),
      categoryId: 'groceries',
      accountId: 'card',
      title: 'Manual',
    );
    await expectLater(save(), throwsStateError);
    fail = false;
    await save();
    expect(c.transactions.where((t) => t.id == 'manual-draft'), hasLength(1));
    expect(
      c.transactions.firstWhere((t) => t.id == 'manual-draft').amountMinor,
      5055,
    );
  });
}
