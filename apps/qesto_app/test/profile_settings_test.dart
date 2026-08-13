import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

import 'fixtures/sample_user_financial_data.dart';

void main() {
  test('profile changes persist separately from Synoball money currencies', () async {
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
    expect(controller.mergeInto(sampleUserFinancialData).user.name, 'Алексей');
    expect(controller.synoballState.entities.single.displayName, 'Алексей');
  });
}
