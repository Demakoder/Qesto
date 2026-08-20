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
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      QestoApp(repository: const MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    expect(find.text('DEMO · отдельно от данных'), findsNothing);
    expect(find.text('Starbucks'), findsNothing);
    expect(find.text('Добрый день'), findsOneWidget);
    expect(find.byKey(const Key('overview-expense-trend')), findsOneWidget);
    expect(find.byKey(const Key('overview-expense-map')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop P0 routes remain overflow-free at target width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      QestoApp(repository: const MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    for (final entry in <String, IconData>{
      'transactions': Icons.layers_outlined,
      'budget': Icons.pie_chart_outline_rounded,
      'cash-flow': Icons.swap_vert_circle_outlined,
      'accounts': Icons.account_balance_wallet_outlined,
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
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

  testWidgets('desktop permanently uses typography variant B', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      QestoApp(repository: const MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('typography-lab')), findsNothing);
    final context = tester.element(find.text('Qesto').first);
    expect(
      Theme.of(context).textTheme.headlineSmall?.fontFamily,
      'IBM Plex Sans',
    );
    expect(Theme.of(context).textTheme.bodyMedium?.fontFamily, 'Manrope');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme can be selected and persists', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    expect(find.byKey(const Key('qesto-dark-surface')), findsOneWidget);
    expect(find.byKey(const Key('desktop-add-data')), findsOneWidget);
    expect(find.text('Добавить данные'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop does not report overrun when budget is unassigned', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

    await tester.tap(find.byIcon(Icons.pie_chart_outline_rounded).first);
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
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
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

  testWidgets('desktop is organised into Budget, Benefits and Savings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
    expect(find.byKey(const Key('desktop-section-savings')), findsOneWidget);

    await tester.tap(find.byKey(const Key('desktop-section-benefits')));
    await tester.pumpAndSettle();
    expect(find.text('Выгода · Предложения'), findsOneWidget);
    expect(
      find.byKey(const Key('desktop-section-items-benefits')),
      findsOneWidget,
    );
    expect(find.text('Транзакции'), findsNothing);

    await tester.tap(find.byKey(const Key('desktop-section-savings')));
    await tester.pumpAndSettle();
    expect(find.text('Накопления · Цели'), findsOneWidget);
    expect(
      find.byKey(const Key('desktop-section-items-savings')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.show_chart_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cash flow has an interactive money river and privacy mode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: sampleUserFinancialData,
        ),
      ),
    );
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
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: sampleUserFinancialData,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.pie_chart_outline_rounded).first);
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

  testWidgets('desktop statistics exposes Android analytics sections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: sampleUserFinancialData,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bar_chart_rounded).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('desktop-statistics-page')), findsOneWidget);
    expect(find.text('Финансовая аналитика'), findsOneWidget);
    expect(find.text('Финансовая динамика'), findsOneWidget);
    expect(
      find.byKey(const Key('desktop-statistics-tab-overview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('desktop-statistics-tab-recurring')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('desktop-statistics-tab-expenses')));
    await tester.pumpAndSettle();
    expect(find.text('Динамика расходов'), findsOneWidget);

    await tester.tap(find.byKey(const Key('desktop-statistics-tab-rhythm')));
    await tester.pumpAndSettle();
    expect(find.text('Календарь расходов'), findsOneWidget);
    await tester.drag(
      find.byKey(const PageStorageKey('statistics-rhythm')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    expect(find.text('Дни недели'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('desktop-statistics-tab-categories')),
    );
    await tester.tap(
      find.byKey(const Key('desktop-statistics-tab-categories')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Структура расходов'), findsOneWidget);

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

  testWidgets('desktop statistics has a genuine empty state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      QestoApp(repository: const MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bar_chart_rounded).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('desktop-statistics-empty')), findsOneWidget);
    expect(find.text('Статистика появится после операций'), findsOneWidget);
    await tester.tap(find.byKey(const Key('desktop-statistics-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Всё время').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop notifications exposes guarded full data deletion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      QestoApp(repository: const MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('desktop-notifications')));
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
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

  testWidgets('all desktop statistics sections fit at 1024', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      QestoApp(
        repository: MockQestoRepository(
          delay: Duration.zero,
          financialData: sampleUserFinancialData,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.bar_chart_rounded).first);
    await tester.pumpAndSettle();

    for (final section in [
      'overview',
      'expenses',
      'rhythm',
      'merchants',
      'categories',
      'cashFlow',
      'budget',
      'recurring',
    ]) {
      final tab = find.byKey(Key('desktop-statistics-tab-$section'));
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'overflow in desktop statistics section $section',
      );
    }
  });
}
