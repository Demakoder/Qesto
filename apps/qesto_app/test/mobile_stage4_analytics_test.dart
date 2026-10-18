import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/desktop/desktop_app_shell.dart';
import 'package:qesto/desktop/desktop_financial_helpers.dart';
import 'package:qesto/desktop/overview/desktop_overview_data.dart';
import 'package:qesto/desktop/pages/desktop_transactions_page.dart';
import 'package:qesto/features/budget/services/cash_flow_calculation_service.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/statistics/domain/models/statistics_models.dart';
import 'package:qesto/features/statistics/presentation/screens/statistics_screen.dart';
import 'package:qesto/features/statistics/presentation/state/analytics_presentation_selectors.dart';
import 'package:qesto/features/statistics/presentation/state/statistics_controller.dart';
import 'package:qesto/features/statistics/presentation/widgets/statistics_charts.dart';
import 'package:qesto/mobile/analytics/mobile_analysis_page.dart';
import 'package:qesto/mobile/analytics/mobile_budget_page.dart';
import 'package:qesto/mobile/analytics/mobile_financial_widgets.dart';
import 'package:qesto/mobile/analytics/mobile_overview_page.dart';
import 'package:qesto/mobile/analytics/mobile_statistics_controls.dart';
import 'package:qesto/mobile/transactions/mobile_transaction_detail.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';
import 'fixtures/mobile_stage4_data.dart';

