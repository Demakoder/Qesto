import 'package:qesto/data/models/qesto_models.dart';
import 'sample_user_financial_data.dart';

const stage4Cases = [
  'empty',
  'typical',
  'many',
  'huge',
  'exceeded',
  'no-budget',
  'long',
  'no-comparison',
];

UserFinancialData stage4Data(String kind) {
  final base = sampleUserFinancialData;
  if (kind == 'empty') {
    return UserFinancialData(
      user: base.user,
      referenceDate: base.referenceDate,
    );
  }
  if (kind == 'no-budget') {
    return base.copyWith(
      categoryBudgets: [],
      budgetPeriods: [
        for (final p in base.budgetPeriods) p.copyWith(totalPlan: 0),
      ],
    );
  }
  if (kind == 'exceeded') {
    return base.copyWith(
      budgetPeriods: [
        for (final p in base.budgetPeriods) p.copyWith(totalPlan: 100),
      ],
      categoryBudgets: [
        for (final b in base.categoryBudgets)
          CategoryBudget(
            id: b.id,
            budgetPeriodId: b.budgetPeriodId,
            categoryId: b.categoryId,
            plannedAmount: 1,
          ),
      ],
    );
  }
  if (kind == 'huge') {
    return base.copyWith(
      transactions: [
        for (final t in base.transactions)
          t.copyWith(
            amount: t.type == TransactionType.income ? 900000000 : 99999999,
          ),
      ],
      accounts: [
        for (final a in base.accounts)
          QestoAccount(
            id: a.id,
            userId: a.userId,
            title: a.title,
            balance: 999999999,
            currency: a.currency,
            type: a.type,
          ),
      ],
    );
  }
  if (kind == 'no-comparison') {
    return base.copyWith(
      transactions: base.transactions.where((t) => t.date.month == 7).toList(),
    );
  }
  if (kind == 'long') {
    return base.copyWith(
      categoryCustomizations: [
        for (final id in ['groceries', 'cafes', 'transport'])
          BudgetCategoryCustomization(
            categoryId: id,
            name:
                'Очень длинное название категории расходов, которое должно оставаться читаемым на узком телефоне',
            iconKey: 'shopping',
            colorValue: 0xFF168B55,
          ),
      ],
    );
  }
  if (kind == 'many') {
    return base.copyWith(
      classification: ClassificationSettings(
        customCategories: [
          for (var i = 0; i < 24; i++)
            BudgetCategory(
              id: 'many-$i',
              name: 'Категория $i',
              iconKey: 'shopping',
              colorValue: 0xFF168B55,
            ),
        ],
      ),
      transactions: [
        for (var i = 0; i < 360; i++)
          BudgetTransaction(
            id: 'many-op-$i',
            userId: base.user.id,
            accountId: base.accounts.first.id,
            date: DateTime(2026, 7, i % 19 + 1),
            amount: 100 + i,
            currency: 'RUB',
            type: TransactionType.expense,
            categoryId: 'many-${i % 24}',
            merchant: 'Магазин ${i % 35}',
          ),
      ],
    );
  }
  return base;
}
