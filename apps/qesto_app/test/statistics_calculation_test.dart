import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/statistics/domain/models/statistics_models.dart';
import 'package:qesto/features/statistics/domain/services/data_quality_service.dart';
import 'package:qesto/features/statistics/domain/services/statistics_calculation_service.dart';
import 'package:qesto/features/statistics/domain/services/statistics_insights_service.dart';

void main() {
  const service = StatisticsCalculationService();
  const account = QestoAccount(
    id: 'card',
    userId: 'user',
    title: 'Карта',
    balance: 20000,
    currency: 'RUB',
    type: AccountType.bankCard,
  );
  const cash = QestoAccount(
    id: 'cash',
    userId: 'user',
    title: 'Наличные',
    balance: 1000,
    currency: 'RUB',
    type: AccountType.cash,
  );
  const categories = [
    BudgetCategory(
      id: 'food',
      name: 'Продукты',
      iconKey: 'cart',
      colorValue: 0xFF00AA00,
    ),
    BudgetCategory(
      id: 'transport',
      name: 'Транспорт',
      iconKey: 'transport',
      colorValue: 0xFF0000AA,
    ),
  ];
  final periods = [
    BudgetPeriod(
      id: 'jun',
      userId: 'user',
      startDate: DateTime(2026, 6),
      endDate: DateTime(2026, 6, 30),
      type: BudgetPeriodType.calendarMonth,
      totalPlan: 7000,
      currency: 'RUB',
    ),
    BudgetPeriod(
      id: 'jul',
      userId: 'user',
      startDate: DateTime(2026, 7),
      endDate: DateTime(2026, 7, 31),
      type: BudgetPeriodType.calendarMonth,
      totalPlan: 8000,
      currency: 'RUB',
    ),
  ];

  BudgetTransaction transaction({
    required String id,
    required DateTime date,
    required int amount,
    TransactionType type = TransactionType.expense,
    String? categoryId = 'food',
    String? merchant = 'Магазин A',
    String accountId = 'card',
    bool isLarge = false,
    bool isRecurring = false,
    bool isDuplicate = false,
    bool isConfirmed = true,
    double confidence = 1,
    TransferDirection? transferDirection,
    List<String> tags = const [],
  }) => BudgetTransaction(
    id: id,
    userId: 'user',
    accountId: accountId,
    date: date,
    amount: amount,
    currency: 'RUB',
    type: type,
    categoryId: categoryId,
    merchant: merchant,
    normalizedMerchant: merchant,
    isLargePurchase: isLarge,
    isRecurring: isRecurring,
    isPotentialDuplicate: isDuplicate,
    isConfirmed: isConfirmed,
    classificationConfidence: confidence,
    transferDirection: transferDirection,
    tags: tags,
  );

  late List<BudgetTransaction> transactions;
  late StatisticsQuery query;

  setUp(() {
    transactions = [
      transaction(
        id: 'previous-food',
        date: DateTime(2026, 6, 1),
        amount: 1000,
      ),
      transaction(
        id: 'previous-transport',
        date: DateTime(2026, 6, 2),
        amount: 1000,
        categoryId: 'transport',
        merchant: 'Такси B',
      ),
      transaction(id: 'food-1', date: DateTime(2026, 7, 1), amount: 1000),
      transaction(
        id: 'food-2',
        date: DateTime(2026, 7, 2),
        amount: 2000,
        isRecurring: true,
      ),
      transaction(
        id: 'refund',
        date: DateTime(2026, 7, 3),
        amount: 500,
        type: TransactionType.refund,
      ),
      transaction(
        id: 'transport',
        date: DateTime(2026, 7, 4),
        amount: 4000,
        categoryId: 'transport',
        merchant: 'Такси B',
        isLarge: true,
      ),
      transaction(
        id: 'income',
        date: DateTime(2026, 7, 1),
        amount: 10000,
        type: TransactionType.income,
        categoryId: null,
        merchant: 'Работодатель',
      ),
      transaction(
        id: 'savings',
        date: DateTime(2026, 7, 2),
        amount: 1000,
        type: TransactionType.savingsTransfer,
        categoryId: null,
        merchant: null,
      ),
      transaction(
        id: 'transfer',
        date: DateTime(2026, 7, 3),
        amount: 5000,
        type: TransactionType.transfer,
        categoryId: null,
        merchant: null,
      ),
      transaction(
        id: 'duplicate',
        date: DateTime(2026, 7, 1, 0, 1),
        amount: 1000,
        isDuplicate: true,
        isConfirmed: false,
      ),
    ];
    query = StatisticsQuery(
      period: StatisticsDateRange(DateTime(2026, 7), DateTime(2026, 7, 10)),
    );
  });

  StatisticsSnapshot snapshot() => service.buildSnapshot(
    query: query,
    allTransactions: transactions,
    categories: categories,
    periods: periods,
    accounts: const [account, cash],
    referenceDate: DateTime(2026, 7, 10),
  );

  test('сумма расходов учитывает только потребительские операции', () {
    expect(snapshot().summary.expenses, 6500);
  });

  test('сумма доходов не включает возвраты и переводы', () {
    expect(snapshot().summary.income, 10000);
  });

  test('остаток вычитает расходы и накопления', () {
    expect(snapshot().summary.balance, 2500);
  });

  test('переводы, накопления и инвестиции исключены из расходов', () {
    final values = [
      transaction(
        id: 'transfer-only',
        date: DateTime(2026, 7, 1),
        amount: 1000,
        type: TransactionType.transfer,
      ),
      transaction(
        id: 'saving-only',
        date: DateTime(2026, 7, 1),
        amount: 1000,
        type: TransactionType.savingsTransfer,
      ),
      transaction(
        id: 'investment-only',
        date: DateTime(2026, 7, 1),
        amount: 1000,
        type: TransactionType.investment,
      ),
    ];
    expect(service.expenses(values), 0);
  });

  test('внешний исходящий перевод считается расходом', () {
    final value = transaction(
      id: 'person-transfer',
      date: DateTime(2026, 7, 1),
      amount: 1000,
      type: TransactionType.transfer,
      transferDirection: TransferDirection.outgoing,
    );

    expect(service.expenses([value]), 1000);
    expect(service.purchaseAmounts([value]), [1000]);
  });

  test('возврат уменьшает исходную категорию', () {
    expect(
      snapshot().categories.firstWhere((item) => item.id == 'food').amount,
      2500,
    );
  });

  test('средний чек рассчитывается по покупкам без возврата', () {
    expect(snapshot().summary.averageCheck, closeTo(2333.33, 0.01));
  });

  test('обычный чек является медианой', () {
    expect(snapshot().summary.medianCheck, 2000);
  });

  test('неполный месяц сравнивается с таким же числом дней', () {
    final range = service.comparisonRange(query)!;
    expect(range.start, DateTime(2026, 6));
    expect(range.end, DateTime(2026, 6, 10));
    expect(range.dayCount, query.period.dayCount);
  });

  test('процент изменения рассчитывается относительно сравнения', () {
    expect(snapshot().summary.changePercent, 225);
    expect(service.percentChange(120, 100), 20);
  });

  test('расходы группируются по категориям', () {
    expect(
      snapshot().categories.map((item) => item.id),
      containsAll(['food', 'transport']),
    );
    expect(
      snapshot().categories.fold<int>(0, (sum, item) => sum + item.amount),
      6500,
    );
  });

  test('расходы группируются по нормализованным продавцам', () {
    final merchants = snapshot().merchants;
    expect(merchants.firstWhere((item) => item.id == 'Магазин A').amount, 2500);
    expect(merchants.firstWhere((item) => item.id == 'Такси B').amount, 4000);
  });

  test('количество покупок исключает возврат и дубль', () {
    expect(snapshot().summary.purchaseCount, 3);
  });

  test('крупная покупка определяется ручной отметкой', () {
    final item = transactions.firstWhere((item) => item.id == 'transport');
    expect(service.isLargePurchase(item, transactions), isTrue);
  });

  test('распределение по диапазонам согласовано с покупками', () {
    final buckets = snapshot().buckets;
    expect(buckets.fold<int>(0, (sum, item) => sum + item.count), 3);
    expect(
      buckets.firstWhere((item) => item.label == '1 000–3 000 ₽').count,
      2,
    );
  });

  test('расходы распределяются по дням недели', () {
    final weekdays = snapshot().weekdays;
    expect(weekdays.fold<int>(0, (sum, item) => sum + item.amount), 6500);
    expect(weekdays.fold<int>(0, (sum, item) => sum + item.count), 3);
  });

  test('регулярные платежи попадают в отдельную выборку', () {
    expect(snapshot().recurringTransactions.single.id, 'food-2');
  });

  test('точки периода исключают будущие периоды', () {
    final points = snapshot().periods;
    expect(points.length, 2);
    expect(points.last.period.id, 'jul');
    expect(points.last.expenses, 6500);
  });

  test('фильтр наличных влияет на все агрегаты', () {
    transactions.add(
      transaction(
        id: 'cash-expense',
        date: DateTime(2026, 7, 5),
        amount: 700,
        accountId: 'cash',
      ),
    );
    query = query.copyWith(includeCash: false);
    expect(snapshot().summary.expenses, 6500);
  });

  test('фильтр категории влияет на итог и график', () {
    query = query.copyWith(categoryIds: {'food'});
    final result = snapshot();
    expect(result.summary.expenses, 2500);
    expect(result.categories.single.id, 'food');
    expect(result.daily.last.cumulative, 2500);
  });

  test('среднее за три периода создаёт три диапазона сравнения', () {
    query = query.copyWith(comparison: StatisticsComparison.average3);
    final ranges = service.comparisonRanges(query);
    expect(ranges.length, 3);
    expect(
      ranges.every((range) => range.dayCount == query.period.dayCount),
      isTrue,
    );
  });

  test('подозрительный дубль не учитывается дважды и виден в качестве', () {
    final result = snapshot();
    expect(result.summary.purchaseCount, 3);
    expect(
      result.dataQuality.issues.any(
        (issue) => issue.type == DataQualityIssueType.potentialDuplicate,
      ),
      isTrue,
    );
  });

  test('полнота данных использует настраиваемые веса', () {
    const quality = DataQualityService(
      weights: {DataQualityIssueType.lowConfidence: 20},
    );
    final report = quality.evaluate(
      transactions: [
        transaction(
          id: 'low',
          date: DateTime(2026, 7, 1),
          amount: 100,
          confidence: 0.2,
        ),
      ],
      accountIds: {'card'},
    );
    expect(report.score, 80);
  });

  test('неизвестный продавец и отсутствующая категория создают проблемы', () {
    const quality = DataQualityService();
    final report = quality.evaluate(
      transactions: [
        transaction(
          id: 'unknown',
          date: DateTime(2026, 7, 1),
          amount: 100,
          categoryId: null,
          merchant: null,
        ),
      ],
      accountIds: {'card'},
    );
    expect(
      report.issues.map((issue) => issue.type),
      containsAll([
        DataQualityIssueType.uncategorized,
        DataQualityIssueType.unknownMerchant,
      ]),
    );
  });

  test('детерминированные выводы содержат объяснение расчёта', () {
    const insights = StatisticsInsightsService();
    final result = snapshot();
    final values = insights.build(
      summary: result.summary,
      categories: result.categories,
      merchants: result.merchants,
      quality: result.dataQuality,
      largePurchaseAmount: 4000,
    );
    expect(values, isNotEmpty);
    expect(values.every((item) => item.calculation.isNotEmpty), isTrue);
  });

  test('дневные точки содержат нулевые дни и накопительный итог', () {
    final points = snapshot().daily;
    expect(points.length, 10);
    expect(points.last.cumulative, 6500);
    expect(points.where((point) => point.amount == 0), isNotEmpty);
  });

  test('сравнение без данных не создаёт категоричный процент', () {
    query = query.copyWith(comparison: StatisticsComparison.previousYear);
    expect(snapshot().summary.changePercent, isNull);
  });
}
