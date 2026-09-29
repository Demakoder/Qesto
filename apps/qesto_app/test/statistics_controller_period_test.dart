import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/statistics/domain/models/statistics_models.dart';
import 'package:qesto/features/statistics/presentation/state/statistics_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

void main() {
  test(
    'analytics opens a recent imported period instead of an empty month',
    () {
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'user',
            name: 'Пользователь',
            defaultCurrency: 'RUB',
          ),
          referenceDate: DateTime(2026, 9, 1),
          accounts: const [
            QestoAccount(
              id: 'card',
              userId: 'user',
              title: 'Карта',
              balance: 1000,
              currency: 'RUB',
              type: AccountType.bankCard,
            ),
          ],
          budgetPeriods: [
            BudgetPeriod(
              id: 'august',
              userId: 'user',
              startDate: DateTime(2026, 8),
              endDate: DateTime(2026, 8, 31),
              type: BudgetPeriodType.calendarMonth,
              totalPlan: 0,
              currency: 'RUB',
            ),
            BudgetPeriod(
              id: 'september',
              userId: 'user',
              startDate: DateTime(2026, 9),
              endDate: DateTime(2026, 9, 30),
              type: BudgetPeriodType.calendarMonth,
              totalPlan: 0,
              currency: 'RUB',
            ),
          ],
          transactions: [
            BudgetTransaction(
              id: 'august-sync',
              userId: 'user',
              accountId: 'card',
              date: DateTime(2026, 8, 20),
              amount: 500,
              currency: 'RUB',
              type: TransactionType.expense,
              categoryId: 'other',
            ),
          ],
        ),
      );
      final statistics = StatisticsController(budgetController: controller);
      addTearDown(statistics.dispose);

      expect(statistics.query.preset, StatisticsPeriodPreset.last30Days);
      expect(statistics.snapshot.transactions, hasLength(1));
      expect(statistics.snapshot.summary.expenses, 500);
    },
  );
}
