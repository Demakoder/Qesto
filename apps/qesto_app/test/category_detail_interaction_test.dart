import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/category_details_screen.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

import 'fixtures/sample_user_financial_data.dart';

void main() {
  late BudgetController budget;
  late BudgetPeriod period;

  setUp(() {
    budget = BudgetController(
      configuration: budgetConfiguration,
      financialData: sampleUserFinancialData,
    );
    period = budget.periods.firstWhere((item) => item.month == 7);
  });
  tearDown(() => budget.dispose());

  Future<void> openCategory(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: CategoryDetailsScreen(
          controller: budget,
          period: period,
          categoryId: 'groceries',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> operationIds(WidgetTester tester) => tester
      .widgetList<ListTile>(
        find.byWidgetPredicate(
          (widget) =>
              widget is ListTile &&
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'category-operation-',
              ),
        ),
      )
      .map(
        (tile) => (tile.key! as ValueKey<String>).value.replaceFirst(
          'category-operation-',
          '',
        ),
      )
      .toList();

  Finder sourceNamed(String fragment) => find.byWidgetPredicate(
    (widget) =>
        widget is ListTile &&
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.toLowerCase().contains(
          fragment.toLowerCase(),
        ),
  );

  testWidgets('all category operations are inline; merchant filters locally', (
    tester,
  ) async {
    await openCategory(tester);
    expect(operationIds(tester).toSet(), {
      'jul-g1',
      'jul-g2',
      'jul-g3',
      'jul-g4',
      'jul-g5',
      'jul-g6',
      'jul-r1',
    });
    expect(find.text('Открыть операции'), findsNothing);
    await tester.tap(sourceNamed('пят'));
    await tester.pumpAndSettle();
    expect(operationIds(tester), ['jul-g1']);
    expect(find.byKey(const Key('category-merchant-filter')), findsOneWidget);
  });

  testWidgets('date, amount and merchant sorts toggle direction', (
    tester,
  ) async {
    await openCategory(tester);
    await tester.tap(find.byKey(const Key('category-sort-date')));
    await tester.pumpAndSettle();
    expect(operationIds(tester).first, 'jul-r1');
    await tester.tap(find.byKey(const Key('category-sort-date')));
    await tester.pumpAndSettle();
    expect(operationIds(tester).first, 'jul-g1');

    await tester.tap(find.byKey(const Key('category-sort-amount')));
    await tester.pumpAndSettle();
    expect(operationIds(tester).first, 'jul-g3');
    await tester.tap(find.byKey(const Key('category-sort-amount')));
    await tester.pumpAndSettle();
    expect(operationIds(tester).first, 'jul-r1');

    await tester.tap(find.byKey(const Key('category-sort-merchant')));
    await tester.pumpAndSettle();
    final ascending = operationIds(tester);
    await tester.tap(find.byKey(const Key('category-sort-merchant')));
    await tester.pumpAndSettle();
    expect(operationIds(tester).first, ascending.last);
    expect(operationIds(tester).last, ascending.first);
  });

  testWidgets('chart day and merchant combine; edits refresh the category', (
    tester,
  ) async {
    await openCategory(tester);
    final chartGesture = find
        .descendant(
          of: find.byKey(const Key('category-chart')),
          matching: find.byType(GestureDetector),
        )
        .first;
    final chartRect = tester.getRect(chartGesture);
    await tester.tapAt(chartRect.topLeft + const Offset(2, 90));
    await tester.pumpAndSettle();
    expect(operationIds(tester), ['jul-g1']);
    expect(find.byKey(const Key('category-day-filter')), findsOneWidget);
    await tester.tap(sourceNamed('пят'));
    await tester.pumpAndSettle();
    expect(operationIds(tester), ['jul-g1']);
    await tester.tap(find.text('Сбросить фильтр'));
    await tester.pumpAndSettle();

    final original = budget.transactions.firstWhere((t) => t.id == 'jul-g1');
    await budget.updateTransaction(original.copyWith(amount: 4000));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('category-operation-jul-g1')),
              matching: find.text('4 000 ₽'),
            ),
          )
          .data,
      '4 000 ₽',
    );
  });

  testWidgets('income category uses same detail with source semantics', (
    tester,
  ) async {
    budget.dispose();
    final income = BudgetTransaction(
      id: 'income-groceries',
      userId: 'demo-user',
      accountId: 'card-main',
      date: DateTime(2026, 7, 14),
      amount: 15000,
      currency: 'RUB',
      type: TransactionType.income,
      categoryId: 'groceries',
      title: 'Подработка',
    );
    budget = BudgetController(
      configuration: budgetConfiguration,
      financialData: sampleUserFinancialData.copyWith(transactions: [income]),
    );
    period = budget.periods.firstWhere((item) => item.month == 7);
    await openCategory(tester);
    expect(find.text('Источники категории'), findsOneWidget);
    expect(find.text('Доходы'), findsOneWidget);
    expect(operationIds(tester), ['income-groceries']);
    await tester.tap(
      find.byKey(const Key('category-operation-income-groceries')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Источник'), findsOneWidget);
    expect(find.text('Доход'), findsOneWidget);
  });

  testWidgets('large category reveals every operation in batches', (
    tester,
  ) async {
    budget.dispose();
    final rows = [
      for (var index = 0; index < 45; index++)
        BudgetTransaction(
          id: 'many-$index',
          userId: 'demo-user',
          accountId: 'card-main',
          date: DateTime(2026, 7, 1 + index ~/ 3, index % 3),
          amount: index + 100,
          currency: 'RUB',
          type: TransactionType.expense,
          categoryId: 'groceries',
          merchant: 'Магазин $index',
        ),
    ];
    budget = BudgetController(
      configuration: budgetConfiguration,
      financialData: sampleUserFinancialData.copyWith(transactions: rows),
    );
    period = budget.periods.firstWhere((item) => item.month == 7);
    await openCategory(tester);
    expect(operationIds(tester), hasLength(30));
    expect(find.byKey(const Key('category-load-more')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('category-load-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('category-load-more')));
    await tester.pumpAndSettle();
    expect(operationIds(tester), hasLength(45));
    expect(find.byKey(const Key('category-load-more')), findsNothing);
  });

  testWidgets('category detail remains usable on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: CategoryDetailsScreen(
          controller: budget,
          period: period,
          categoryId: 'groceries',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('category-sort-date')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('category-sort-date')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
