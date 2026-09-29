import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';

import 'fixtures/sample_user_financial_data.dart';

void main() {
  testWidgets('production desktop starts without seeded financial data', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(repository: const MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    expect(find.text('DEMO · отдельно от данных'), findsNothing);
    expect(find.text('Starbucks'), findsNothing);
    expect(find.text('Добрый день'), findsOneWidget);
    expect(find.byKey(const Key('overview-expense-trend')), findsOneWidget);
    expect(find.byKey(const Key('overview-expense-map')), findsOneWidget);
    expect(find.byKey(const Key('overview-refresh')), findsOneWidget);
    expect(
      find.byKey(const Key('overview-flow-category-mode')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('overview-refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overview-expense-map')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop P0 routes remain overflow-free at target width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(repository: const MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('desktop-section-budget')));
    await tester.pumpAndSettle();

    for (final entry in <String, IconData>{
      'transactions': Icons.layers_outlined,
      'budget': Icons.pie_chart_outline_rounded,
      'cash-flow': Icons.swap_vert_circle_outlined,
      'recurring': Icons.event_repeat_outlined,
    }.entries) {
      await tester.tap(find.byIcon(entry.value).first);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow on ${entry.key}',
      );
    }
  });

  testWidgets('desktop shell remains compact and overflow-free at 1024', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(repository: const MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('desktop-overview-scroll')), findsOneWidget);
    expect(
      find.byIcon(Icons.keyboard_double_arrow_right_rounded),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('capital accounts expose liquidity, emergency goal and details', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: sampleUserFinancialData,
        ),
        preferenceStore: MemoryKeyValueStore(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('desktop-section-capital')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-destination-liquidity')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('total-liquid-assets')), findsOneWidget);
    expect(find.text('Деньги на счетах'), findsOneWidget);
    expect(find.text('Инвестиционный портфель'), findsNothing);

    await tester.tap(find.byKey(const Key('emergency-goal-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('emergency-goal-dialog')), findsOneWidget);
    expect(find.byKey(const Key('emergency-target-field')), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Основная карта'));
    await tester.tap(find.text('Основная карта'));
    await tester.pumpAndSettle();
    expect(find.text('Детали счёта'), findsOneWidget);
    expect(find.byKey(const Key('account-role-card-main')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop uses approved White Silver typography', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      QestoApp(repository: const MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('typography-lab')), findsNothing);
    final context = tester.element(find.text('Qesto').first);
    expect(Theme.of(context).textTheme.headlineSmall?.fontFamily, 'Prata');
    expect(Theme.of(context).textTheme.bodyMedium?.fontFamily, 'Onest');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme can be selected and persists', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryKeyValueStore();

    await tester.pumpWidget(
      QestoApp(
        repository: const MockQestoRepository(delay: Duration.zero),
        preferenceStore: store,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('desktop-profile-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-theme-selector')), findsOneWidget);
    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();

    expect(await store.readString('qesto.themeMode'), 'dark');
    expect(find.byType(ColorFiltered), findsNothing);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    expect(find.byKey(const Key('desktop-add-data')), findsOneWidget);
    expect(find.text('Добавить данные'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop does not report overrun when budget is unassigned', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final zeroBudgetData = sampleUserFinancialData.copyWith(
      budgetPeriods: [
        for (final period in sampleUserFinancialData.budgetPeriods)
          BudgetPeriod(
            id: period.id,
            userId: period.userId,
            startDate: period.startDate,
            endDate: period.endDate,
            type: period.type,
            totalPlan: 0,
            currency: period.currency,
          ),
      ],
      categoryBudgets: const [],
    );

    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: zeroBudgetData,
        ),
        preferenceStore: MemoryKeyValueStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Не рассчитаны'), findsOneWidget);
    expect(find.text('Назначьте бюджет'), findsOneWidget);
    expect(find.textContaining('План превышен'), findsNothing);

    await tester.tap(find.byKey(const Key('desktop-section-budget')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-destination-budget')));
    await tester.pumpAndSettle();
    expect(find.text('Бюджет не назначен'), findsWidgets);
    expect(find.textContaining('Лимит превышен'), findsNothing);

    await tester.tap(find.byKey(const Key('edit-total-budget')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('total-budget-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('total-budget-input')),
      '50000',
    );
    await tester.tap(find.byKey(const Key('save-total-budget')));
    await tester.pumpAndSettle();
    expect(find.text('Бюджет не назначен'), findsNothing);
    expect(find.text('Изменить'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'overview metrics, period and transaction sorting are interactive',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        QestoApp(
          repository: MockQestoRepository(
            delay: Duration.zero,
            financialData: sampleUserFinancialData,
          ),
          preferenceStore: MemoryKeyValueStore(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Кэшфлоу'), findsOneWidget);
      expect(find.byKey(const Key('desktop-overview-period')), findsOneWidget);

      await tester.tap(find.byTooltip('Выбрать доходы или расходы'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Доходы').last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('overview-primary-metric')),
          matching: find.text('Доходы'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('desktop-overview-period')));
      await tester.pumpAndSettle();
      expect(find.text('Период обзора'), findsOneWidget);
      await tester.tap(find.text('Июнь 2026'));
      await tester.pumpAndSettle();
      expect(find.text('Июнь 2026'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('overview-recent-transactions')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сумма'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('overview day drilldown opens scoped journal and keeps month', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: sampleUserFinancialData,
        ),
        preferenceStore: MemoryKeyValueStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-overview-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Июль 2026').last);
    await tester.pumpAndSettle();

    final chart = find.byKey(const Key('overview-trend-hit-area'));
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();
    final rect = tester.getRect(chart);
    await tester.tapAt(Offset(rect.right - 15, rect.center.dy));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overview-drilldown-panel')), findsOneWidget);
    expect(find.text('19 июля 2026'), findsWidgets);
    expect(
      find.byKey(const Key('overview-drilldown-transaction-jul-c7')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('overview-drilldown-open-all')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('transactions-overview-filter')),
      findsOneWidget,
    );
    expect(find.text('Из обзора: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overview lower cards open merchant and category details', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: sampleUserFinancialData,
        ),
        preferenceStore: MemoryKeyValueStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-overview-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Июль 2026').last);
    await tester.pumpAndSettle();

    final expense = find.byKey(const Key('overview-top-expense-jul-g3'));
    await tester.ensureVisible(expense);
    await tester.tap(expense);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overview-drilldown-panel')), findsOneWidget);
    expect(find.text('Продавец за выбранный период'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('overview-merchant-timeline')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('overview-merchant-timeline')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('overview-drilldown-transaction-jul-g3')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overview-drilldown-transaction-jul-g3')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Закрыть'));
    await tester.pumpAndSettle();

    final category = find.byKey(
      const Key('overview-category-budget-groceries'),
    );
    await tester.ensureVisible(category);
    await tester.tap(category);
    await tester.pumpAndSettle();
    expect(find.text('Категория за выбранный период'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('overview-merchant-donut')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overview-merchant-donut')), findsOneWidget);
    expect(find.byKey(const Key('overview-merchant-bars')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('overview-drilldown-transaction-jul-g3')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('overview-drilldown-transaction-jul-g3')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop is organised into Budget, Benefits and Capital', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: sampleUserFinancialData,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('desktop-section-budget')), findsOneWidget);
    expect(find.byKey(const Key('desktop-section-benefits')), findsOneWidget);
    expect(find.byKey(const Key('desktop-section-capital')), findsOneWidget);
    expect(
      find.byKey(const Key('desktop-destination-dashboard')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('desktop-destination-insights')),
      findsOneWidget,
    );
    expect(find.text('ИИ'), findsOneWidget);
    expect(find.byKey(const Key('desktop-destination-reports')), findsNothing);

    await tester.tap(find.byKey(const Key('desktop-section-budget')));
    await tester.pumpAndSettle();
    expect(find.text('Бюджет · Расходы'), findsOneWidget);
    expect(find.byKey(const Key('desktop-destination-rhythm')), findsOneWidget);
    expect(
      find.byKey(const Key('desktop-destination-merchants')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('desktop-destination-categories')),
      findsNothing,
    );
    expect(find.byKey(const Key('desktop-destination-accounts')), findsNothing);

    await tester.tap(find.byKey(const Key('desktop-destination-dashboard')));
    await tester.pumpAndSettle();
    expect(find.text('Обзор'), findsWidgets);

    await tester.tap(find.byKey(const Key('desktop-section-benefits')));
    await tester.pumpAndSettle();
    expect(find.text('Выгода · Предложения'), findsOneWidget);
    expect(
      find.byKey(const Key('desktop-section-items-benefits')),
      findsOneWidget,
    );
    expect(find.text('Операции'), findsNothing);

    await tester.tap(find.byKey(const Key('desktop-section-capital')));
    await tester.pumpAndSettle();
    expect(find.text('Капитал · Ликвидность'), findsOneWidget);
    expect(
      find.byKey(const Key('desktop-section-items-capital')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('desktop-destination-investments')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('desktop-destination-debts')), findsOneWidget);
    expect(find.byKey(const Key('desktop-destination-goals')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cash flow has an interactive money river and privacy mode', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: sampleUserFinancialData,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-section-budget')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.swap_vert_circle_outlined).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('desktop-cash-flow-page')), findsOneWidget);
    expect(find.byKey(const Key('money-flow-river-card')), findsOneWidget);
    expect(find.text('Река денег'), findsOneWidget);
    expect(find.text('Тестовый режим'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cash-flow-privacy')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Показать суммы'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category visual identity can be edited from the budget', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: sampleUserFinancialData,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-section-budget')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-destination-budget')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-customize-categories')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('category-appearance-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('category-style-groceries')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('category-appearance-name')),
      'Еда домой',
    );
    await tester.tap(find.byKey(const Key('category-icon-camera')));
    await tester.tap(find.byKey(const Key('category-color-4281255094')));
    await tester.tap(find.byKey(const Key('save-category-appearance')));
    await tester.pumpAndSettle();

    expect(find.text('Еда домой'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('budget exposes unique analytics without a statistics hub', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: sampleUserFinancialData,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('desktop-section-budget')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('desktop-budget-analysis-page')),
      findsOneWidget,
    );
    expect(find.text('Расходы · аналитика'), findsOneWidget);
    expect(find.text('Динамика расходов'), findsOneWidget);
    expect(find.text('Статистика'), findsNothing);

    await tester.drag(
      find.byKey(const PageStorageKey('statistics-expenses')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    expect(find.text('Структура расходов'), findsOneWidget);
    expect(find.text('Категории расходов'), findsOneWidget);

    await tester.drag(
      find.byKey(const PageStorageKey('statistics-expenses')),
      const Offset(0, -620),
    );
    await tester.pumpAndSettle();
    expect(find.text('Магазины и сервисы'), findsOneWidget);
    expect(find.text('Покупательские привычки'), findsOneWidget);

    await tester.drag(
      find.byKey(const PageStorageKey('statistics-expenses')),
      const Offset(0, 900),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.calendar_view_week_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Ритм жизни · аналитика'), findsOneWidget);
    expect(find.text('Календарь расходов'), findsOneWidget);
    await tester.drag(
      find.byKey(const PageStorageKey('statistics-rhythm')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    expect(find.text('Дни недели'), findsOneWidget);

    await tester.tap(find.byKey(const Key('desktop-statistics-filters')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('desktop-statistics-filter-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('desktop-statistics-apply-filters')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('budget analytics has a genuine empty state', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(repository: const MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('desktop-section-budget')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('desktop-budget-analysis-empty')),
      findsOneWidget,
    );
    expect(find.text('Аналитика появится после операций'), findsOneWidget);
    await tester.tap(find.byKey(const Key('desktop-statistics-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Всё время').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop notifications exposes guarded full data deletion', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(repository: const MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('desktop-notifications')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('qesto-notification-center')), findsOneWidget);
    await tester.tap(find.text('Уведомления и SMS'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delete-all-data')), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete-all-data')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirm-delete-all-data')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop add dialog exposes a dedicated Excel action', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(repository: const MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('desktop-add-data')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-data-excel')), findsOneWidget);
    expect(find.text('Excel-таблицу'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-data-excel')));
    await tester.pumpAndSettle();
    expect(find.text('Добавить Excel-таблицу'), findsOneWidget);
    expect(find.byKey(const Key('pick-excel-file')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all direct budget analytics sections fit at 1024', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: sampleUserFinancialData,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-section-budget')));
    await tester.pumpAndSettle();

    for (final icon in [
      Icons.trending_down_rounded,
      Icons.calendar_view_week_rounded,
    ]) {
      final destination = find.byIcon(icon).first;
      await tester.tap(destination);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow in direct budget analytics section $icon',
      );
    }
  });

  testWidgets('expenses can be displayed in the fixed CBR currencies', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: sampleUserFinancialData,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-section-budget')));
    await tester.pumpAndSettle();

    expect(find.textContaining('22.08.2026'), findsOneWidget);
    await tester.tap(find.byKey(const Key('expenses-currency-USD')));
    await tester.pumpAndSettle();
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const Key('expenses-currency-USD')),
    );
    expect(chip.selected, isTrue);
    expect(find.textContaining(r'$'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop goals can be created with category and deadline', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: sampleUserFinancialData,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-section-capital')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-destination-goals')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal-add-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goal-editor-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('goal-title-field')),
      'Поездка в Китай',
    );
    await tester.enterText(
      find.byKey(const Key('goal-target-field')),
      '200000',
    );
    await tester.tap(find.byKey(const Key('goal-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Поездка в Китай'), findsOneWidget);
    expect(find.text('Финансовая подушка'), findsWidgets);
    await tester.tap(find.text('Поездка в Китай'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goal-details-page')), findsOneWidget);
    expect(find.text('Что если откладывать больше?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop investment account can be created from empty state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(
        repository: const MockQestoRepository(delay: Duration.zero),
        preferenceStore: MemoryKeyValueStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-section-capital')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-destination-investments')));
    await tester.pumpAndSettle();

    expect(find.text('Инвестиционных счетов пока нет'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'empty investment state');
    await tester.tap(find.byKey(const Key('investment-empty-add-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'investment editor');
    await tester.enterText(
      find.byKey(const Key('investment-name-field')),
      'Т-Инвестиции',
    );
    await tester.enterText(
      find.byKey(const Key('investment-balance-field')),
      '430000',
    );
    expect(tester.takeException(), isNull, reason: 'investment editor values');
    await tester.tap(find.byKey(const Key('investment-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Т-Инвестиции'), findsOneWidget);
    expect(find.text('430 000 ₽'), findsWidgets);
    expect(find.text('Пополнения по месяцам'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop debt can be created from the honest empty state', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      QestoApp(
        repository: const MockQestoRepository(delay: Duration.zero),
        preferenceStore: MemoryKeyValueStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-section-capital')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktop-destination-debts')));
    await tester.pumpAndSettle();

    expect(find.text('Долгов нет'), findsOneWidget);
    await tester.tap(find.byKey(const Key('debt-add-empty')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('debt-name-field')),
      'Учебный кредит',
    );
    await tester.enterText(
      find.byKey(const Key('debt-balance-field')),
      '125000',
    );
    await tester.tap(find.byKey(const Key('debt-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Учебный кредит'), findsOneWidget);
    expect(find.text('125 000 ₽'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
