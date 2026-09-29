import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/bank_screenshot_import/data/bank_screenshot_scanner_service.dart';
import 'package:qesto/features/bank_screenshot_import/domain/bank_screenshot_models.dart';
import 'package:qesto/features/bank_screenshot_import/presentation/bank_screenshot_import_screen.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  testWidgets(
    'screenshot preview is editable and saves only after confirmation',
    (tester) async {
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'screen-user',
            name: 'Screen user',
            defaultCurrency: 'RUB',
          ),
          referenceDate: DateTime(2026, 8, 31),
          accounts: const [
            QestoAccount(
              id: 'screen-card',
              userId: 'screen-user',
              title: 'Сбер •• 1234',
              balance: 10000,
              currency: 'RUB',
              type: AccountType.bankCard,
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BankScreenshotImportScreen(
            controller: controller,
            scanner: _FakeScanner(),
          ),
        ),
      );

      expect(controller.transactions, isEmpty);
      await tester.tap(find.byKey(const Key('pick-bank-screenshots')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Предпросмотр'), findsOneWidget);
      expect(find.text('PYATEROCHKA'), findsOneWidget);
      expect(controller.transactions, isEmpty);

      await tester.tap(find.byKey(const Key('save-bank-screenshots')));
      await tester.pumpAndSettle();

      expect(controller.transactions, hasLength(1));
      expect(controller.transactions.single.categoryId, 'groceries');
      expect(
        controller.synoballState.evidence.single.sourceType,
        SynoballSourceType.bankScreenshot,
      );
    },
  );
}

class _FakeScanner implements BankScreenshotScannerGateway {
  @override
  bool get isSupported => true;

  @override
  Future<List<ExtractedBankScreenshot>> pickAndRecognize() async => [
    ExtractedBankScreenshot(
      imageHash: 'widget-fixture',
      capturedAt: DateTime(2026, 8, 31),
      lines: const [
        BankScreenshotTextLine(text: 'PYATEROCHKA', top: 10, left: 10),
        BankScreenshotTextLine(text: '499 ₽', top: 10, left: 400),
        BankScreenshotTextLine(
          text: 'Оплата товаров и услуг',
          top: 30,
          left: 10,
        ),
        BankScreenshotTextLine(
          text: 'Платёжный счёт: 9 501 ₽',
          top: 50,
          left: 10,
        ),
      ],
    ),
  ];
}
