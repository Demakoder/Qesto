import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/data/repositories/local_qesto_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('unified user data survives a JSON round trip', () {
    final source = UserFinancialData(
      user: const QestoUser(id: 'user-1', name: 'Test', defaultCurrency: 'RUB'),
      referenceDate: DateTime(2026, 8, 9),
      accounts: const [
        QestoAccount(
          id: 'account-1',
          userId: 'user-1',
          title: 'Card',
          balance: 1000,
          currency: 'RUB',
          type: AccountType.bankCard,
        ),
      ],
      transactions: [
        BudgetTransaction(
          id: 'transaction-1',
          userId: 'user-1',
          accountId: 'account-1',
          date: DateTime(2026, 8, 8),
          amount: 500,
          currency: 'RUB',
          type: TransactionType.transfer,
          transferDirection: TransferDirection.incoming,
          tags: const ['statement-import', 'transfer-incoming'],
        ),
      ],
      savingsGoals: [
        SavingsGoal(
          id: 'goal-1',
          userId: 'user-1',
          title: 'Goal',
          targetAmount: 10000,
          savedAmount: 2000,
          currency: 'RUB',
          streakWeeks: 2,
          isActive: true,
          history: [
            SavingsHistoryPoint(date: DateTime(2026, 8, 1), amount: 2000),
          ],
        ),
      ],
      trackedProducts: const [
        TrackedProduct(
          id: 'product-1',
          userId: 'user-1',
          title: 'Product',
          currentPrice: 3000,
          currency: 'RUB',
          bestMarketplace: 'Shop',
          changePercent: -2.5,
          trackedStoresCount: 3,
          visualKey: 'product',
        ),
      ],
      actions: [
        FinancialAction(
          id: 'action-1',
          occurredAt: DateTime(2026, 8, 9, 12),
          title: 'Statement import',
          type: FinancialActionType.statementImport,
          createdTransactionIds: const ['transaction-1'],
        ),
      ],
    );

    const codec = UserFinancialDataCodec();
    final restored = codec.decode(codec.encode(source));

    expect(restored.user.id, source.user.id);
    expect(restored.accounts.single.type, AccountType.bankCard);
    expect(restored.transactions.single.type, TransactionType.transfer);
    expect(
      restored.transactions.single.transferDirection,
      TransferDirection.incoming,
    );
    expect(restored.savingsGoals.single.savedAmount, 2000);
    expect(restored.trackedProducts.single.changePercent, -2.5);
    expect(restored.actions.single.title, 'Statement import');
  });

  test('local repository restores data after an app restart', () async {
    SharedPreferences.setMockInitialValues({});
    final source = UserFinancialData(
      user: const QestoUser(id: 'user-1', name: 'Test', defaultCurrency: 'RUB'),
      referenceDate: DateTime(2026, 8, 9),
      transactions: [
        BudgetTransaction(
          id: 'imported-operation',
          userId: 'user-1',
          accountId: 'account-1',
          date: DateTime(2026, 8, 8),
          amount: 8499,
          currency: 'RUB',
          type: TransactionType.expense,
          tags: const ['statement-import'],
        ),
      ],
    );

    await LocalQestoRepository().saveUserFinancialData(source);
    final restored = await LocalQestoRepository().getUserFinancialData();

    expect(restored.transactions.single.id, 'imported-operation');
    expect(restored.transactions.single.tags, ['statement-import']);
  });
}
