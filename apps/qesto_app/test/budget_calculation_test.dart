import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/services/budget_calculation_service.dart';
import 'package:qesto/features/budget/services/budget_forecast_service.dart';

void main() {
  const calculations = BudgetCalculationService();
  const forecasts = BudgetForecastService();
  final period = BudgetPeriod(
    id: 'test-period',
    userId: 'user',
    startDate: DateTime(2026, 7),
    endDate: DateTime(2026, 7, 10),
    type: BudgetPeriodType.custom,
    totalPlan: 10000,
    currency: 'RUB',
  );

  BudgetTransaction transaction({
    required String id,
    required int day,
    required int amount,
    TransactionType type = TransactionType.expense,
    String? categoryId = 'food',
  }) {
    return BudgetTransaction(
      id: id,
      userId: 'user',
      accountId: 'card',
      date: DateTime(2026, 7, day),
      amount: amount,
      currency: 'RUB',
      type: type,
      categoryId: categoryId,
    );
  }

  test('суммирует потребительские расходы периода', () {
    final total = calculations.currentExpense(period, [
      transaction(id: 'a', day: 1, amount: 1200),
      transaction(id: 'b', day: 2, amount: 800),
    ]);
    expect(total, 2000);
  });

  test('исключает переводы, накопления и инвестиции', () {
    final total = calculations.currentExpense(period, [
      transaction(id: 'expense', day: 1, amount: 1000),
      transaction(
        id: 'transfer',
        day: 2,
        amount: 5000,
        type: TransactionType.transfer,
      ),
      transaction(
        id: 'savings',
        day: 2,
        amount: 3000,
        type: TransactionType.savingsTransfer,
      ),
      transaction(
        id: 'investment',
        day: 2,
        amount: 2000,
        type: TransactionType.investment,
      ),
    ]);
    expect(total, 1000);
  });

  test('возврат уменьшает расход', () {
    final total = calculations.currentExpense(period, [
      transaction(id: 'expense', day: 1, amount: 3000),
      transaction(
        id: 'refund',
        day: 2,
        amount: 700,
        type: TransactionType.refund,
      ),
    ]);
    expect(total, 2300);
  });

  test('рассчитывает сумму выбранной категории', () {
    final total = calculations.categoryExpense(period, 'food', [
      transaction(id: 'food', day: 1, amount: 2000),
      transaction(
        id: 'transport',
        day: 2,
        amount: 900,
        categoryId: 'transport',
      ),
    ]);
    expect(total, 2000);
  });

  test('рассчитывает процент выполнения плана', () {
    expect(calculations.planProgress(7500, 10000), 0.75);
    expect(calculations.planProgress(100, 0), 0);
  });

  test('рассчитывает допустимый дневной расход', () {
    expect(
      calculations.allowedDailyExpense(period, 4000, DateTime(2026, 7, 4)),
      1000,
    );
  });

  test('строит накопительные точки по дням', () {
    final points = calculations.cumulativePoints(period, [
      transaction(id: 'a', day: 1, amount: 1000),
      transaction(id: 'b', day: 3, amount: 500),
    ], DateTime(2026, 7, 3));
    expect(points.map((point) => point.amount), [1000, 1000, 1500]);
  });

  test('прогнозирует дату превышения лимита', () {
    final forecast = forecasts.buildForecast(
      period: period,
      transactions: [
        for (var day = 1; day <= 5; day++)
          transaction(id: 'e$day', day: day, amount: 1500),
      ],
      asOfDate: DateTime(2026, 7, 5),
    );
    expect(forecast.state, BudgetForecastState.projectedOverLimit);
    expect(forecast.crossingDate, DateTime(2026, 7, 7));
  });

  test('показывает состояние прогноза в пределах плана', () {
    final forecast = forecasts.buildForecast(
      period: period,
      transactions: [
        for (var day = 1; day <= 5; day++)
          transaction(id: 'e$day', day: day, amount: 300),
      ],
      asOfDate: DateTime(2026, 7, 5),
    );
    expect(forecast.state, BudgetForecastState.underPlan);
    expect(forecast.crossingDate, isNull);
  });

  test('показывает состояние уже превышенного лимита', () {
    final forecast = forecasts.buildForecast(
      period: period,
      transactions: [transaction(id: 'large', day: 2, amount: 12000)],
      asOfDate: DateTime(2026, 7, 2),
    );
    expect(forecast.state, BudgetForecastState.exceeded);
    expect(forecast.targetPoints, isEmpty);
  });

  test('нулевой план означает неназначенный бюджет, а не превышение', () {
    final unassigned = BudgetPeriod(
      id: 'unassigned',
      userId: 'user',
      startDate: DateTime(2026, 7),
      endDate: DateTime(2026, 7, 10),
      type: BudgetPeriodType.custom,
      totalPlan: 0,
      currency: 'RUB',
    );
    final summary = calculations.summary(unassigned, [
      transaction(id: 'expense-without-budget', day: 2, amount: 7000),
    ], const []);
    final forecast = forecasts.buildForecast(
      period: unassigned,
      transactions: [
        transaction(id: 'expense-without-budget', day: 2, amount: 7000),
      ],
      asOfDate: DateTime(2026, 7, 2),
    );

    expect(unassigned.hasAssignedBudget, isFalse);
    expect(summary.hasAssignedBudget, isFalse);
    expect(summary.progress, 0);
    expect(forecast.state, BudgetForecastState.noForecast);
    expect(forecast.projectedPoints, isEmpty);
  });
}
