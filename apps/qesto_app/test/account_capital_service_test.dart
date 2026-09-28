import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/services/cash_flow_calculation_service.dart';
import 'package:qesto/features/capital/domain/account_capital_service.dart';
import 'package:qesto/synoball/core/models.dart';

void main() {
  const service = AccountCapitalService();
  final asOf = DateTime(2026, 9, 2);

  QestoAccount account(
    String id,
    int balance, {
    AccountType type = AccountType.bankCard,
    String currency = 'RUB',
  }) => QestoAccount(
    id: id,
    userId: 'user-1',
    title: id,
    balance: balance,
    currency: currency,
    type: type,
  );

  BudgetTransaction transaction({
    required String id,
    required String accountId,
    required DateTime date,
    required int amount,
    required TransactionType type,
    TransferDirection? transferDirection,
    String? categoryId,
    String currency = 'RUB',
    List<String> tags = const [],
  }) => BudgetTransaction(
    id: id,
    userId: 'user-1',
    accountId: accountId,
    date: date,
    amount: amount,
    currency: currency,
    type: type,
    transferDirection: transferDirection,
    categoryId: categoryId,
    tags: tags,
  );

  AccountCapitalSnapshot calculate({
    required List<QestoAccount> accounts,
    List<QestoAccountPreferences> preferences = const [],
    List<BudgetTransaction> transactions = const [],
    List<SavingsGoal> goals = const [],
    List<GoalAllocation> goalAllocations = const [],
    List<DebtAccount> debts = const [],
    CapitalPeriod period = CapitalPeriod.oneMonth,
  }) => service.calculate(
    accounts: accounts,
    accountPreferences: preferences,
    transactions: transactions,
    upcomingExpenses: const [],
    savingsGoals: goals,
    goalAllocations: goalAllocations,
    debts: debts,
    synoballState: const SynoballState(),
    asOf: asOf,
    period: period,
    baseCurrency: 'RUB',
  );

  test('internal transfer does not change aggregate liquid balance trend', () {
    final result = calculate(
      accounts: [account('sber', 40000), account('tbank', 50000)],
      transactions: [
        transaction(
          id: 'transfer-out',
          accountId: 'sber',
          date: DateTime(2026, 8, 20),
          amount: 50000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.outgoing,
        ),
        transaction(
          id: 'transfer-in',
          accountId: 'tbank',
          date: DateTime(2026, 8, 20),
          amount: 50000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.incoming,
        ),
        transaction(
          id: 'shop',
          accountId: 'sber',
          date: DateTime(2026, 8, 25),
          amount: 10000,
          type: TransactionType.expense,
          categoryId: 'groceries',
        ),
      ],
    );

    expect(result.totalLiquidAssets, 90000);
    expect(result.change, -10000);
    expect(result.history.first.balance, 100000);
    expect(result.history.last.balance, 90000);
    expect(result.accounts.first.internalTransfers, -50000);
    expect(result.accounts.last.internalTransfers, 50000);
  });

  test('one expense reconstructs the balance before it from current cash', () {
    final result = calculate(
      accounts: [account('card', 14144)],
      transactions: [
        transaction(
          id: 'expense',
          accountId: 'card',
          date: DateTime(2026, 8, 30),
          amount: 11000,
          type: TransactionType.expense,
        ),
      ],
    );

    expect(result.history.first.date, DateTime(2026, 8, 29));
    expect(result.history.first.balance, 25144);
    expect(result.history.last.balance, result.totalLiquidAssets);
    expect(result.change, -11000);
  });

  test('one income has a lower preceding end-of-day balance', () {
    final result = calculate(
      accounts: [account('card', 14144)],
      transactions: [
        transaction(
          id: 'income',
          accountId: 'card',
          date: DateTime(2026, 9),
          amount: 5000,
          type: TransactionType.income,
        ),
      ],
    );

    expect(result.history.first.balance, 9144);
    expect(result.history.last.balance, 14144);
  });

  test('daily history combines same-day movements and carries quiet days', () {
    final result = calculate(
      accounts: [account('card', 13000)],
      transactions: [
        transaction(
          id: 'income',
          accountId: 'card',
          date: DateTime(2026, 8, 29, 9),
          amount: 6000,
          type: TransactionType.income,
        ),
        transaction(
          id: 'expense-1',
          accountId: 'card',
          date: DateTime(2026, 8, 29, 12),
          amount: 1000,
          type: TransactionType.expense,
        ),
        transaction(
          id: 'expense-2',
          accountId: 'card',
          date: DateTime(2026, 8, 29, 18),
          amount: 2000,
          type: TransactionType.expense,
        ),
      ],
    );

    expect(result.history.map((point) => point.balance), [
      10000,
      13000,
      13000,
      13000,
      13000,
      13000,
    ]);
    expect(result.history.first.date, DateTime(2026, 8, 28));
  });

  test('paired own-account transfers conserve combined daily liquidity', () {
    final result = calculate(
      accounts: [account('sber', 4000), account('tbank', 10000)],
      transactions: [
        transaction(
          id: 'out',
          accountId: 'sber',
          date: DateTime(2026, 8, 30),
          amount: 10000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.outgoing,
          tags: const [qestoInternalTransferTag],
        ),
        transaction(
          id: 'in',
          accountId: 'tbank',
          date: DateTime(2026, 8, 30),
          amount: 10000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.incoming,
          tags: const [qestoInternalTransferTag],
        ),
      ],
    );

    expect(result.history.map((point) => point.balance).toSet(), {14000});
    expect(result.history.last.balance, 14000);
  });

  test('a one-sided internal debit reduces observed aggregate liquidity', () {
    final result = calculate(
      accounts: [account('card', 4000)],
      transactions: [
        transaction(
          id: 'transfer-out',
          accountId: 'sber-unassigned-RUB',
          date: DateTime(2026, 8, 30),
          amount: 10000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.outgoing,
          tags: const [qestoInternalTransferTag],
        ),
      ],
    );

    expect(result.history.first.balance, 14000);
    expect(result.history.last.balance, 4000);
    expect(result.change, -10000);
  });

  test('empty account history has only the current confirmed balance', () {
    final result = calculate(accounts: [account('card', 14144)]);

    expect(result.history, hasLength(1));
    expect(result.history.single.balance, 14144);
    expect(result.history.single.isConfirmed, isTrue);
    expect(result.change, isNull);
  });

  test(
    'unresolved bank rows participate in aggregate but not account history',
    () {
      final result = calculate(
        accounts: [account('card', 14144)],
        transactions: [
          transaction(
            id: 'unresolved',
            accountId: 'sber-unassigned-RUB',
            date: DateTime(2026, 8, 30),
            amount: 11000,
            type: TransactionType.expense,
            tags: const ['sber-account-unresolved'],
          ),
        ],
      );

      expect(result.unlinkedTransactionCount, 1);
      expect(result.totalLiquidAssets, 14144);
      expect(result.history.first.balance, 25144);
      expect(result.history.last.balance, 14144);
      expect(result.accounts.single.history.single.balance, 14144);
    },
  );

  test(
    'unresolved and resolved account IDs have the same aggregate effect',
    () {
      List<BudgetTransaction> movements(String accountId, List<String> tags) =>
          [
            transaction(
              id: 'income',
              accountId: accountId,
              date: DateTime(2026, 8, 29),
              amount: 3000,
              type: TransactionType.income,
              tags: tags,
            ),
            transaction(
              id: 'expense-1',
              accountId: accountId,
              date: DateTime(2026, 8, 30),
              amount: 5000,
              type: TransactionType.expense,
              tags: tags,
            ),
            transaction(
              id: 'expense-2',
              accountId: accountId,
              date: DateTime(2026, 9, 1),
              amount: 2000,
              type: TransactionType.expense,
              tags: tags,
            ),
          ];
      final unresolved = calculate(
        accounts: [account('card', 14000)],
        transactions: movements('sber-unassigned-RUB', const [
          'sber-account-unresolved',
        ]),
      );
      final resolved = calculate(
        accounts: [account('card', 14000)],
        transactions: movements('card', const []),
      );

      expect(unresolved.unlinkedTransactionCount, 3);
      expect(unresolved.totalLiquidAssets, 14000);
      expect(unresolved.history.first.date, DateTime(2026, 8, 28));
      expect(unresolved.history.map((point) => point.balance), [
        18000,
        21000,
        16000,
        16000,
        14000,
        14000,
      ]);
      expect(
        resolved.history.map((point) => point.balance),
        unresolved.history.map((point) => point.balance),
      );
      expect(unresolved.history.last.isConfirmed, isTrue);
      expect(unresolved.accounts.single.history.single.balance, 14000);
    },
  );

  test('pending unresolved rows are not treated as cash movements', () {
    final result = calculate(
      accounts: [account('card', 14000)],
      transactions: [
        transaction(
          id: 'pending',
          accountId: 'sber-unassigned-RUB',
          date: DateTime(2026, 9, 1),
          amount: 5000,
          type: TransactionType.expense,
          tags: const ['sber-account-unresolved', 'sber-status-pending'],
        ),
      ],
    );

    expect(result.history.single.balance, 14000);
    expect(result.isHistoryReconstructed, isFalse);
  });

  test('known non-liquid account movements stay outside the liquid anchor', () {
    final result = calculate(
      accounts: [
        account('card', 14000),
        account('broker', 100000, type: AccountType.investment),
      ],
      transactions: [
        transaction(
          id: 'broker-fee',
          accountId: 'broker',
          date: DateTime(2026, 9, 1),
          amount: 5000,
          type: TransactionType.expense,
        ),
        transaction(
          id: 'unresolved-card-purchase',
          accountId: 'sber-unassigned-RUB',
          date: DateTime(2026, 9, 1),
          amount: 2000,
          type: TransactionType.expense,
          tags: const ['sber-account-unresolved'],
        ),
      ],
    );

    expect(result.totalLiquidAssets, 14000);
    expect(result.history.first.balance, 16000);
    expect(result.history.last.balance, 14000);
  });

  test(
    'period selectors restrict one reconstruction to available coverage',
    () {
      final transactions = [
        transaction(
          id: 'old-expense',
          accountId: 'card',
          date: DateTime(2026, 5, 2),
          amount: 1000,
          type: TransactionType.expense,
        ),
        transaction(
          id: 'recent-income',
          accountId: 'card',
          date: DateTime(2026, 8, 30),
          amount: 5000,
          type: TransactionType.income,
        ),
      ];
      for (final period in CapitalPeriod.values) {
        final result = calculate(
          accounts: [account('card', 14000)],
          transactions: transactions,
          period: period,
        );
        expect(result.history.last.balance, 14000, reason: period.name);
        expect(result.history.last.date, asOf, reason: period.name);
        expect(
          result.history.first.balance,
          period == CapitalPeriod.oneMonth ||
                  period == CapitalPeriod.threeMonths
              ? 9000
              : 10000,
          reason: period.name,
        );
      }
    },
  );

  test('external person transfers change liquid capital and account flow', () {
    final result = calculate(
      accounts: [account('card', 16000)],
      transactions: [
        transaction(
          id: 'person-in',
          accountId: 'card',
          date: DateTime(2026, 8, 20),
          amount: 10000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.incoming,
          tags: const [qestoExternalTransferTag],
        ),
        transaction(
          id: 'person-out',
          accountId: 'card',
          date: DateTime(2026, 8, 25),
          amount: 4000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.outgoing,
          tags: const [qestoExternalTransferTag],
        ),
      ],
    );

    expect(result.change, 6000);
    expect(result.history.first.balance, 10000);
    expect(result.accounts.single.inflow, 10000);
    expect(result.accounts.single.outflow, 4000);
    expect(result.accounts.single.internalTransfers, 0);
  });

  test('liquid currencies are converted while investments are excluded', () {
    final result = calculate(
      accounts: [
        account('rub', 1000),
        account('usd', 10, currency: 'USD'),
        account('broker', 500000, type: AccountType.investment),
      ],
    );

    expect(result.totalLiquidAssets, 1829);
    expect(result.excludedNonLiquidAccounts, 1);
    expect(result.hasUnconvertedCurrencies, isFalse);
  });

  test('closed and excluded accounts do not inflate available money', () {
    final result = calculate(
      accounts: [account('active', 10000), account('closed', 20000)],
      preferences: const [
        QestoAccountPreferences(
          accountId: 'closed',
          role: QestoAccountRole.savings,
          isClosed: true,
        ),
      ],
    );

    expect(result.totalLiquidAssets, 10000);
  });

  test('emergency fund remains unconfigured without selected accounts', () {
    final result = calculate(accounts: [account('card', 10000)]);

    expect(result.emergencyAccountCount, 0);
    expect(result.emergencyFundAmount, 0);
    expect(result.emergencyFundMonths, isNull);
  });

  test('known debt payments are reserved from available liquidity', () {
    final result = calculate(
      accounts: [account('card', 50000)],
      debts: [
        DebtAccount(
          id: 'loan',
          userId: 'user-1',
          name: 'Кредит',
          type: DebtType.personalLoan,
          currency: 'RUB',
          currentBalance: 200000,
          monthlyPayment: 15000,
          nextPaymentDate: DateTime(2026, 9, 10),
          status: DebtStatus.active,
          source: DebtSource.manual,
          dataQuality: DebtDataQuality.manual,
          confidence: 1,
          createdAt: DateTime(2026),
          updatedAt: asOf,
        ),
      ],
    );

    expect(result.debtPaymentsReserved, 15000);
    expect(result.reservedCash, 15000);
    expect(result.availableCash, 35000);
  });

  test(
    'goal allocations reserve liquidity without changing account balance',
    () {
      final result = calculate(
        accounts: [account('savings', 100000, type: AccountType.savings)],
        goalAllocations: [
          GoalAllocation(
            id: 'allocation',
            goalId: 'goal',
            sourceType: GoalAllocationSourceType.account,
            sourceId: 'savings',
            allocatedAmount: 60000,
            currency: 'RUB',
            updatedAt: asOf,
          ),
        ],
      );

      expect(result.totalLiquidAssets, 100000);
      expect(result.reservedCash, 60000);
      expect(result.availableCash, 40000);
    },
  );

  test(
    'emergency fund uses selected accounts and essential spending history',
    () {
      final expenses = <BudgetTransaction>[
        for (var index = 0; index < 6; index++)
          transaction(
            id: 'essential-$index',
            accountId: 'card',
            date: DateTime(2026, 7, 5 + index * 8),
            amount: 5000,
            type: TransactionType.expense,
            categoryId: 'groceries',
          ),
      ];
      final result = calculate(
        accounts: [
          account('card', 10000),
          account('reserve', 60000, type: AccountType.savings),
        ],
        transactions: expenses,
        goals: [
          SavingsGoal(
            id: 'goal',
            userId: 'user-1',
            title: 'Подушка безопасности',
            targetAmount: 120000,
            savedAmount: 0,
            currency: 'RUB',
            streakWeeks: 0,
            isActive: true,
            history: const [],
            category: 'Финансовая подушка',
          ),
        ],
      );

      expect(result.emergencyFundAmount, 60000);
      expect(result.averageEssentialMonthlyExpenses, isNotNull);
      expect(result.emergencyFundMonths, isNotNull);
      expect(result.emergencyGoal?.targetAmount, 120000);
    },
  );
}
