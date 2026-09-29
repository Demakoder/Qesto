import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/synoball/core/models.dart';

void main() {
  BudgetController controller() => BudgetController(
    configuration: budgetConfiguration,
    financialData: UserFinancialData(
      user: const QestoUser(id: 'user-1', name: 'Test', defaultCurrency: 'RUB'),
      referenceDate: DateTime(2026, 9, 2),
    ),
  );

  test(
    'manual debt is linked to a canonical Synoball liability account',
    () async {
      final value = controller();
      final debt = await value.addDebt(
        name: 'Кредитная карта',
        currentBalance: 32000,
        type: DebtType.creditCard,
        monthlyPayment: 3000,
      );

      expect(debt, isNotNull);
      expect(debt!.linkedAccountId, isNotNull);
      final canonical = value.synoballState.accounts.singleWhere(
        (item) => item.id == debt.linkedAccountId,
      );
      expect(canonical.type, SynoballAccountType.credit);
      expect(canonical.balance.minorUnits, 3200000);
      expect(
        value.accounts.singleWhere((item) => item.id == canonical.id).type,
        AccountType.liability,
      );

      await value.updateDebt(debt.copyWith(currentBalance: 28000));
      expect(value.debtBalanceSnapshots, hasLength(2));
      expect(
        value.synoballState.accounts
            .singleWhere((item) => item.id == canonical.id)
            .balance
            .minorUnits,
        2800000,
      );

      await value.archiveDebt(debt.id);
      expect(value.debts.single.status, DebtStatus.archived);
      expect(
        value.synoballState.accounts
            .singleWhere((item) => item.id == canonical.id)
            .balance
            .minorUnits,
        0,
      );
    },
  );

  test('goal changes preserve progress history and completion', () async {
    final value = controller();
    final goal = await value.addSavingsGoal(
      title: 'Подушка',
      category: 'Финансовая подушка',
      targetAmount: 100000,
    );

    await value.updateSavingsGoal(goal!.copyWith(savedAmount: 100000));

    expect(value.savingsGoals.single.history.single.amount, 100000);
    expect(value.savingsGoals.single.status, GoalStatus.funded);
    expect(value.savingsGoals.single.isActive, isFalse);
  });

  test(
    'manual investment account is linked to Synoball and keeps snapshots',
    () async {
      final value = controller();
      final investment = await value.addInvestmentAccount(
        name: 'Т-Инвестиции',
        currentBalance: 430000,
        type: InvestmentAccountType.brokerage,
      );

      expect(investment, isNotNull);
      final saved = investment!;
      final canonical = value.synoballState.accounts.singleWhere(
        (item) => item.id == saved.linkedAccountId,
      );
      expect(canonical.type, SynoballAccountType.brokerage);
      expect(canonical.balance.minorUnits, 43000000);

      await value.updateInvestmentBalance(
        investmentAccountId: saved.id,
        balance: 455000,
        date: DateTime.now(),
      );

      expect(value.investmentAccounts.single.currentBalance, 455000);
      expect(value.investmentBalanceSnapshots, hasLength(1));
      expect(value.investmentBalanceSnapshots.single.balance, 455000);
      await value.updateInvestmentBalance(
        investmentAccountId: saved.id,
        balance: 460000,
        date: DateTime.now().add(const Duration(days: 1)),
      );
      expect(value.investmentBalanceSnapshots, hasLength(2));
      expect(
        value.synoballState.accounts
            .singleWhere((item) => item.id == saved.linkedAccountId)
            .balance
            .minorUnits,
        46000000,
      );
    },
  );

  test('hard goal allocations cannot exceed a source balance', () async {
    final value = controller();
    final account = await value.addAccount(
      title: 'Накопительный',
      balance: 100000,
      type: AccountType.savings,
    );
    final first = await value.addSavingsGoal(
      title: 'Подушка',
      category: 'Финансовая подушка',
      targetAmount: 200000,
    );
    final second = await value.addSavingsGoal(
      title: 'Отпуск',
      category: 'Путешествие',
      targetAmount: 100000,
    );

    expect(
      await value.upsertGoalAllocation(
        GoalAllocation(
          id: 'allocation-1',
          goalId: first!.id,
          sourceType: GoalAllocationSourceType.account,
          sourceId: account.id,
          allocatedAmount: 80000,
          currency: 'RUB',
          updatedAt: DateTime(2026, 9, 2),
        ),
      ),
      isTrue,
    );
    expect(
      await value.upsertGoalAllocation(
        GoalAllocation(
          id: 'allocation-2',
          goalId: second!.id,
          sourceType: GoalAllocationSourceType.account,
          sourceId: account.id,
          allocatedAmount: 30000,
          currency: 'RUB',
          updatedAt: DateTime(2026, 9, 2),
        ),
      ),
      isFalse,
    );
    expect(value.goalAllocations, hasLength(1));
  });
}