BudgetController fixture([String kind = 'typical']) => BudgetController(
  configuration: budgetConfiguration,
  financialData: stage4Data(kind),
);
void main() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    for (final kind in stage4Cases) {
      testWidgets(
        'Stage 4 Overview/Budget $width $kind whole scroll no overflow',
        (tester) async {
          tester.view
            ..physicalSize = Size(width, 844)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final c = fixture(kind);
          addTearDown(c.dispose);
          final p = c.periods.firstWhere(
            (p) => p.contains(c.referenceDate),
            orElse: () => c.periods.last,
          );
          final before = const UserFinancialDataCodec().encode(
            c.mergeInto(stage4Data(kind)),
          );
          final screens = [
            MobileOverviewPage(
              controller: c,
              period: p,
              onOpenDestination: (_) {},
              onOpenTransaction: (_) {},
              onOpenFilteredTransactions: (_) {},
            ),
            MobileBudgetPage(controller: c, onOpenFilteredTransactions: (_) {}),
          ];
          for (final screen in screens) {
            await tester.pumpWidget(
              MaterialApp(
                key: UniqueKey(),
                theme: buildQestoTheme(),
                home: Scaffold(
                  appBar: AppBar(title: const Text('Qesto')),
                  body: screen,
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$width $kind top');
            if (kind == 'empty' && screen is MobileOverviewPage) {
              expect(
                find.text('Данные о капитале ещё не добавлены'),
                findsOneWidget,
              );
              expect(
                find.byKey(const Key('mobile-overview-capital')),
                findsNothing,
              );
            }
            final scroll = tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position;
            for (
              var offset = 0.0;
              offset <= scroll.maxScrollExtent;
              offset += 350
            ) {
              scroll.jumpTo(offset);
              await tester.pump();
              expect(
                tester.takeException(),
                isNull,
                reason: '$width $kind $offset',
              );
            }
            scroll.jumpTo(scroll.maxScrollExtent);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          expect(
            const UserFinancialDataCodec().encode(
              c.mergeInto(stage4Data(kind)),
            ),
            before,
            reason: 'presentation must not mutate ledger/plans/schema',
          );
          await tester.pumpWidget(const SizedBox());
        },
        variant: android,
      );
    }
  }
  testWidgets('Overview and Budget render existing desktop read-model values', (
    tester,
  ) async {
    final c = fixture();
    addTearDown(c.dispose);
    final p = c.periods.firstWhere((p) => p.contains(c.referenceDate));
    final data = DesktopOverviewData.build(c, p);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: Scaffold(
          body: MobileOverviewPage(
            controller: c,
            period: p,
            onOpenDestination: (_) {},
            onOpenTransaction: (_) {},
            onOpenFilteredTransactions: (_) {},
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<MobileMoney>(find.byKey(const Key('mobile-overview-capital')))
          .amount,
      data.capital,
    );
    expect(
      tester
          .widget<MobileMetric>(
            find.byKey(const Key('mobile-overview-expenses')),
          )
          .amount,
      data.expenses,
    );
    expect(
      tester
          .widget<MobileMetric>(find.byKey(const Key('mobile-overview-net')))
          .amount,
      data.cashFlow,
    );
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: Scaffold(
          body: MobileBudgetPage(
            controller: c,
            onOpenFilteredTransactions: (_) {},
          ),
        ),
      ),
    );
    final spent = find.byWidgetPredicate(
      (w) => w is MobileValueRow && w.title == 'Потрачено',
    );
    expect(
      tester.widget<MobileValueRow>(spent).amount,
      c.summaryFor(p).currentExpense,
    );
    expect(
      tester.widget<MobileValueRow>(spent).progress,
      c.summaryFor(p).progress,
    );
  });
  testWidgets(
    'analytics parity, comparison absence, privacy and touch survive local refresh',
    (tester) async {
      tester.view
        ..physicalSize = const Size(320, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = fixture('no-comparison');
      addTearDown(c.dispose);
      final s = StatisticsController(budgetController: c);
      addTearDown(s.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildQestoTheme(),
          home: MobileAnalysisPage(
            controller: c,
            section: StatisticsSection.expenses,
            onOpenFilteredTransactions: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<MobileMoney>(find.byType(MobileMoney).first).amount,
        s.snapshot.summary.expenses,
      );
      expect(
        find.text('Нет сопоставимых данных для сравнения'),
        findsOneWidget,
      );
      final chart = find.byType(StatisticsLineChartCard);
      await tester.scrollUntilVisible(
        chart,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      final before = tester.widget<StatisticsLineChartCard>(chart);
      final date = before.points[3].date;
      before.onDaySelected!(date);
      await tester.pumpAndSettle();
      expect(tester.widget<StatisticsLineChartCard>(chart).selectedDate, date);
      c.refreshLocalReadModel();
      await tester.pumpAndSettle();
      expect(tester.widget<StatisticsLineChartCard>(chart).selectedDate, date);
      await tester.tap(find.byKey(const Key('mobile-analysis-privacy')));
      await tester.pumpAndSettle();
      expect(find.byType(StatisticsLineChartCard), findsNothing);
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).last)
          .position;
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MobileMoney>(find.byType(MobileMoney).first).hidden,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          home: MobileAnalysisPage(
            controller: c,
            section: StatisticsSection.cashFlow,
            onOpenFilteredTransactions: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final flow = c.cashFlowForRange(
        from: s.query.period.start,
        toExclusive: s.query.period.end.add(const Duration(days: 1)),
        currency: c.user.defaultCurrency,
      );
      expect(
        tester.widget<MobileMoney>(find.byType(MobileMoney).first).amount,
        flow.netCashFlow,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'failed local refresh retains last Overview snapshot and exposes retry',
    (tester) async {
      final c = _FailingController();
      addTearDown(c.dispose);
      final p = c.periods.firstWhere((p) => p.contains(c.referenceDate));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MobileOverviewPage(
              controller: c,
              period: p,
              onOpenDestination: (_) {},
              onOpenTransaction: (_) {},
              onOpenFilteredTransactions: (_) {},
            ),
          ),
        ),
      );
      final value = tester
          .widget<MobileMoney>(find.byKey(const Key('mobile-overview-capital')))
          .amount;
      c.fail = true;
      await tester.tap(find.byKey(const Key('overview-refresh')));
      await tester.pumpAndSettle();
      expect(find.byType(MobileReadError), findsOneWidget);
      expect(
        tester
            .widget<MobileMoney>(
              find.byKey(const Key('mobile-overview-capital')),
            )
            .amount,
        value,
      );
      c.fail = false;
      tester.widget<MobileReadError>(find.byType(MobileReadError)).onRetry();
      await tester.pumpAndSettle();
      expect(find.byType(MobileReadError), findsNothing);
    },
  );
  testWidgets('320px large text budget and privacy states remain readable', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = fixture('huge');
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: MobileBudgetPage(
            controller: c,
            onOpenFilteredTransactions: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Скрыть суммы'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MobileMoney>(find.byType(MobileMoney).first).hidden,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'Shared desktop cash flow and rhythm extraction preserves previous grouping',
    () {
      final c = fixture();
      addTearDown(c.dispose);
      final s = StatisticsController(budgetController: c);
      addTearDown(s.dispose);
      final rows = s.snapshot.transactions;
      for (final treatment in [
        CashFlowTreatment.externalInflow,
        CashFlowTreatment.externalOutflow,
      ]) {
        final old = <String, int>{};
        for (final t in rows.where(
          (t) => c.cashFlowTreatment(t) == treatment,
        )) {
          final key = treatment == CashFlowTreatment.externalInflow
              ? desktopTransactionTitle(t)
              : desktopCategoryName(c, t);
          old.update(key, (v) => v + t.amount, ifAbsent: () => t.amount);
        }
        expect(cashFlowDisplayGroups(c, rows, treatment), old);
        final ids = cashFlowDisplayMembers(
          c,
          rows,
          treatment,
        ).values.expand((l) => l).map((t) => t.id).toList();
        expect(
          ids.toSet(),
          rows
              .where((t) => c.cashFlowTreatment(t) == treatment)
              .map((t) => t.id)
              .toSet(),
        );
        expect(ids.length, ids.toSet().length);
      }
      final oldWeeks = <int, int>{};
      for (final p in s.snapshot.daily) {
        final week = p.date.difference(s.query.period.start).inDays ~/ 7 + 1;
        oldWeeks.update(week, (v) => v + p.amount, ifAbsent: () => p.amount);
      }
      expect(rhythmWeekAmounts(s), oldWeeks);
      final cycle = rhythmSalaryCycle(s)!;
      final incomeDay = rows.firstWhere((t) => t.type.name == 'income').date;
      expect(cycle.day, incomeDay);
      expect(
        cycle.expenses,
        rows
            .where(s.calculationService.isConsumerExpense)
            .where(
              (t) =>
                  !t.date.isBefore(incomeDay) &&
                  t.date.difference(incomeDay).inDays < 5,
            )
            .fold<int>(0, (v, t) => v + s.calculationService.signedExpense(t)),
      );
    },
  );
  testWidgets(
    'active filters remove one/reset all; sheet preserves tags until explicit reset',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      final s = StatisticsController(budgetController: c);
      addTearDown(s.dispose);
      applyMobileFilters(
        s,
        s.query.copyWith(
          categoryIds: {'groceries', 'cafes'},
          tagIds: {'review-tag'},
          includeCash: false,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: s,
              builder: (context, _) => Column(
                children: [
                  MobileActiveFilters(controller: s),
                  TextButton(
                    onPressed: () =>
                        showStatisticsFilterSheet(context, s, compact: true),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('mobile-filter-category-groceries')),
          matching: find.byTooltip('Delete'),
        ),
      );
      await tester.pumpAndSettle();
      expect(s.query.categoryIds, {'cafes'});
      expect(s.query.tagIds, {'review-tag'});
      expect(s.query.includeCash, isFalse);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('statistics-apply-filters')));
      await tester.pumpAndSettle();
      expect(s.query.tagIds, {'review-tag'});
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сбросить'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('statistics-apply-filters')));
      await tester.pumpAndSettle();
      expect(s.query.activeFilterCount, 0);
      applyMobileFilters(s, s.query.copyWith(categoryIds: {'cafes'}));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mobile-reset-filters')));
      await tester.pumpAndSettle();
      expect(s.query.activeFilterCount, 0);
    },
  );
  testWidgets(
    'budget editor cancel read-only; repeat save stable category budget ID',
    (tester) async {
      final c = fixture();
      addTearDown(c.dispose);
      final p = c.periods.firstWhere((p) => p.contains(c.referenceDate));
      final before = const UserFinancialDataCodec().encode(
        c.mergeInto(stage4Data('typical')),
      );
      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => MobileBudgetLimitEditor(
                        controller: c,
                        periodId: p.id,
                        categoryId: 'groceries',
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
      }

      await open();
      await tester.enterText(
        find.byKey(const Key('mobile-budget-limit-amount')),
        '123',
      );
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(
        const UserFinancialDataCodec().encode(
          c.mergeInto(stage4Data('typical')),
        ),
        before,
      );
      for (var i = 0; i < 2; i++) {
        await open();
        await tester.enterText(
          find.byKey(const Key('mobile-budget-limit-amount')),
          '123',
        );
        await tester.tap(find.byKey(const Key('mobile-budget-limit-save')));
        await tester.pumpAndSettle();
      }
      final plans = c.categoryBudgets
          .where((b) => b.budgetPeriodId == p.id && b.categoryId == 'groceries')
          .toList();
      expect(plans.length, 1);
      expect(plans.single.plannedAmount, 123);
    },
  );
  testWidgets(
    'Overview analytics exact operations detail Back preserves route and period',
    (tester) async {
      await boot(tester);
      final overview = tester.state(find.byType(MobileOverviewPage));
      final page = tester.widget<MobileOverviewPage>(
        find.byType(MobileOverviewPage),
      );
      await tester.tap(find.byKey(const Key('mobile-overview-expenses')));
      await tester.pumpAndSettle();
      final analysis = tester.widget<MobileAnalysisPage>(
        find.byType(MobileAnalysisPage),
      );
      final state = tester.state(find.byType(MobileAnalysisPage));
      expect(analysis.initialRange!.start, page.period.startDate);
      await tester.scrollUntilVisible(
        find.text('Все операции расходов'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Все операции расходов'));
      await tester.pumpAndSettle();
      final ops = tester.widget<DesktopTransactionsPage>(
        find.byType(DesktopTransactionsPage),
      );
      final s = StatisticsController(budgetController: analysis.controller);
      addTearDown(s.dispose);
      s.setCustomPeriod(
        analysis.initialRange!.start,
        analysis.initialRange!.end,
      );
      expect(
        ops.initialTransactionIds!.toSet(),
        s.snapshot.transactions
            .where(s.calculationService.isConsumerExpense)
            .map((t) => t.id)
            .toSet(),
      );
      ops.onOpenTransaction!(ops.initialTransactionIds!.first);
      await tester.pumpAndSettle();
      expect(find.byType(MobileTransactionDetail), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(MobileAnalysisPage)), same(state));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(MobileOverviewPage)), same(overview));
    },
    variant: android,
  );
  testWidgets(
    'Budget category exact operations detail Back retains budget root',
    (tester) async {
      await boot(tester);
      await tester.tap(find.byKey(const Key('mobile-root-budget')));
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(MobileBudgetPage));
      final c = tester
          .widget<DesktopAppShell>(find.byType(DesktopAppShell))
          .controller;
      final p = c.periods.firstWhere((p) => p.contains(c.referenceDate));
      final category = c.categoryPlansFor(p).first.category;
      final link = find.byWidgetPredicate(
        (w) => w is MobileValueRow && w.title == category.name,
      );
      await tester.scrollUntilVisible(
        link,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(link);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('mobile-budget-category-operations')),
      );
      await tester.pumpAndSettle();
      final ops = tester.widget<DesktopTransactionsPage>(
        find.byType(DesktopTransactionsPage),
      );
      expect(
        ops.initialTransactionIds!.toSet(),
        c.transactionsForCategory(p, category.id).map((t) => t.id).toSet(),
      );
      ops.onOpenTransaction!(ops.initialTransactionIds!.first);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MobileBudgetCategoryPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(MobileBudgetPage)), same(state));
    },
    variant: android,
  );
}

class _FailingController extends BudgetController {
  _FailingController()
    : super(
        configuration: budgetConfiguration,
        financialData: stage4Data('typical'),
      );
  bool fail = false;
  @override
  void refreshLocalReadModel() {
    if (fail) {
      throw StateError('fixture failure');
    }
    super.refreshLocalReadModel();
  }
}

Future<void> boot(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    QestoApp(
      preferenceStore: MemoryKeyValueStore(),
      repository: MockQestoRepository(
        delay: Duration.zero,
        financialData: stage4Data('typical'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
