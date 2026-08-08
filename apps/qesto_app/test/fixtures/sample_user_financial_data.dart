import 'package:qesto/data/models/qesto_models.dart';

import 'sample_transactions.dart';

final mockBudgetPeriods = <BudgetPeriod>[
  for (var month = 1; month <= 4; month++)
    BudgetPeriod(
      id: 'budget-2026-${month.toString().padLeft(2, '0')}',
      userId: 'demo-user',
      startDate: DateTime(2026, month),
      endDate: DateTime(2026, month + 1, 0),
      type: BudgetPeriodType.calendarMonth,
      totalPlan: 56000 + month * 1000,
      currency: 'RUB',
    ),
  BudgetPeriod(
    id: 'budget-2026-05',
    userId: 'demo-user',
    startDate: DateTime(2026, 5),
    endDate: DateTime(2026, 5, 31),
    type: BudgetPeriodType.calendarMonth,
    totalPlan: 56000,
    currency: 'RUB',
  ),
  BudgetPeriod(
    id: 'budget-2026-06',
    userId: 'demo-user',
    startDate: DateTime(2026, 6),
    endDate: DateTime(2026, 6, 30),
    type: BudgetPeriodType.calendarMonth,
    totalPlan: 60000,
    currency: 'RUB',
  ),
  BudgetPeriod(
    id: 'budget-2026-07',
    userId: 'demo-user',
    startDate: DateTime(2026, 7),
    endDate: DateTime(2026, 7, 31),
    type: BudgetPeriodType.calendarMonth,
    totalPlan: 60000,
    currency: 'RUB',
  ),
  BudgetPeriod(
    id: 'budget-2026-08',
    userId: 'demo-user',
    startDate: DateTime(2026, 8),
    endDate: DateTime(2026, 8, 31),
    type: BudgetPeriodType.calendarMonth,
    totalPlan: 58000,
    currency: 'RUB',
  ),
  BudgetPeriod(
    id: 'budget-2026-09',
    userId: 'demo-user',
    startDate: DateTime(2026, 9),
    endDate: DateTime(2026, 9, 30),
    type: BudgetPeriodType.calendarMonth,
    totalPlan: 60000,
    currency: 'RUB',
  ),
];

final mockCategoryBudgets = <CategoryBudget>[
  for (final period in mockBudgetPeriods) ...[
    CategoryBudget(
      id: '${period.id}-groceries',
      budgetPeriodId: period.id,
      categoryId: 'groceries',
      plannedAmount: period.id == 'budget-2026-07' ? 20000 : 19000,
    ),
    CategoryBudget(
      id: '${period.id}-transport',
      budgetPeriodId: period.id,
      categoryId: 'transport',
      plannedAmount: 13000,
    ),
    CategoryBudget(
      id: '${period.id}-cafes',
      budgetPeriodId: period.id,
      categoryId: 'cafes',
      plannedAmount: 6000,
    ),
    CategoryBudget(
      id: '${period.id}-fun',
      budgetPeriodId: period.id,
      categoryId: 'fun',
      plannedAmount: 10000,
    ),
  ],
];

final mockPlanPoints = <BudgetPlanPoint>[
  BudgetPlanPoint(
    budgetPeriodId: 'budget-2026-07',
    date: DateTime(2026, 7, 1),
    cumulativePlannedAmount: 1800,
  ),
  BudgetPlanPoint(
    budgetPeriodId: 'budget-2026-07',
    date: DateTime(2026, 7, 5),
    cumulativePlannedAmount: 9000,
  ),
  BudgetPlanPoint(
    budgetPeriodId: 'budget-2026-07',
    date: DateTime(2026, 7, 10),
    cumulativePlannedAmount: 18000,
  ),
  BudgetPlanPoint(
    budgetPeriodId: 'budget-2026-07',
    date: DateTime(2026, 7, 15),
    cumulativePlannedAmount: 32000,
  ),
  BudgetPlanPoint(
    budgetPeriodId: 'budget-2026-07',
    date: DateTime(2026, 7, 19),
    cumulativePlannedAmount: 42000,
  ),
  BudgetPlanPoint(
    budgetPeriodId: 'budget-2026-07',
    date: DateTime(2026, 7, 25),
    cumulativePlannedAmount: 52000,
  ),
  BudgetPlanPoint(
    budgetPeriodId: 'budget-2026-07',
    date: DateTime(2026, 7, 31),
    cumulativePlannedAmount: 60000,
  ),
];

