import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/desktop/pages/desktop_statistics_page.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/statistics/domain/models/statistics_models.dart';
import 'package:qesto/features/statistics/domain/services/statistics_calculation_service.dart';
import 'package:qesto/features/statistics/presentation/screens/statistics_drilldown_screens.dart';
import 'package:qesto/features/statistics/presentation/state/statistics_controller.dart';
import 'package:qesto/features/statistics/presentation/widgets/statistics_charts.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

const _account = QestoAccount(
  id: 'card',
  userId: 'user',
  title: 'Card',
  balance: 20000,
  currency: 'RUB',
  type: AccountType.bankCard,
);

BudgetTransaction _expense(String id, int amount, String category, int day) =>
    BudgetTransaction(
      id: id,
      userId: 'user',
      accountId: 'card',
      date: DateTime(2026, 9, day),
      amount: amount,
      currency: 'RUB',
      type: TransactionType.expense,
      categoryId: category,
      merchant: id,
      title: id,
    );

BudgetController _budget({Future<void> Function()? onChanged}) =>
    BudgetController(
      configuration: budgetConfiguration,
      onChanged: onChanged,
      financialData: UserFinancialData(
        user: const QestoUser(id: 'user', name: 'User', defaultCurrency: 'RUB'),
        referenceDate: DateTime(2026, 9, 28),
        accounts: const [_account],
        classification: const ClassificationSettings(
          customCategories: [
            BudgetCategory(
              id: 'sports',
              name: 'Спорт',
              iconKey: 'hobby',
              colorValue: 0xFF3478F6,
            ),
          ],
        ),
        budgetPeriods: [
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
          _expense('DDX', 2000, 'other', 10),
          _expense('other-base', 8000, 'other', 11),
          _expense('sport-base', 5000, 'sports', 12),
        ],
      ),
    );

int _categoryTotal(StatisticsController stats, String id) => stats
    .snapshot
    .categories
    .where((category) => category.id == id)
    .fold(0, (sum, category) => sum + category.amount);

class _CountingCalculationService extends StatisticsCalculationService {
  int calls = 0;
  bool fail = false;

  @override
  StatisticsSnapshot buildSnapshot({
    required StatisticsQuery query,
    required List<BudgetTransaction> allTransactions,
    required List<BudgetCategory> categories,
    required List<BudgetPeriod> periods,
    required List<QestoAccount> accounts,
    required DateTime referenceDate,
    Set<String> ignoredQualityIssueIds = const {},
  }) {
    calls++;
    if (fail) throw StateError('Local analytics failure');
    return super.buildSnapshot(
      query: query,
      allTransactions: allTransactions,
      categories: categories,
      periods: periods,
      accounts: accounts,
      referenceDate: referenceDate,
      ignoredQualityIssueIds: ignoredQualityIssueIds,
    );
  }
}

