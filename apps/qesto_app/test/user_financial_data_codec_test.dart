import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/data/repositories/local_qesto_repository.dart';
import 'package:qesto/features/benefits/data/deals_api_client.dart';
import 'package:qesto/features/benefits/data/deals_cache.dart';

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
      accountPreferences: const [
        QestoAccountPreferences(
          accountId: 'account-1',
          role: QestoAccountRole.salary,
          includeInEmergencyFund: true,
        ),
      ],
      categoryCustomizations: const [
        BudgetCategoryCustomization(
          categoryId: 'groceries',
          name: 'Еда домой',
          iconKey: 'cart',
          colorValue: 0xFF2EC4B6,
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
          receipt: TransactionReceiptDetails(
            id: 'fn:fd:fp',
            purchasedAt: DateTime(2026, 8, 8, 14, 30),
            totalMinor: 50000,
            fiscalDriveNumber: '9282440300999999',
            fiscalDocumentNumber: '12345',
            fiscalSign: '987654321',
            merchant: 'Тестовый магазин',
            items: const [
              TransactionReceiptItem(
                name: 'Тестовый товар',
                quantity: 2,
                unitPriceMinor: 25000,
                totalMinor: 50000,
              ),
            ],
          ),
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
          category: 'Путешествие',
          type: GoalType.targetAmountDate,
          targetDate: DateTime(2027, 6, 1),
          comment: 'Первый отпуск',
          desiredMonthlyContribution: 1000,
          priority: GoalPriority.high,
          reminder: const GoalReminder(enabled: true, amount: 1000, day: 12),
        ),
      ],
      goalAllocations: [
        GoalAllocation(
          id: 'allocation-1',
          goalId: 'goal-1',
          sourceType: GoalAllocationSourceType.account,
          sourceId: 'account-1',
          allocatedAmount: 2000,
          currency: 'RUB',
          updatedAt: DateTime(2026, 8, 9),
        ),
      ],
      goalContributions: [
        GoalContribution(
          id: 'goal-contribution-1',
          goalId: 'goal-1',
          date: DateTime(2026, 8, 5),
          amount: 1000,
          currency: 'RUB',
          type: GoalContributionType.contribution,
          source: GoalContributionSource.manual,
          createdAt: DateTime(2026, 8, 5),
        ),
      ],
      goalHistoryEvents: [
        GoalHistoryEvent(
          id: 'goal-event-1',
          goalId: 'goal-1',
          type: GoalHistoryEventType.created,
          date: DateTime(2026, 8, 1),
          description: 'Цель создана',
          amount: 10000,
        ),
      ],
      investmentAccounts: [
        InvestmentAccount(
          id: 'investment-1',
          userId: 'user-1',
          linkedAccountId: 'investment-account-1',
          name: 'Брокер',
          type: InvestmentAccountType.iis,
          currency: 'RUB',
          currentBalance: 50000,
          status: InvestmentAccountStatus.active,
          source: InvestmentDataSource.manual,
          createdAt: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 9),
          lastBalanceUpdateAt: DateTime(2026, 8, 9),
          plan: const InvestmentPlan(amount: 10000, preferredDay: 12),
        ),
      ],
      investmentBalanceSnapshots: [
        InvestmentBalanceSnapshot(
          id: 'investment-snapshot-1',
          investmentAccountId: 'investment-1',
          date: DateTime(2026, 8, 9),
          balance: 50000,
          currency: 'RUB',
          source: InvestmentDataSource.manual,
          createdAt: DateTime(2026, 8, 9),
        ),
      ],
      investmentContributions: [
        InvestmentContribution(
          id: 'investment-contribution-1',
          investmentAccountId: 'investment-1',
          date: DateTime(2026, 8, 5),
          amount: 10000,
          currency: 'RUB',
          type: InvestmentContributionType.contribution,
          source: InvestmentDataSource.manual,
          createdAt: DateTime(2026, 8, 5),
        ),
      ],
      debts: [
        DebtAccount(
          id: 'debt-1',
          userId: 'user-1',
          name: 'Credit card',
          type: DebtType.creditCard,
          currency: 'RUB',
          currentBalance: 15000,
          status: DebtStatus.active,
          source: DebtSource.manual,
          dataQuality: DebtDataQuality.manual,
          confidence: 1,
          createdAt: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 9),
          creditCardDetails: CreditCardDebtDetails(
            creditLimit: 100000,
            minimumPayment: 1500,
            graceDeadline: DateTime(2026, 8, 25),
          ),
        ),
      ],
      debtBalanceSnapshots: [
        DebtBalanceSnapshot(
          id: 'snapshot-1',
          debtId: 'debt-1',
          date: DateTime(2026, 8, 9),
          totalBalance: 15000,
          source: DebtSource.manual,
          confidence: 1,
        ),
      ],
      debtPayments: [
        DebtPayment(
          id: 'payment-1',
          debtId: 'debt-1',
          date: DateTime(2026, 8, 8),
          amount: 1500,
          currency: 'RUB',
          source: DebtSource.manual,
          confidence: 1,
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
    expect(restored.accountPreferences.single.role, QestoAccountRole.salary);
    expect(restored.accountPreferences.single.includeInEmergencyFund, isTrue);
    expect(restored.transactions.single.type, TransactionType.transfer);
    expect(
      restored.transactions.single.transferDirection,
      TransferDirection.incoming,
    );
    expect(restored.savingsGoals.single.savedAmount, 2000);
    expect(restored.savingsGoals.single.type, GoalType.targetAmountDate);
    expect(restored.goalContributions.single.amount, 1000);
    expect(
      restored.goalHistoryEvents.single.type,
      GoalHistoryEventType.created,
    );
    expect(restored.investmentAccounts.single.type, InvestmentAccountType.iis);
    expect(restored.investmentAccounts.single.plan?.amount, 10000);
    expect(restored.investmentBalanceSnapshots.single.balance, 50000);
    expect(restored.investmentContributions.single.amount, 10000);
    expect(restored.savingsGoals.single.priority, GoalPriority.high);
    expect(restored.savingsGoals.single.reminder?.day, 12);
    expect(restored.goalAllocations.single.allocatedAmount, 2000);
    expect(restored.debts.single.type, DebtType.creditCard);
    expect(restored.debts.single.creditCardDetails?.creditLimit, 100000);
    expect(restored.debtBalanceSnapshots.single.totalBalance, 15000);
    expect(restored.debtPayments.single.amount, 1500);
    expect(restored.trackedProducts.single.changePercent, -2.5);
    expect(restored.actions.single.title, 'Statement import');
    expect(restored.transactions.single.receipt?.merchant, 'Тестовый магазин');
    expect(
      restored.transactions.single.receipt?.items.single.name,
      'Тестовый товар',
    );
    expect(restored.transactions.single.receipt?.items.single.quantity, 2);
    expect(restored.categoryCustomizations.single.name, 'Еда домой');
    expect(restored.categoryCustomizations.single.colorValue, 0xFF2EC4B6);
  });

  test('local repository restores data after an app restart', () async {
    final store = MemoryKeyValueStore();
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

    await LocalQestoRepository(store: store).saveUserFinancialData(source);
    final restored = await LocalQestoRepository(
      store: store,
    ).getUserFinancialData();

    expect(restored.transactions.single.id, 'imported-operation');
    expect(restored.transactions.single.tags, ['statement-import']);
    final today = DateTime.now();
    expect(
      restored.referenceDate,
      DateTime(today.year, today.month, today.day),
      reason: 'analytics must not reuse the previous launch date',
    );
  });

  test('local repository deletes only private financial data', () async {
    final store = MemoryKeyValueStore();
    final repository = LocalQestoRepository(store: store);
    final source = UserFinancialData(
      user: const QestoUser(id: 'user-1', name: 'Test', defaultCurrency: 'RUB'),
      referenceDate: DateTime(2026, 8, 13),
      transactions: [
        BudgetTransaction(
          id: 'private-operation',
          userId: 'user-1',
          accountId: 'account-1',
          date: DateTime(2026, 8, 12),
          amount: 100,
          currency: 'RUB',
          type: TransactionType.expense,
        ),
      ],
    );

    await repository.saveUserFinancialData(source);
    await repository.deleteUserFinancialData();
    final restored = await repository.getUserFinancialData();

    expect(restored.transactions, isEmpty);
    expect(restored.accounts, isEmpty);
    expect(restored.synoballState, isNull);
  });

  test('public deals use a separate non-sensitive cache', () async {
    final financialStore = MemoryKeyValueStore();
    final publicStore = MemoryKeyValueStore({
      publicDealsCacheKey: '''
        {"offers":[{"id":"cached-deal","type":"promotion","title":"Кэш"}]}
      ''',
    });
    final repository = LocalQestoRepository(
      store: financialStore,
      publicStore: publicStore,
      dealsApiClient: DealsApiClient(
        baseUrl: 'http://deals.test',
        client: MockClient((_) async => http.Response('unavailable', 503)),
      ),
    );

    final deals = await repository.getPromotions();

    expect(deals.single.id, 'cached-deal');
    expect(await financialStore.readString(publicDealsCacheKey), isNull);
  });
}
