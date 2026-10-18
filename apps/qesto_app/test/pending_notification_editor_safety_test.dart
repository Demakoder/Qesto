import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/budget/transaction_editor_screen.dart';
import 'package:qesto/features/notification_import/data/notification_capture_service.dart';
import 'package:qesto/features/notification_import/domain/parsed_bank_transaction.dart';
import 'package:qesto/features/notification_import/presentation/notification_import_screen.dart';
import 'package:qesto/features/notification_import/services/bank_notification_parser.dart';
import 'package:qesto/synoball/core/models.dart';

import 'mobile_transaction_editor_test.dart' show editorBudget;

class SafetyCapture extends NotificationCaptureService {
  SafetyCapture();
  final items = [
    CapturedNotification(
      packageName: 'ru.sberbankmobile',
      notificationKey: 'safety-slot',
      deliveryVersion: 'v1',
      postedAt: DateTime(2026, 10, 5, 12),
      title: 'Сбер',
      text: 'Original banking evidence',
    ),
  ];
  bool rejectAck = false;
  @override
  Future<List<CapturedNotification>> readNotifications() async =>
      List.of(items);
  @override
  Future<void> removeNotification(
    String key, {
    required String expectedVersion,
  }) async {
    if (rejectAck) {
      rejectAck = false;
      throw StateError('ack failed');
    }
    items.removeWhere(
      (n) => n.notificationKey == key && n.deliveryVersion == expectedVersion,
    );
  }
}

class SafetyParser implements BankNotificationParser {
  const SafetyParser(this.kind, this.minor);
  final ParsedBankTransactionKind kind;
  final int minor;
  @override
  ParsedBankTransaction parse(CapturedNotification n) => ParsedBankTransaction(
    notificationKey: n.notificationKey,
    sourcePackage: n.packageName,
    date: n.postedAt,
    amountMinor: minor,
    currency: 'RUB',
    merchant: 'Контрагент',
    categoryId: 'groceries',
    confidence: .9,
    kind: kind,
    accountHint: 'card',
    bankHint: 'sber',
  );
}

void main() {
  for (final kind in ParsedBankTransactionKind.values) {
    for (final minor in [10000, 10037]) {
      testWidgets(
        'pending $kind $minor correction preserves canonical type, cents and provenance',
        (tester) async {
          final budget = editorBudget();
          addTearDown(budget.dispose);
          final capture = SafetyCapture();
          final before = jsonEncode(budget.synoballState.toJson());
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              home: NotificationImportScreen(
                controller: budget,
                captureService: capture,
                parser: SafetyParser(kind, minor),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Изменить'));
          await tester.pumpAndSettle();
          expect(find.byType(TransactionEditorScreen), findsOneWidget);
          expect(
            tester
                .widget<TextFormField>(
                  find.byKey(const Key('transaction-amount')),
                )
                .controller!
                .text,
            minorAmountInput(minor),
          );
          await tester.enterText(
            find.byKey(const Key('transaction-merchant')),
            'Исправленный контрагент',
          );
          await tester.enterText(
            find.byKey(const Key('transaction-amount')),
            '123,45',
          );
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
          await tester.tap(find.byKey(const Key('transaction-save')));
          await tester.pumpAndSettle();
          expect(capture.items, hasLength(1));
          expect(jsonEncode(budget.synoballState.toJson()), before);
          await tester.tap(find.text('Добавить'));
          await tester.pumpAndSettle();
          final canonical = budget.synoballState.transactions
              .where((t) => t.id != 'operation')
              .single;
          expect(canonical.amount.minorUnits, 12345);
          expect(canonical.merchantName, 'Исправленный контрагент');
          expect(canonical.accountId, 'savings');
          expect(canonical.effectiveCategory, 'cafes');
          final legacyType = switch (kind) {
            ParsedBankTransactionKind.expense => 'expense',
            ParsedBankTransactionKind.income => 'income',
            ParsedBankTransactionKind.refund => 'refund',
            ParsedBankTransactionKind.transfer => 'transfer',
          };
          expect(canonical.tags, contains('legacy-type-$legacyType'));
          expect(
            canonical.direction,
            kind == ParsedBankTransactionKind.income ||
                    kind == ParsedBankTransactionKind.refund
                ? FinancialDirection.inflow
                : FinancialDirection.outflow,
          );
          expect(
            canonical.transferDirection,
            kind == ParsedBankTransactionKind.transfer ? 'outgoing' : null,
          );
          expect(
            budget.synoballState.evidence
                .where((e) => e.transactionId == canonical.id)
                .single
                .sourceType,
            SynoballSourceType.androidNotification,
          );
          expect(capture.items, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'discard correction leaves notification/periods/ledger unchanged',
    (tester) async {
      final budget = editorBudget();
      addTearDown(budget.dispose);
      final capture = SafetyCapture();
      final before = jsonEncode(budget.synoballState.toJson());
      final periodCount = budget.periods.length;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationImportScreen(
            controller: budget,
            captureService: capture,
            parser: const SafetyParser(ParsedBankTransactionKind.income, 10037),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Изменить'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('transaction-merchant')),
        'Discard me',
      );
      await tester.tap(find.byKey(const Key('transaction-editor-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Не сохранять'));
      await tester.pumpAndSettle();
      expect(capture.items, hasLength(1));
      expect(budget.periods, hasLength(periodCount));
      expect(jsonEncode(budget.synoballState.toJson()), before);
    },
  );
  for (final failSave in [false, true]) {
    testWidgets(
      'corrected notification retry never duplicates (storage failure=$failSave)',
      (tester) async {
        var reject = failSave;
        final budget = editorBudget(
          onChanged: () async {
            if (reject) {
              reject = false;
              throw StateError('storage failure');
            }
          },
        );
        addTearDown(budget.dispose);
        final capture = SafetyCapture()..rejectAck = !failSave;
        await tester.pumpWidget(
          MaterialApp(
            home: NotificationImportScreen(
              controller: budget,
              captureService: capture,
              parser: const SafetyParser(
                ParsedBankTransactionKind.refund,
                10037,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Изменить'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('transaction-amount')),
          '100,55',
        );
        await tester.tap(find.byKey(const Key('transaction-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Добавить'));
        await tester.pumpAndSettle();
        expect(capture.items, hasLength(1));
        await tester.tap(find.text('Добавить'));
        await tester.pumpAndSettle();
        expect(capture.items, isEmpty);
        expect(budget.synoballState.transactions, hasLength(2));
        expect(
          budget.synoballState.transactions
              .where((t) => t.id != 'operation')
              .single
              .amount
              .minorUnits,
          10055,
        );
      },
    );
  }
}