void main() {
  late BudgetController budget;
  late StatisticsController stats;
  late _CountingCalculationService calculation;
  var saves = 0;

  setUp(() {
    saves = 0;
    budget = _budget(onChanged: () async => saves++);
    calculation = _CountingCalculationService();
    stats = StatisticsController(
      budgetController: budget,
      calculationService: calculation,
    );
    stats.setCustomPeriod(DateTime(2026, 9), DateTime(2026, 9, 30));
  });
  tearDown(() {
    stats.dispose();
    budget.dispose();
  });

  test(
    'saved category mutation moves amount and count without stale category',
    () async {
      final initialBuilds = calculation.calls;
      expect(_categoryTotal(stats, 'other'), 10000);
      expect(_categoryTotal(stats, 'sports'), 5000);

      await budget.changeTransactionCategory('DDX', 'sports');

      expect(saves, 1);
      expect(calculation.calls, initialBuilds + 1);
      expect(
        budget.transactions.singleWhere((t) => t.id == 'DDX').categoryId,
        'sports',
      );
      expect(_categoryTotal(stats, 'other'), 8000);
      expect(_categoryTotal(stats, 'sports'), 7000);
      expect(
        stats.snapshot.categories.singleWhere((c) => c.id == 'other').count,
        1,
      );
      expect(
        stats.snapshot.categories.singleWhere((c) => c.id == 'sports').count,
        2,
      );
    },
  );

  test(
    'failed persistence does not publish a new analytics snapshot',
    () async {
      final failingBudget = _budget(
        onChanged: () async => throw StateError('Storage unavailable'),
      );
      final failingStats = StatisticsController(
        budgetController: failingBudget,
      );
      addTearDown(failingStats.dispose);
      addTearDown(failingBudget.dispose);
      failingStats.setCustomPeriod(DateTime(2026, 9), DateTime(2026, 9, 30));
      final priorSnapshot = failingStats.snapshot;

      await expectLater(
        failingBudget.changeTransactionCategory('DDX', 'sports'),
        throwsStateError,
      );
      expect(failingStats.snapshot, same(priorSnapshot));
      expect(_categoryTotal(failingStats, 'other'), 10000);
    },
  );

  test(
    'amount, date, type and delete/restore update derived analytics',
    () async {
      var ddx = budget.transactions.singleWhere((t) => t.id == 'DDX');
      await budget.updateTransaction(ddx.copyWith(amount: 3000));
      expect(stats.snapshot.summary.expenses, 16000);
      expect(_categoryTotal(stats, 'other'), 11000);

      ddx = budget.transactions.singleWhere((t) => t.id == 'DDX');
      await budget.updateTransaction(ddx.copyWith(date: DateTime(2026, 8, 10)));
      expect(stats.snapshot.summary.expenses, 13000);
      expect(stats.snapshot.transactions.any((t) => t.id == 'DDX'), isFalse);

      ddx = budget.transactions.singleWhere((t) => t.id == 'DDX');
      await budget.updateTransaction(ddx.copyWith(date: DateTime(2026, 9, 10)));
      expect(stats.snapshot.summary.expenses, 16000);

      ddx = budget.transactions.singleWhere((t) => t.id == 'DDX');
      await budget.updateTransaction(
        ddx.copyWith(type: TransactionType.income),
      );
      expect(stats.snapshot.summary.expenses, 13000);
      expect(stats.snapshot.summary.income, 3000);
      ddx = budget.transactions.singleWhere((t) => t.id == 'DDX');
      await budget.updateTransaction(
        ddx.copyWith(type: TransactionType.expense),
      );
      expect(stats.snapshot.summary.expenses, 16000);

      await budget.deleteTransaction('DDX');
      expect(stats.snapshot.summary.expenses, 13000);
      expect(await budget.restoreTrashedTransactions(['DDX']), 1);
      expect(stats.snapshot.summary.expenses, 16000);
    },
  );

  test(
    'new manual expense appears and filters retain their current meaning',
    () async {
      stats.applyFilters(
        accountIds: const {'card'},
        categoryIds: const {'sports'},
        transactionTypes: const {TransactionType.expense},
        includeCash: true,
        includeLargePurchases: true,
        includeRecurring: true,
        includeRefunds: true,
        includeUncategorized: true,
        onlyConfirmed: false,
      );
      expect(stats.snapshot.summary.expenses, 5000);
      await budget.addExpense(
        period: budget.periods.single,
        amount: 1200,
        date: DateTime(2026, 9, 20),
        categoryId: 'sports',
        accountId: 'card',
        title: 'New sport expense',
      );
      expect(stats.snapshot.summary.expenses, 6200);
      expect(stats.query.categoryIds, {'sports'});
    },
  );

  test(
    'manual refresh reads local data once, preserves query and does not save',
    () async {
      stats.applyFilters(
        accountIds: const {'card'},
        categoryIds: const {'other'},
        transactionTypes: const {TransactionType.expense},
        includeCash: true,
        includeLargePurchases: true,
        includeRecurring: true,
        includeRefunds: true,
        includeUncategorized: true,
        onlyConfirmed: false,
      );
      final previousQuery = stats.query;
      final previousBuilds = calculation.calls;
      final first = stats.refreshFromLocalData();
      expect(stats.isRefreshing, isTrue);
      final duplicate = stats.refreshFromLocalData();
      expect(await duplicate, isFalse);
      expect(await first, isTrue);
      expect(stats.isRefreshing, isFalse);
      expect(calculation.calls, previousBuilds + 1);
      expect(stats.query, same(previousQuery));
      expect(stats.snapshot.summary.expenses, 10000);
      expect(saves, 0); // No persistence or bank sync entry point is touched.
    },
  );

  test(
    'failed local refresh retains last valid snapshot and permits retry',
    () async {
      final valid = stats.snapshot;
      calculation.fail = true;
      await expectLater(stats.refreshFromLocalData(), throwsStateError);
      expect(stats.snapshot, same(valid));
      expect(stats.isRefreshing, isFalse);
      calculation.fail = false;
      expect(await stats.refreshFromLocalData(), isTrue);
      expect(stats.snapshot, isNot(same(valid)));
    },
  );

  testWidgets('desktop toolbar refresh is local, compact and shows progress', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: Scaffold(
          body: DesktopBudgetAnalysisPage(
            controller: budget,
            section: StatisticsSection.expenses,
            statisticsController: stats,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StatisticsDonut>(find.byType(StatisticsDonut))
          .items
          .singleWhere((item) => item.id == 'other')
          .amount,
      10000,
    );
    await budget.changeTransactionCategory('DDX', 'sports');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StatisticsDonut>(find.byType(StatisticsDonut))
          .items
          .singleWhere((item) => item.id == 'other')
          .amount,
      8000,
    );
    final refresh = find.byKey(const Key('desktop-statistics-refresh'));
    expect(refresh, findsOneWidget);
    expect(find.byTooltip('Обновить аналитику'), findsOneWidget);
    await tester.tap(refresh);
    await tester.pump();
    expect(stats.isRefreshing, isTrue);
    expect(tester.widget<IconButton>(refresh).onPressed, isNull);
    expect(
      find.descendant(
        of: refresh,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(stats.isRefreshing, isFalse);
    expect(saves, 1); // Only the category mutation persists.
    expect(tester.takeException(), isNull);
  });

  testWidgets('open category operation list follows the live category', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: StatisticsOperationsScreen(
          controller: stats,
          title: 'Прочее',
          transactions: stats.transactionsForCategory('other'),
          transactionSelector: (source) =>
              source.transactionsForCategory('other'),
        ),
      ),
    );
    expect(find.byType(ListTile), findsNWidgets(2));
    await budget.changeTransactionCategory('DDX', 'sports');
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop refresh failure is unobtrusive and keeps the chart', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: Scaffold(
          body: DesktopBudgetAnalysisPage(
            controller: budget,
            section: StatisticsSection.expenses,
            statisticsController: stats,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final previous = stats.snapshot;
    calculation.fail = true;
    await tester.tap(find.byKey(const Key('desktop-statistics-refresh')));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(find.text('Не удалось обновить аналитику'), findsOneWidget);
    expect(stats.snapshot, same(previous));
    expect(find.byType(StatisticsDonut), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
