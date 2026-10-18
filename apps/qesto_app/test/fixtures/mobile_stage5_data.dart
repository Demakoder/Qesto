import 'package:qesto/data/models/qesto_models.dart';
import 'sample_user_financial_data.dart';

// Synthetic data only; render/test harness never loads a user's storage.
UserFinancialData stage5Data([String kind = 'typical']) {
  final day = DateTime(2026, 10, 6);
  final empty = kind == 'empty';
  final many = kind == 'many' ? 180 : 2;
  final huge = kind == 'huge';
  final negative = kind == 'negative';
  final amount = huge ? 9876543210123 : 84320;
  final snapshotCount = kind == 'many' ? 1500 : 20;
  final accounts = <QestoAccount>[
    if (!empty)
      for (var i = 0; i < many; i++)
        QestoAccount(
          id: 'cap-$i',
          userId: 'demo-user',
          title: i == 0
              ? 'Платёжный счёт с длинным названием для проверки доступности'
              : 'Резерв $i',
          balance: i == 0 ? amount : 15000,
          exactBalanceMinor: i == 0 ? amount * 100 + 45 : null,
          currency: 'RUB',
          type: i == 0 ? AccountType.bankCard : AccountType.savings,
        ),
    if (!empty)
      const QestoAccount(
        id: 'fx',
        userId: 'demo-user',
        title: 'Валютный остаток',
        balance: 123,
        exactBalanceMinor: 12345,
        currency: 'USD',
        type: AccountType.bankCard,
      ),
    if (!empty)
      QestoAccount(
        id: 'linked-inv-0',
        userId: 'demo-user',
        title: 'Брокерский портфель',
        balance: amount,
        currency: 'RUB',
        type: AccountType.investment,
      ),
    if (!empty)
      QestoAccount(
        id: 'linked-debt-0',
        userId: 'demo-user',
        title: 'Кредит на образование',
        balance: negative ? amount * 10 : 120000,
        currency: 'RUB',
        type: AccountType.liability,
      ),
  ];
  final investments = <InvestmentAccount>[
    if (!empty)
      for (var i = 0; i < many; i++)
        InvestmentAccount(
          id: 'inv-$i',
          userId: 'demo-user',
          linkedAccountId: 'linked-inv-$i',
          name: i == 0
              ? 'Брокерский портфель · долгосрочные накопления'
              : 'Архивный портфель $i',
          type: InvestmentAccountType.brokerage,
          currency: 'RUB',
          currentBalance: i == 0 ? amount : 0,
          status: i == 0
              ? InvestmentAccountStatus.active
              : InvestmentAccountStatus.archived,
          source: InvestmentDataSource.manual,
          createdAt: DateTime(2026, 1),
          updatedAt: day,
          lastBalanceUpdateAt: day,
          plan: const InvestmentPlan(amount: 5000, preferredDay: 12),
        ),
  ];
  final debts = <DebtAccount>[
    if (!empty)
      for (var i = 0; i < many; i++)
        DebtAccount(
          id: 'debt-$i',
          linkedAccountId: i == 0 ? 'linked-debt-0' : null,
          userId: 'demo-user',
          name: i == 0
              ? 'Кредит на образование с длинным названием'
              : 'Закрытый долг $i',
          type: DebtType.personalLoan,
          currency: 'RUB',
          currentBalance: i == 0 ? (negative ? amount * 10 : 120000) : 0,
          status: i == 0 ? DebtStatus.active : DebtStatus.closed,
          source: DebtSource.manual,
          dataQuality: DebtDataQuality.manual,
          confidence: 1,
          createdAt: DateTime(2026, 1),
          updatedAt: day,
          interestRate: 12.5,
          monthlyPayment: 10000,
          paymentDay: 12,
          paymentType: DebtPaymentType.annuity,
          nextPaymentDate: DateTime(2026, 10, 12),
        ),
  ];
  final goals = <SavingsGoal>[
    if (!empty)
      for (var i = 0; i < many; i++)
        SavingsGoal(
          id: 'goal-$i',
          userId: 'demo-user',
          title: i == 0
              ? 'Путешествие и отдых · план на следующий год'
              : 'Завершённая цель $i',
          targetAmount: huge ? amount : 50000,
          savedAmount: i == 0 ? (kind == 'overfunded' ? 65000 : 15000) : 20000,
          currency: 'RUB',
          streakWeeks: 0,
          isActive: i == 0,
          status: i == 0 ? GoalStatus.active : GoalStatus.completed,
          desiredMonthlyContribution: 5000,
          targetDate: i == 0 ? DateTime(2027, 6) : null,
          history: [
            SavingsHistoryPoint(
              date: day.subtract(const Duration(days: 15)),
              amount: 5000,
            ),
            SavingsHistoryPoint(date: day, amount: 15000),
          ],
        ),
  ];
  return sampleUserFinancialData.copyWith(
    referenceDate: day,
    accounts: accounts,
    transactions: [
      if (!empty)
        for (final entry in <(int, int, TransactionType)>[
          (1, 20000, TransactionType.income),
          (2, 800, TransactionType.expense),
          (4, 1500, TransactionType.expense),
          (6, 300, TransactionType.expense),
        ])
          BudgetTransaction(
            id: 'stage5-operation-${entry.$1}',
            userId: 'demo-user',
            accountId: 'cap-0',
            date: DateTime(2026, 10, entry.$1),
            amount: entry.$2,
            currency: 'RUB',
            type: entry.$3,
            categoryId: entry.$3 == TransactionType.expense
                ? 'groceries'
                : null,
            merchant: entry.$3 == TransactionType.expense
                ? 'Демонстрационная покупка'
                : 'Демонстрационный доход',
          ),
    ],
    savingsGoals: goals,
    accountPreferences: [
      if (!empty)
        const QestoAccountPreferences(
          accountId: 'cap-1',
          includeInEmergencyFund: true,
          role: QestoAccountRole.emergency,
        ),
    ],
    investmentAccounts: investments,
    investmentBalanceSnapshots: [
      if (!empty)
        for (var i = 0; i < snapshotCount; i++)
          InvestmentBalanceSnapshot(
            id: 'ivs-$i',
            investmentAccountId: 'inv-0',
            date: day.subtract(Duration(days: snapshotCount - 1 - i)),
            balance: amount - 1000 + i * 50,
            currency: 'RUB',
            source: InvestmentDataSource.manual,
            createdAt: day,
          ),
    ],
    investmentContributions: [],
    debts: debts,
    debtBalanceSnapshots: [
      if (!empty)
        for (var i = 0; i < 20; i++)
          DebtBalanceSnapshot(
            id: 'ds-$i',
            debtId: 'debt-0',
            date: day.subtract(Duration(days: 19 - i)),
            totalBalance: 125000 - i * 250,
            source: DebtSource.manual,
            confidence: 1,
          ),
    ],
    debtPayments: [],
    goalAllocations: [],
    goalContributions: [],
    goalHistoryEvents: [],
    upcomingExpenses: [],
  );
}
