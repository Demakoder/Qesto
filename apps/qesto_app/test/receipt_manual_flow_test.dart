import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/receipt_import/presentation/receipt_import_screen.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  testWidgets('manual fiscal QR creates a canonical receipt transaction', (
    tester,
  ) async {
    final controller = BudgetController(
      configuration: budgetConfiguration,
      financialData: UserFinancialData(
        user: const QestoUser(
          id: 'receipt-user',
          name: 'Receipt test',
          defaultCurrency: 'RUB',
        ),
        referenceDate: DateTime(2026, 8, 13),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: ReceiptImportScreen(controller: controller)),
    );

    await tester.enterText(
      find.byKey(const Key('manual-receipt-qr')),
      't=20260813T1430&s=1250.50&fn=9282440300999999&'
      'i=123456&fp=987654321&n=1',
    );
    await tester.tap(find.byKey(const Key('parse-manual-receipt-qr')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Перекрёсток');
    await tester.tap(find.byKey(const Key('save-receipt')));
    await tester.pumpAndSettle();

    expect(controller.transactions, hasLength(1));
    expect(controller.transactions.single.amount, 1251);
    expect(controller.transactions.single.receipt, isNotNull);
    final canonical = controller.synoballState.transactions.single;
    expect(
      controller.synoballState.evidence.single.sourceType,
      SynoballSourceType.receipt,
    );
    expect(canonical.receiptId, isNotNull);
    expect(controller.synoballState.rawPayloads, isNotEmpty);
    expect(controller.synoballState.evidence, isNotEmpty);
  });
}
