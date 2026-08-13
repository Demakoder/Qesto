import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/statistics/domain/services/data_quality_service.dart';
import 'package:qesto/features/statistics/domain/services/statistics_calculation_service.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

void main() {
  BudgetController buildController() => BudgetController(
    configuration: budgetConfiguration,
    financialData: UserFinancialData(
      user: const QestoUser(id: 'user-1', name: 'Test', defaultCurrency: 'RUB'),
      referenceDate: DateTime(2026, 8, 9),
    ),
  );

  test(
    'statement import creates an account and can be undone as one action',
    () async {
      final controller = buildController();
      final periodIdsBefore = controller.periods.map((item) => item.id).toSet();
      final period = controller.periodForOrCreate(DateTime(2026, 5, 1));
      const account = QestoAccount(
        id: 'sber-account-2345',
        userId: 'user-1',
        title: 'Счёт Сбербанка • 2345',
        balance: 6010,
        currency: 'RUB',
        type: AccountType.bankCard,
      );
      final transaction = BudgetTransaction(
        id: 'sber-operation-1',
        userId: 'user-1',
        accountId: account.id,
        date: DateTime(2026, 5, 1),
        amount: 500,
        currency: 'RUB',
        type: TransactionType.transfer,
        transferDirection: TransferDirection.incoming,
        classificationConfidence: 0.55,
      );

      final imported = await controller.importStatement(
        account: account,
        transactions: [transaction],
        createdPeriodIds: controller.periods
            .map((item) => item.id)
            .where((id) => !periodIdsBefore.contains(id))
            .toSet(),
        actionTitle: 'Импорт выписки',
      );

      expect(imported, 1);
      expect(controller.accounts.single.id, account.id);
      expect(controller.accounts.single.balance, 6010);
      expect(controller.transactions.single.accountId, account.id);
      expect(
        controller.actions.single.type,
        FinancialActionType.statementImport,
      );

      expect(await controller.undoAction(controller.actions.single.id), isTrue);
      expect(controller.transactions, isEmpty);
      expect(controller.accounts.single.id, 'local-default-account');
      expect(controller.periods.any((item) => item.id == period.id), isFalse);
      expect(controller.actions.single.isUndone, isTrue);
    },
  );

  test('known transfers are not reported as low-confidence purchases', () {
    const quality = DataQualityService();
    final report = quality.evaluate(
      transactions: [
        BudgetTransaction(
          id: 'transfer-1',
          userId: 'user-1',
          accountId: 'account-1',
          date: DateTime(2026, 8, 9),
          amount: 500,
          currency: 'RUB',
          type: TransactionType.transfer,
          transferDirection: TransferDirection.outgoing,
          classificationConfidence: 0.1,
        ),
      ],
      accountIds: {'account-1'},
    );

    expect(report.issues, isEmpty);
    expect(report.score, 100);
  });

  test(
    'reimport migrates previously saved operations to the statement account',
    () async {
      final oldTransaction = BudgetTransaction(
        id: 'sber-operation-1',
        userId: 'user-1',
        accountId: 'local-default-account',
        date: DateTime(2026, 8, 8),
        amount: 500,
        currency: 'RUB',
        type: TransactionType.transfer,
        transferDirection: TransferDirection.incoming,
      );
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'user-1',
            name: 'Test',
            defaultCurrency: 'RUB',
          ),
          referenceDate: DateTime(2026, 8, 9),
          transactions: [oldTransaction],
        ),
      );
      const account = QestoAccount(
        id: 'sber-account-2345',
        userId: 'user-1',
        title: 'Счёт Сбербанка • 2345',
        balance: 6010,
        currency: 'RUB',
        type: AccountType.bankCard,
      );
      final updatedTransaction = oldTransaction.copyWith(accountId: account.id);

      await controller.importStatement(
        account: account,
        transactions: [updatedTransaction],
        createdPeriodIds: const {},
        actionTitle: 'Обновление выписки',
      );

      expect(controller.transactions.single.accountId, account.id);
      expect(controller.accounts.single.id, account.id);
      expect(controller.actions.single.previousTransactions, [oldTransaction]);

      await controller.undoAction(controller.actions.single.id);
      expect(controller.transactions.single.accountId, 'local-default-account');
      expect(controller.accounts.single.id, 'local-default-account');
    },
  );

  test(
    'Excel capital allocations create assets without becoming expenses',
    () async {
      final controller = buildController();
      const sourceAccount = QestoAccount(
        id: 'excel-account',
        userId: 'user-1',
        title: 'Импорт из Excel',
        balance: 0,
        currency: 'RUB',
        type: AccountType.other,
      );
      const cryptoAccount = QestoAccount(
        id: 'excel-capital-crypto',
        userId: 'user-1',
        title: 'Крипта',
        balance: 198591,
        currency: 'RUB',
        type: AccountType.investment,
      );
      final allocation = BudgetTransaction(
        id: 'excel-crypto-allocation',
        userId: 'user-1',
        accountId: sourceAccount.id,
        date: DateTime(2025, 1),
        amount: 198591,
        currency: 'RUB',
        type: TransactionType.investment,
        categoryId: 'other',
        tags: const ['statement-import', 'excel-capital-allocation'],
      );

      await controller.importStatement(
        account: sourceAccount,
        additionalAccounts: const [cryptoAccount],
        transactions: [allocation],
        createdPeriodIds: const {},
        actionTitle: 'Импорт Excel',
      );

      final importedCapital = controller.accounts.firstWhere(
        (item) => item.id == cryptoAccount.id,
      );
      expect(importedCapital.title, 'Крипта');
      expect(importedCapital.balance, 198591);
      expect(importedCapital.type, AccountType.investment);
      expect(
        const StatisticsCalculationService().expenses(controller.transactions),
        0,
      );
      expect(controller.transactions.single.type, TransactionType.investment);
    },
  );

  test(
    'Excel reimport replaces the old expense meaning with investment',
    () async {
      final oldExpense = BudgetTransaction(
        id: 'excel-crypto-allocation',
        userId: 'user-1',
        accountId: 'excel-account',
        date: DateTime(2000, 1),
        amount: 198591,
        currency: 'RUB',
        type: TransactionType.expense,
        categoryId: 'other',
        tags: const ['statement-import', 'excel-import'],
      );
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'user-1',
            name: 'Test',
            defaultCurrency: 'RUB',
          ),
          referenceDate: DateTime(2026, 8, 9),
          accounts: const [
            QestoAccount(
              id: 'excel-account',
              userId: 'user-1',
              title: 'Импорт из Excel',
              balance: 0,
              currency: 'RUB',
              type: AccountType.other,
            ),
          ],
          transactions: [oldExpense],
        ),
      );
      final refreshed = oldExpense.copyWith(
        date: DateTime(2025, 1),
        type: TransactionType.investment,
        tags: const [
          'statement-import',
          'excel-import',
          'excel-capital-allocation',
        ],
      );

      await controller.importStatement(
        account: controller.accounts.single,
        transactions: [refreshed],
        createdPeriodIds: const {},
        actionTitle: 'Обновление Excel',
      );

      expect(controller.transactions.single.type, TransactionType.investment);
      expect(controller.transactions.single.date, DateTime(2025, 1));
      expect(
        controller.transactions.single.tags.where(
          (tag) => tag.startsWith('legacy-type-'),
        ),
        ['legacy-type-investment'],
      );
      expect(controller.actions.single.previousTransactions, hasLength(1));

      await controller.undoAction(controller.actions.single.id);
      expect(controller.transactions.single.type, TransactionType.expense);
      expect(controller.transactions.single.date, DateTime(2000, 1));
    },
  );
}
