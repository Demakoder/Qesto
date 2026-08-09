import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/budget/transaction_details_screen.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

void main() {
  testWidgets('детали расхода показывают магазин и состав чека', (
    tester,
  ) async {
    final period = BudgetPeriod(
      id: 'period',
      userId: 'user',
      startDate: DateTime(2026, 7),
      endDate: DateTime(2026, 7, 31),
      type: BudgetPeriodType.calendarMonth,
      totalPlan: 30000,
      currency: 'RUB',
    );
    final transaction = BudgetTransaction(
      id: 'transaction',
      userId: 'user',
      accountId: 'account',
      date: DateTime(2026, 7, 19, 14, 30),
      amount: 145,
      currency: 'RUB',
      type: TransactionType.expense,
      categoryId: 'groceries',
      merchant: 'АГРОТОРГ',
      receipt: TransactionReceiptDetails(
        id: 'fn:fd:fp',
        merchant: 'АГРОТОРГ',
        purchasedAt: DateTime(2026, 7, 19, 14, 30),
        totalMinor: 14489,
        fiscalDriveNumber: '9282440300999999',
        fiscalDocumentNumber: '654321',
        fiscalSign: '123456789',
        items: const [
          TransactionReceiptItem(name: 'МОЛОКО 3,2%', totalMinor: 8999),
          TransactionReceiptItem(name: 'ХЛЕБ БОРОДИНСКИЙ', totalMinor: 5490),
        ],
      ),
    );
    final controller = BudgetController(
      configuration: budgetConfiguration,
      financialData: UserFinancialData(
        user: const QestoUser(id: 'user', name: 'Тест', defaultCurrency: 'RUB'),
        referenceDate: DateTime(2026, 7, 20),
        accounts: const [
          QestoAccount(
            id: 'account',
            userId: 'user',
            title: 'Карта',
            balance: 1000,
            currency: 'RUB',
            type: AccountType.bankCard,
          ),
        ],
        budgetPeriods: [period],
        transactions: [transaction],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TransactionDetailsScreen(
          controller: controller,
          period: period,
          transactionId: transaction.id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('receipt-items-card')), findsOneWidget);
    expect(find.text('Состав чека'), findsOneWidget);
    expect(find.text('МОЛОКО 3,2%'), findsOneWidget);
    expect(find.text('ХЛЕБ БОРОДИНСКИЙ'), findsOneWidget);
    expect(find.text('144,89 ₽'), findsOneWidget);
  });
}
