import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

import 'fixtures/sample_user_financial_data.dart';

void main() {
  test(
    'profile changes persist separately from Synoball money currencies',
    () async {
      var saved = false;
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: sampleUserFinancialData,
        onChanged: () async => saved = true,
      );
      final transactionCurrency =
          controller.synoballState.transactions.first.amount.currency;

      await controller.updateUserProfile(
        name: 'Алексей',
        defaultCurrency: 'EUR',
        avatarUrl: 'emoji:🚀',
      );

      expect(saved, isTrue);
      expect(controller.user.name, 'Алексей');
      expect(controller.user.defaultCurrency, 'EUR');
      expect(controller.user.avatarUrl, 'emoji:🚀');
      expect(
        controller.synoballState.transactions.first.amount.currency,
        transactionCurrency,
      );
      expect(
        controller.mergeInto(sampleUserFinancialData).user.name,
        'Алексей',
      );
      expect(controller.synoballState.entities.single.displayName, 'Алексей');
    },
  );

  test('savings goal editor data persists without mutating Synoball', () async {
    final controller = BudgetController(
      configuration: budgetConfiguration,
      financialData: sampleUserFinancialData,
    );
    final synoballBefore = controller.synoballState.transactions.length;
    final goal = await controller.addSavingsGoal(
      title: 'Кругосветка',
      category: 'Путешествие',
      targetAmount: 500000,
      savedAmount: 25000,
      targetDate: DateTime(2027, 6, 1),
      currency: 'RUB',
    );

    expect(goal, isNotNull);
    expect(controller.savingsGoals.last.category, 'Путешествие');
    expect(controller.savingsGoals.last.targetDate, DateTime(2027, 6, 1));
    expect(
      controller.mergeInto(sampleUserFinancialData).savingsGoals.last.title,
      'Кругосветка',
    );
    expect(controller.synoballState.transactions.length, synoballBefore);

    await controller.deleteSavingsGoal(goal!.id);
    expect(controller.savingsGoals.any((item) => item.id == goal.id), isTrue);
    expect(
      controller.savingsGoals.singleWhere((item) => item.id == goal.id).status,
      GoalStatus.archived,
    );
  });
}