const mockAccounts = <QestoAccount>[
  QestoAccount(
    id: 'card-main',
    userId: 'demo-user',
    title: 'Основная карта',
    balance: 86420,
    currency: 'RUB',
    type: AccountType.bankCard,
  ),
  QestoAccount(
    id: 'cash',
    userId: 'demo-user',
    title: 'Наличные',
    balance: 6300,
    currency: 'RUB',
    type: AccountType.cash,
  ),
  QestoAccount(
    id: 'savings',
    userId: 'demo-user',
    title: 'Накопительный счёт',
    balance: 467000,
    currency: 'RUB',
    type: AccountType.savings,
  ),
  QestoAccount(
    id: 'deposit',
    userId: 'demo-user',
    title: 'Вклад',
    balance: 180000,
    currency: 'RUB',
    type: AccountType.deposit,
  ),
  QestoAccount(
    id: 'investments',
    userId: 'demo-user',
    title: 'Инвестиционный портфель',
    balance: 92000,
    currency: 'RUB',
    type: AccountType.investment,
  ),
  QestoAccount(
    id: 'receivable',
    userId: 'demo-user',
    title: 'Мне должны',
    balance: 12000,
    currency: 'RUB',
    type: AccountType.receivable,
  ),
  QestoAccount(
    id: 'liability',
    userId: 'demo-user',
    title: 'Обязательства',
    balance: -74000,
    currency: 'RUB',
    type: AccountType.liability,
  ),
];

final mockUpcomingExpenses = <UpcomingExpense>[
  UpcomingExpense(
    id: 'up-spotify',
    userId: 'demo-user',
    budgetPeriodId: 'budget-2026-07',
    title: 'Spotify',
    amount: 299,
    currency: 'RUB',
    plannedDate: DateTime(2026, 7, 22),
    categoryId: 'subscriptions',
    accountId: 'card-main',
    isRecurring: true,
    recurrenceRule: 'monthly',
    source: UpcomingExpenseSource.subscription,
  ),
  UpcomingExpense(
    id: 'up-internet',
    userId: 'demo-user',
    budgetPeriodId: 'budget-2026-07',
    title: 'Интернет',
    amount: 650,
    currency: 'RUB',
    plannedDate: DateTime(2026, 7, 24),
    categoryId: 'internet',
    accountId: 'card-main',
    isRecurring: true,
    recurrenceRule: 'monthly',
    source: UpcomingExpenseSource.detectedRecurring,
  ),
  UpcomingExpense(
    id: 'up-rent',
    userId: 'demo-user',
    budgetPeriodId: 'budget-2026-07',
    title: 'Аренда',
    amount: 35000,
    currency: 'RUB',
    plannedDate: DateTime(2026, 7, 28),
    categoryId: 'housing',
    accountId: 'card-main',
    isRecurring: true,
    recurrenceRule: 'monthly',
    source: UpcomingExpenseSource.manual,
  ),
  UpcomingExpense(
    id: 'up-fitness',
    userId: 'demo-user',
    budgetPeriodId: 'budget-2026-07',
    title: 'Фитнес',
    amount: 1900,
    currency: 'RUB',
    plannedDate: DateTime(2026, 7, 30),
    categoryId: 'health',
    accountId: 'card-main',
    source: UpcomingExpenseSource.manual,
  ),
];

final mockSavingsGoals = <SavingsGoal>[
  SavingsGoal(
    id: 'goal-home',
    userId: 'demo-user',
    title: 'Первоначальный взнос на дом',
    targetAmount: 600000,
    savedAmount: 467000,
    currency: 'RUB',
    streakWeeks: 64,
    isActive: true,
    history: [
      SavingsHistoryPoint(date: DateTime(2026, 3, 1), amount: 340000),
      SavingsHistoryPoint(date: DateTime(2026, 4, 1), amount: 378000),
      SavingsHistoryPoint(date: DateTime(2026, 5, 1), amount: 412000),
      SavingsHistoryPoint(date: DateTime(2026, 6, 1), amount: 441000),
      SavingsHistoryPoint(date: DateTime(2026, 7, 1), amount: 467000),
    ],
  ),
  const SavingsGoal(
    id: 'goal-travel',
    userId: 'demo-user',
    title: 'Путешествие',
    targetAmount: 180000,
    savedAmount: 24000,
    currency: 'RUB',
    streakWeeks: 8,
    isActive: false,
    history: [],
  ),
];

const mockUser = QestoUser(
  id: 'demo-user',
  name: 'Мария',
  defaultCurrency: 'RUB',
);

const mockTrackedProducts = <TrackedProduct>[
  TrackedProduct(
    id: 'tracked-headphones',
    userId: 'demo-user',
    title: 'Беспроводные наушники',
    currentPrice: 18990,
    currency: 'RUB',
    bestMarketplace: 'Яндекс Маркет',
    changePercent: -8.4,
    trackedStoresCount: 6,
    visualKey: 'electronics',
  ),
  TrackedProduct(
    id: 'tracked-coffee',
    userId: 'demo-user',
    title: 'Кофе в зёрнах, 1 кг',
    currentPrice: 1590,
    currency: 'RUB',
    bestMarketplace: 'Metro',
    changePercent: -12.0,
    trackedStoresCount: 4,
    visualKey: 'coffee',
  ),
];

final sampleUserFinancialData = UserFinancialData(
  user: mockUser,
  referenceDate: DateTime(2026, 7, 19),
  accounts: mockAccounts,
  budgetPeriods: mockBudgetPeriods,
  categoryBudgets: mockCategoryBudgets,
  transactions: sampleTransactions,
  upcomingExpenses: mockUpcomingExpenses,
  plannedCumulativePoints: mockPlanPoints,
  savingsGoals: mockSavingsGoals,
  trackedProducts: mockTrackedProducts,
);
