import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/desktop/overview/desktop_overview_data.dart';
import 'package:qesto/desktop/overview/overview_drilldown_panel.dart';
import 'package:qesto/desktop/overview/overview_expense_map.dart';
import 'package:qesto/desktop/overview/overview_expense_trend_chart.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

import 'fixtures/sample_user_financial_data.dart';

void main() {
  late BudgetController controller;
  late BudgetPeriod period;

  setUp(() {
    controller = BudgetController(
      configuration: budgetConfiguration,
      financialData: sampleUserFinancialData,
    );
    period = controller.periods.firstWhere(
      (p) => p.year == 2026 && p.month == 7,
    );
  });
  tearDown(() => controller.dispose());

  test('day selection includes only eligible expenses on that date', () {
    final day = DateTime(2026, 7, 19);
    final data = OverviewDrilldownData.forTrend(
      controller: controller,
      period: period,
      selection: OverviewTrendSelection(
        from: day,
        through: day,
        cumulativeAmount: 46700,
      ),
    );
    expect(data.title, '19 июля 2026');
    expect(data.amount, 1600);
    expect(data.transactions.map((item) => item.id), ['jul-c7']);
  });

  test('weekly selection means the full interval after the prior sample', () {
    final points = [
      OverviewTrendPoint(date: DateTime(2026, 7, 7), amount: 8000),
      OverviewTrendPoint(date: DateTime(2026, 7, 14), amount: 22000),
      OverviewTrendPoint(date: DateTime(2026, 7, 19), amount: 46700),
    ];
    final first = overviewTrendSelection(
      points,
      OverviewTrendGranularity.weeks,
      0,
      DateTime(2026, 7),
    );
    expect(first.from, DateTime(2026, 7));
    expect(first.through, DateTime(2026, 7, 7));
    final second = overviewTrendSelection(
      points,
      OverviewTrendGranularity.weeks,
      1,
      DateTime(2026, 7),
    );
    expect(second.from, DateTime(2026, 7, 8));
    expect(second.through, DateTime(2026, 7, 14));
    final data = OverviewDrilldownData.forTrend(
      controller: controller,
      period: period,
      selection: second,
    );
    expect(
      data.transactions.every(
        (item) =>
            !item.date.isBefore(DateTime(2026, 7, 8)) &&
            item.date.isBefore(DateTime(2026, 7, 15)),
      ),
      isTrue,
    );
    expect(data.transactions.any((item) => item.id == 'jul-transfer'), isFalse);
  });

  test('category and destination use model IDs, not tooltip text', () {
    final flow = DesktopOverviewData.build(controller, period).flow!;
    final branch = flow.branches.firstWhere((item) => item.id == 'groceries');
    final category = OverviewDrilldownData.forFlow(
      controller: controller,
      period: period,
      selection: OverviewFlowSelection(
        kind: OverviewFlowSelectionKind.category,
        id: branch.id,
        label: branch.label,
        amount: branch.amount,
        transactionIds: branch.transactionIds,
      ),
    );
    expect(category.transactions, isNotEmpty);
    expect(
      category.transactions.every((item) => item.categoryId == 'groceries'),
      isTrue,
    );
    expect(
      category.transactions.any((item) => item.type == TransactionType.income),
      isFalse,
    );

    final destination = branch.destinations.firstWhere(
      (item) => item.transactionIds.length == 1,
    );
    final single = OverviewDrilldownData.forFlow(
      controller: controller,
      period: period,
      selection: OverviewFlowSelection(
        kind: OverviewFlowSelectionKind.destination,
        id: destination.id,
        label: destination.label,
        amount: destination.amount,
        transactionIds: destination.transactionIds,
      ),
    );
    expect(
      single.transactions.map((item) => item.id),
      destination.transactionIds,
    );
  });

  test('calculated remainder never fabricates a transaction', () {
    final flow = DesktopOverviewData.build(controller, period).flow!;
    final branch = flow.branches.firstWhere(
      (item) => item.id == 'remaining-income',
    );
    final data = OverviewDrilldownData.forFlow(
      controller: controller,
      period: period,
      selection: OverviewFlowSelection(
        kind: OverviewFlowSelectionKind.category,
        id: branch.id,
        label: branch.label,
        amount: branch.amount,
        transactionIds: branch.transactionIds,
      ),
    );
    expect(data.transactions, isEmpty);
    expect(data.explanation, contains('разница'));
  });

  test('merchant identity uses existing normalized name, not raw variants', () {
    final variants = [
      BudgetTransaction(
        id: 'merchant-a',
        userId: 'demo-user',
        accountId: 'card-main',
        date: DateTime(2026, 7, 8, 12),
        amount: 400,
        currency: 'RUB',
        type: TransactionType.expense,
        merchant: 'BURGER KING RUS',
        normalizedMerchant: 'Burger King',
      ),
      BudgetTransaction(
        id: 'merchant-b',
        userId: 'demo-user',
        accountId: 'card-main',
        date: DateTime(2026, 7, 8, 13),
        amount: 600,
        currency: 'RUB',
        type: TransactionType.expense,
        merchant: 'Burger King Moscow',
        normalizedMerchant: 'burger  king',
      ),
    ];
    final summary = OverviewMerchantSummary.fromTransactions(
      controller,
      variants,
    );
    expect(summary.uniqueCount, 1);
    expect(summary.total, 1000);
    expect(summary.top?.count, 2);
    expect(summary.top?.label, 'Burger King');
  });

  test('merchant chart caps slices and aggregates the rest', () {
    final transactions = controller
        .transactionsFor(period)
        .where((item) => controller.calculationService.signedExpense(item) > 0);
    final summary = OverviewMerchantSummary.fromTransactions(
      controller,
      transactions,
    );
    expect(summary.uniqueCount, greaterThan(5));
    expect(summary.visualGroups, hasLength(6));
    expect(summary.visualGroups.last.label, 'Прочие продавцы');
    expect(
      summary.visualGroups.fold<int>(0, (sum, item) => sum + item.amount),
      summary.total,
    );
  });

  test('merchant and category drilldowns keep the selected month', () {
    final selected = controller
        .transactionsFor(period)
        .firstWhere((item) => item.id == 'jul-t1');
    final merchant = OverviewDrilldownData.forMerchant(
      controller: controller,
      period: period,
      selected: selected,
    );
    expect(
      merchant.transactions.map((item) => item.id),
      containsAll(['jul-t1', 'jul-t3', 'jul-t5']),
    );
    expect(
      merchant.transactions.every((item) => period.contains(item.date)),
      isTrue,
    );

    final row = DesktopOverviewData.build(
      controller,
      period,
    ).categoryBudgets.firstWhere((item) => item.id == 'groceries');
    final category = OverviewDrilldownData.forCategory(
      controller: controller,
      period: period,
      category: row,
    );
    expect(category.showMerchantAnalysis, isTrue);
    expect(category.transactions.any((item) => item.id == 'jul-r1'), isTrue);
    expect(
      category.transactions.every((item) => item.categoryId == 'groceries'),
      isTrue,
    );
  });

  test('operation sorting respects amount, time, and merchant', () {
    final items = controller
        .transactionsFor(period)
        .where((item) => {'jul-c1', 'jul-c2', 'jul-c3'}.contains(item.id));
    expect(
      sortOverviewDrilldownTransactions(
        items,
        OverviewDrilldownSort.amountDescending,
      ).map((item) => item.id),
      ['jul-c2', 'jul-c1', 'jul-c3'],
    );
    expect(
      sortOverviewDrilldownTransactions(
        items,
        OverviewDrilldownSort.amountAscending,
      ).map((item) => item.id),
      ['jul-c3', 'jul-c1', 'jul-c2'],
    );
    expect(
      sortOverviewDrilldownTransactions(
        items,
        OverviewDrilldownSort.dateDescending,
      ).map((item) => item.id),
      ['jul-c3', 'jul-c2', 'jul-c1'],
    );
    expect(
      sortOverviewDrilldownTransactions(
        items,
        OverviewDrilldownSort.merchant,
      ).map(overviewMerchantKey),
      orderedEquals(['surf coffee', 'даблби', 'хлеб насущный']),
    );
  });

  testWidgets(
    'trend click reports the selected point and keeps hover support',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 500);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      OverviewTrendSelection? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              child: OverviewExpenseTrendChart(
                points: [
                  OverviewTrendPoint(date: DateTime(2026, 7, 1), amount: 100),
                  OverviewTrendPoint(date: DateTime(2026, 7, 2), amount: 500),
                ],
                currency: 'RUB',
                granularity: OverviewTrendGranularity.days,
                onSelection: (value) => chosen = value,
              ),
            ),
          ),
        ),
      );
      final rect = tester.getRect(
        find.byKey(const Key('overview-trend-hit-area')),
      );
      await tester.tapAt(Offset(rect.right - 16, rect.center.dy));
      await tester.pump();
      expect(chosen?.from, DateTime(2026, 7, 2));
      expect(find.text('Нажмите, чтобы увидеть операции'), findsOneWidget);
    },
  );

  testWidgets('map category and right-hand operation are clickable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final flow = DesktopOverviewData.build(controller, period).flow!;
    OverviewFlowSelection? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: OverviewExpenseMap(
              data: flow,
              onSelection: (value) => chosen = value,
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(
      find.byKey(const Key('overview-flow-hit-area')),
    );
    await tester.tapAt(Offset(rect.left + rect.width * .62, rect.top + 50));
    await tester.pump();
    expect(chosen?.kind, OverviewFlowSelectionKind.category);
    expect(chosen?.transactionIds, isNotEmpty);

    await tester.tapAt(Offset(rect.left + rect.width * .88, rect.top + 50));
    await tester.pump();
    expect(chosen?.kind, OverviewFlowSelectionKind.destination);
    expect(chosen?.transactionIds, isNotEmpty);
  });

  testWidgets(
    'right-side operation drilldown opens the existing detail route',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final flow = DesktopOverviewData.build(controller, period).flow!;
      final destination = flow.branches
          .firstWhere((branch) => branch.id == 'groceries')
          .destinations
          .firstWhere((item) => item.transactionIds.length == 1);
      final data = OverviewDrilldownData.forFlow(
        controller: controller,
        period: period,
        selection: OverviewFlowSelection(
          kind: OverviewFlowSelectionKind.destination,
          id: destination.id,
          label: destination.label,
          amount: destination.amount,
          transactionIds: destination.transactionIds,
        ),
      );
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showOverviewDrilldownPanel(
                  context,
                  controller: controller,
                  data: data,
                  onOpenTransaction: (id) => opened = id,
                  onOpenTransactions: (_) {},
                ),
                child: const Text('Открыть карту'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть карту'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overview-drilldown-panel')), findsOneWidget);
      final transactionRow = find.byKey(
        Key(
          'overview-drilldown-transaction-${destination.transactionIds.single}',
        ),
      );
      await tester.scrollUntilVisible(
        transactionRow,
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(transactionRow);
      await tester.pumpAndSettle();
      expect(opened, destination.transactionIds.single);
      expect(find.byKey(const Key('overview-drilldown-panel')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category drawer shows mini charts, sorting and merchant groups',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final row = DesktopOverviewData.build(
        controller,
        period,
      ).categoryBudgets.firstWhere((item) => item.id == 'groceries');
      final data = OverviewDrilldownData.forCategory(
        controller: controller,
        period: period,
        category: row,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showOverviewDrilldownPanel(
                  context,
                  controller: controller,
                  data: data,
                  onOpenTransaction: (_) {},
                  onOpenTransactions: (_) {},
                ),
                child: const Text('Открыть категорию'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть категорию'));
      await tester.pumpAndSettle();
      expect(find.text('Уникальных продавцов'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('overview-merchant-donut')),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overview-merchant-donut')), findsOneWidget);
      expect(find.byKey(const Key('overview-merchant-bars')), findsOneWidget);
      final sort = find.byKey(const Key('overview-drilldown-sort'));
      await tester.ensureVisible(sort);
      await tester.tap(sort);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сначала дорогие').last);
      await tester.pumpAndSettle();
      final listTileKeys = find
          .byType(ListTile)
          .evaluate()
          .map((element) => element.widget.key);
      expect(
        listTileKeys.first,
        const Key('overview-drilldown-transaction-jul-g3'),
      );
      final group = find.byKey(const Key('overview-drilldown-group-merchants'));
      await tester.ensureVisible(group);
      await tester.tap(group);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('overview-merchant-group-пятёрочка')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
