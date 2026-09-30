import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/desktop/pages/desktop_cash_flow_page.dart';
import 'package:qesto/desktop/widgets/desktop_charts.dart';
import 'package:qesto/desktop/widgets/money_flow_river.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/budget/transaction_details_screen.dart';
import 'package:qesto/features/statistics/presentation/screens/statistics_drilldown_screens.dart';
import 'package:qesto/features/statistics/presentation/sections/overview_expenses_sections.dart';
import 'package:qesto/features/statistics/presentation/state/statistics_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

import 'fixtures/sample_user_financial_data.dart';

void main() {
  late BudgetController budget;
  late StatisticsController statistics;

  final transactions = [
    BudgetTransaction(
      id: 'cheap-1',
      userId: 'demo-user',
      accountId: 'card-main',
      date: DateTime(2026, 9, 7, 12),
      amount: 100,
      currency: 'RUB',
      type: TransactionType.expense,
      categoryId: 'cafes',
      merchant: 'Столовая МГУ',
      isConfirmed: true,
    ),
    BudgetTransaction(
      id: 'cheap-2',
      userId: 'demo-user',
      accountId: 'card-main',
      date: DateTime(2026, 9, 9, 12),
      amount: 250,
      currency: 'RUB',
      type: TransactionType.expense,
      categoryId: 'cafes',
      merchant: 'Столовая МГУ',
      isConfirmed: true,
    ),
    BudgetTransaction(
      id: 'middle',
      userId: 'demo-user',
      accountId: 'card-main',
      date: DateTime(2026, 9, 10, 12),
      amount: 450,
      currency: 'RUB',
      type: TransactionType.expense,
      categoryId: 'groceries',
      merchant: 'Магазин',
      isConfirmed: true,
    ),
    BudgetTransaction(
      id: 'large',
      userId: 'demo-user',
      accountId: 'card-main',
      date: DateTime(2026, 9, 11, 12),
      amount: 12000,
      currency: 'RUB',
      type: TransactionType.expense,
      categoryId: 'travel',
      merchant: 'Билеты',
      isConfirmed: true,
      isLargePurchase: true,
    ),
    BudgetTransaction(
      id: 'income-1',
      userId: 'demo-user',
      accountId: 'card-main',
      date: DateTime(2026, 9, 3, 12),
      amount: 20000,
      currency: 'RUB',
      type: TransactionType.income,
      title: 'Подработка',
      isConfirmed: true,
    ),
  ];

  setUp(() {
    budget = BudgetController(
      configuration: budgetConfiguration,
      financialData: sampleUserFinancialData.copyWith(
        transactions: transactions,
      ),
    );
    statistics = StatisticsController(budgetController: budget);
    statistics.setCustomPeriod(DateTime(2026, 9), DateTime(2026, 9, 30));
  });
  tearDown(() {
    statistics.dispose();
    budget.dispose();
  });

  Future<void> pumpPage(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1440, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('merchant shows all operations inline and day click filters', (
    tester,
  ) async {
    expect(
      statistics.snapshot.merchants.map((item) => item.id).toList(),
      contains('столовая мгу'),
      reason: statistics.snapshot.transactions
          .map((item) => item.id)
          .toList()
          .toString(),
    );
    await pumpPage(
      tester,
      StatisticsMerchantScreen(
        controller: statistics,
        merchant: 'столовая мгу',
      ),
    );
    expect(find.byKey(const Key('merchant-operation-cheap-1')), findsOneWidget);
    expect(find.byKey(const Key('merchant-operation-cheap-2')), findsOneWidget);
    expect(find.text('Открыть операции'), findsNothing);
    await tester.tap(find.byKey(const Key('merchant-sort-amount')));
    await tester.pumpAndSettle();
    final tiles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where(
          (tile) =>
              tile.key is ValueKey<String> &&
              (tile.key! as ValueKey<String>).value.startsWith(
                'merchant-operation-',
              ),
        )
        .toList();
    expect(
      (tiles.first.key! as ValueKey<String>).value,
      'merchant-operation-cheap-2',
    );
    final gesture = find
        .descendant(
          of: find.byKey(const Key('merchant-chart')),
          matching: find.byType(GestureDetector),
        )
        .first;
    final rect = tester.getRect(gesture);
    await tester.tapAt(rect.topLeft + Offset(rect.width * 6 / 29, 90));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('merchant-day-filter')), findsOneWidget);
    expect(find.byKey(const Key('merchant-operation-cheap-1')), findsOneWidget);
    expect(find.byKey(const Key('merchant-operation-cheap-2')), findsNothing);
  });

  testWidgets('amount bucket opens only purchases in its exact range', (
    tester,
  ) async {
    await pumpPage(
      tester,
      ExpensesStatisticsSection(
        controller: statistics,
        scrollController: ScrollController(),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('amount-bucket-0')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('amount-bucket-0')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('statistics-operation-cheap-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('statistics-operation-cheap-2')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('statistics-operation-middle')), findsNothing);
    expect(find.byKey(const Key('statistics-operation-large')), findsNothing);
  });

  testWidgets('cash flow source row opens period-scoped income operations', (
    tester,
  ) async {
    await pumpPage(tester, DesktopCashFlowPage(controller: budget));
    final source = find.byKey(const Key('cash-flow-breakdown-Подработка'));
    await tester.ensureVisible(source);
    await tester.tap(source);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('budget-drilldown-operation-income-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('budget-drilldown-operation-cheap-1')),
      findsNothing,
    );
  });

  testWidgets(
    'large-purchase aggregate and single row use the right destinations',
    (tester) async {
      await pumpPage(
        tester,
        ExpensesStatisticsSection(
          controller: statistics,
          scrollController: ScrollController(),
        ),
      );
      final largeLegend = find.byKey(const Key('large-purchases-legend'));
      await tester.scrollUntilVisible(
        largeLegend,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.tap(largeLegend);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('statistics-operation-large')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('statistics-operation-middle')),
        findsNothing,
      );
      Navigator.of(
        tester.element(find.byKey(const Key('statistics-operation-large'))),
      ).pop();
      await tester.pumpAndSettle();
      final single = find.byKey(const Key('largest-operation-large'));
      await tester.scrollUntilVisible(
        single,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -450));
      await tester.pumpAndSettle();
      await tester.tap(single);
      await tester.pumpAndSettle();
      expect(find.byType(TransactionDetailsScreen), findsOneWidget);
    },
  );

  testWidgets(
    'cash flow category reuses category detail with exact operations',
    (tester) async {
      await pumpPage(tester, DesktopCashFlowPage(controller: budget));
      final category = find.byKey(const Key('cash-flow-breakdown-Кафе'));
      await tester.ensureVisible(category);
      await tester.tap(category);
      await tester.pumpAndSettle();
      expect(find.byType(StatisticsCategoryScreen), findsOneWidget);
      expect(
        find.byKey(const Key('category-operation-cheap-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('category-operation-cheap-2')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('category-operation-middle')), findsNothing);
      final original = budget.transactions.firstWhere(
        (item) => item.id == 'cheap-1',
      );
      await budget.updateTransaction(original.copyWith(amount: 180));
      await tester.pumpAndSettle();
      expect(find.text('180 ₽'), findsWidgets);
    },
  );

  testWidgets(
    'cash flow bar opens only selected month with income and expenses',
    (tester) async {
      await pumpPage(tester, DesktopCashFlowPage(controller: budget));
      final chart = find.byType(CashFlowBarChart);
      await tester.ensureVisible(chart);
      await tester.tapAt(
        tester.getRect(chart).centerRight - const Offset(10, 0),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Доходы:'), findsOneWidget);
      expect(find.textContaining('Расходы:'), findsOneWidget);
      expect(
        find.byKey(const Key('cashflow-income-operation-income-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('cashflow-expense-operation-cheap-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets('money-flow river exposes category and purchase hit targets', (
    tester,
  ) async {
    final tapped = <String>[];
    await pumpPage(
      tester,
      SizedBox(
        width: 1200,
        child: MoneyFlowRiver(
          income: 1000,
          expenses: 800,
          categories: const [
            MoneyFlowCategory(
              id: 'cafes',
              label: 'Кафе',
              amount: 800,
              color: Colors.orange,
              iconKey: 'cafe',
              purchases: [
                MoneyFlowPurchase(label: 'Столовая МГУ', amount: 800),
              ],
            ),
          ],
          currency: 'RUB',
          onNodeTap: tapped.add,
        ),
      ),
    );
    final rect = tester.getRect(find.byType(MoneyFlowRiver));
    await tester.tapAt(rect.topLeft + const Offset(90, 120));
    await tester.pump();
    await tester.tapAt(rect.topLeft + Offset(rect.width * 0.45, 120));
    await tester.pump();
    await tester.tapAt(rect.topLeft + Offset(rect.width * 0.80, 120));
    await tester.pump();
    expect(tapped, containsAll(['root', 'category-cafes', 'purchase-cafes-0']));
  });
}
