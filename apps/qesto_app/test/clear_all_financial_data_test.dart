import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

import 'fixtures/sample_user_financial_data.dart';

void main() {
  test(
    'clear all removes user finance while leaving an operable scaffold',
    () async {
      var saved = false;
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: sampleUserFinancialData,
        onChanged: () async => saved = true,
      );

      expect(controller.transactions, isNotEmpty);
      expect(controller.accounts.length, greaterThan(1));
      expect(controller.upcomingExpenses, isNotEmpty);

      await controller.clearAllFinancialData();

      expect(saved, isTrue);
      expect(controller.transactions, isEmpty);
      expect(controller.upcomingExpenses, isEmpty);
      expect(controller.actions, isEmpty);
      expect(controller.categoryBudgets, isEmpty);
      expect(controller.plannedCumulativePoints, isEmpty);
      expect(controller.synoballState.transactions, isEmpty);
      expect(controller.synoballState.rawPayloads, isEmpty);
      expect(controller.synoballState.evidence, isEmpty);
      expect(controller.accounts, hasLength(1));
      expect(controller.accounts.single.balance, 0);

      final persisted = controller.mergeInto(sampleUserFinancialData);
      expect(persisted.savingsGoals, isEmpty);
      expect(persisted.trackedProducts, isEmpty);
    },
  );
}
