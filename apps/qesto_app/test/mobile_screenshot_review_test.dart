import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/bank_screenshot_import/data/bank_screenshot_scanner_service.dart';
import 'package:qesto/features/bank_screenshot_import/domain/bank_screenshot_models.dart';
import 'package:qesto/features/bank_screenshot_import/presentation/bank_screenshot_import_screen.dart';
import 'package:qesto/features/bank_screenshot_import/services/bank_screenshot_import_service.dart';
import 'package:qesto/synoball/core/models.dart';
import 'mobile_transaction_editor_test.dart' show editorBudget;

class ReviewScanner implements BankScreenshotScannerGateway {
  ReviewScanner({this.cancel = false});
  final bool cancel;
  @override
  bool get isSupported => true;
  @override
  Future<List<ExtractedBankScreenshot>> pickAndRecognize() async => cancel
      ? []
      : [
          ExtractedBankScreenshot(
            imageHash: 'review-fixture',
            capturedAt: DateTime(2026, 10, 5),
            lines: const [],
          ),
        ];
}

class ReviewParser extends BankScreenshotImportService {
  const ReviewParser(this.kind);
  final BankScreenshotTransactionKind kind;
  @override
  BankScreenshotParseResult parseAll(
    Iterable<ExtractedBankScreenshot> documents,
  ) => BankScreenshotParseResult(
    warnings: const [],
    candidates: [
      BankScreenshotCandidate(
        id: 'review',
        imageHash: 'review-fixture',
        parserId: 'sber-fixture',
        merchant: 'Контрагент',
        amountMinor: 2037,
        currency: 'RUB',
        date: DateTime(2026, 10, 5, 11),
        kind: kind,
        categoryId: 'groceries',
        confidence: .99,
        accountId: 'card',
        dateOnly: false,
      ),
    ],
  );
}

void main() {
  for (final kind in BankScreenshotTransactionKind.values) {
    testWidgets(
      'screenshot $kind correction is draft-only and preserves type/cents at canonical import',
      (tester) async {
        tester.view
          ..physicalSize = const Size(320, 740)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var fail = false;
        final c = editorBudget(
          onChanged: () async {
            if (fail) throw StateError('disk');
          },
        );
        addTearDown(c.dispose);
        final before = jsonEncode(c.synoballState.toJson());
        await tester.pumpWidget(
          MaterialApp(
            home: BankScreenshotImportScreen(
              controller: c,
              scanner: ReviewScanner(),
              importService: ReviewParser(kind),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('pick-bank-screenshots')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Изменить'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('transaction-amount')),
          '33,17',
        );
        await tester.enterText(
          find.byKey(const Key('transaction-merchant')),
          'Исправленный',
        );
        await tester.tap(find.byKey(const Key('transaction-save')));
        await tester.pumpAndSettle();
        expect(jsonEncode(c.synoballState.toJson()), before);
        expect(find.text('Исправленный'), findsOneWidget);
        final save = find.byKey(const Key('save-bank-screenshots'));
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        fail = true;
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('Не удалось сохранить операции'), findsOneWidget);
        fail = false;
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        final canonical = c.synoballState.transactions.where(
          (t) => t.merchantName == 'Исправленный',
        );
        expect(canonical, hasLength(1));
        expect(canonical.single.amount.minorUnits, 3317);
        expect(canonical.single.tags, contains('legacy-type-${kind.name}'));
        expect(
          canonical.single.direction,
          kind == BankScreenshotTransactionKind.income ||
                  kind == BankScreenshotTransactionKind.refund
              ? FinancialDirection.inflow
              : FinancialDirection.outflow,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
  testWidgets('screenshot picker cancellation does not mutate canonical data', (
    tester,
  ) async {
    final c = editorBudget();
    addTearDown(c.dispose);
    final before = jsonEncode(c.synoballState.toJson());
    await tester.pumpWidget(
      MaterialApp(
        home: BankScreenshotImportScreen(
          controller: c,
          scanner: ReviewScanner(cancel: true),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('pick-bank-screenshots')));
    await tester.pumpAndSettle();
    expect(jsonEncode(c.synoballState.toJson()), before);
    expect(find.byKey(const Key('save-bank-screenshots')), findsNothing);
  });
}
