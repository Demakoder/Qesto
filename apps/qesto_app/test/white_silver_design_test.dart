import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/design_system/qesto_silver.dart';
import 'package:qesto/design_system/qesto_window.dart';
import 'package:qesto/design_system/qesto_expandable_tool.dart';
import 'package:qesto/desktop/desktop_destination.dart';
import 'package:qesto/desktop/pages/desktop_dashboard_page.dart';
import 'package:qesto/desktop/pages/desktop_debts_page.dart';
import 'package:qesto/desktop/pages/desktop_investments_page.dart';
import 'package:qesto/desktop/pages/desktop_accounts_page.dart';
import 'package:qesto/desktop/pages/desktop_budget_page.dart';
import 'package:qesto/desktop/pages/desktop_support_pages.dart';
import 'package:qesto/desktop/pages/desktop_transactions_page.dart';
import 'package:qesto/desktop/widgets/desktop_chrome.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'fixtures/sample_user_financial_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final handler = FlutterError.onError!;
    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
      handler(details);
    };
  });
  setUpAll(() async {
    for (final entry in {
      'Onest': 'assets/fonts/white_silver/Onest-Variable.ttf',
      'Prata': 'assets/fonts/white_silver/Prata-Regular.ttf',
      'Noto Serif Display':
          'assets/fonts/white_silver/NotoSerifDisplay-Italic.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });

  Future<void> size(WidgetTester tester, Size value) async {
    final handler = FlutterError.onError!;
    FlutterError.onError = (details) {
      // Include the owning widget / constraints for native layout regressions.
      debugPrint(details.toString());
      handler(details);
    };
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = value;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test('typography and financial colour roles are explicit', () {
    final theme = buildQestoTheme();
    expect(theme.textTheme.bodyMedium!.fontFamily, 'Onest');
    expect(theme.textTheme.headlineSmall!.fontFamily, 'Prata');
    expect(theme.textTheme.displayLarge!.fontFamily, 'Noto Serif Display');
    expect(theme.textTheme.displayLarge!.fontStyle, FontStyle.italic);
    expect(QestoColors.positive, QestoPalette.income);
    expect(QestoColors.negative, QestoPalette.expense);
    expect(
      buildQestoTheme(brightness: Brightness.dark).brightness,
      Brightness.dark,
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'Window, Silver buttons and long Cyrillic money values $brightness',
      (tester) async {
        await size(tester, const Size(900, 740));
        var presses = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildQestoTheme(brightness: brightness),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    QestoWindow(
                      title: 'Капитал',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ваша финансовая позиция',
                            style: QestoTypography.sectionTitle,
                          ),
                          const QestoHeroMoney('84 320 ₽'),
                          const Text(
                            'Сентябрь · данные за выбранный период',
                            style: QestoTypography.caption,
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              QestoPrimaryButton(
                                label: 'Добавить операцию',
                                icon: Icons.add,
                                onPressed: () => presses++,
                              ),
                              QestoSecondaryButton(
                                label: 'Изменить период',
                                onPressed: () {},
                              ),
                              const QestoPrimaryButton(
                                label: 'Недоступно',
                                onPressed: null,
                              ),
                              QestoDangerButton(
                                label: 'Удалить',
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const QestoWindow(
                      title: 'Проверка чисел',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 220,
                            child: QestoHeroMoney(
                              '−12 345 678 901 234 ₽',
                              color: QestoPalette.expense,
                            ),
                          ),
                          QestoMoneyCell(
                            '+8 450,25 ₽',
                            color: QestoPalette.income,
                          ),
                          Text(
                            'Ёж, счёт, ₽, юань — русский интерфейс',
                            style: QestoTypography.ui,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const TextField(
                      decoration: InputDecoration(
                        labelText: 'Название цели',
                        hintText: 'Подушка безопасности',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/white_silver/components_${brightness.name}.png',
          ),
        );
        await tester.tap(find.text('Добавить операцию'));
        await tester.pumpAndSettle();
        expect(presses, 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus, isNotNull);
      },
    );
  }
  for (final config in [
    for (final brightness in Brightness.values)
      for (final width in [1440.0, 1280.0, 1024.0, 390.0]) (width, brightness),
  ]) {
    final (width, brightness) = config;
    testWidgets('Overview native render at $width $brightness', (tester) async {
      await size(tester, Size(width, width > 900 ? 1200 : 1000));
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: sampleUserFinancialData,
      );
      addTearDown(controller.dispose);
      final page = DesktopDashboardPage(
        controller: controller,
        period: controller.periods.firstWhere(
          (p) => p.year == 2026 && p.month == 7,
        ),
        onOpenTransactions: () {},
        onOpenBudget: () {},
        onOpenRecurring: () {},
        onOpenTransaction: (_) {},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildQestoTheme(brightness: brightness),
          home: Scaffold(
            body: width > 900
                ? Row(
                    children: [
                      DesktopSidebar(
                        selected: DesktopDestination.dashboard,
                        collapsed: false,
                        user: controller.user,
                        onSelected: (_) {},
                        onToggle: () {},
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            DesktopTopBar(
                              title: 'Обзор',
                              period: 'Июль 2026',
                              onPeriodPressed: () {},
                              onSearch: () {},
                              onAdd: () {},
                              onNotifications: () {},
                            ),
                            Expanded(child: page),
                          ],
                        ),
                      ),
                    ],
                  )
                : page,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/white_silver/overview_${width.toInt()}_${brightness.name}.png',
        ),
      );
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
      expect(tester.takeException(), isNull);
      final expandChart = find.byTooltip('Развернуть Динамика расходов');
      await tester.ensureVisible(expandChart);
      await tester.pumpAndSettle();
      await tester.tap(expandChart);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Свернуть Динамика расходов'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(expandChart, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'Transaction log uses real fixture rows and keeps search $brightness',
      (tester) async {
        await size(tester, const Size(1200, 800));
        final controller = BudgetController(
          configuration: budgetConfiguration,
          financialData: sampleUserFinancialData,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildQestoTheme(brightness: brightness),
            home: Scaffold(
              body: DesktopTransactionsPage(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/white_silver/transactions_${brightness.name}.png',
          ),
        );
        await tester.enterText(
          find.byType(TextField).first,
          'несуществующий магазин',
        );
        await tester.pumpAndSettle();
        expect(find.text('Операции не найдены'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'expanded tool preserves the same input state and closes with Escape',
    (tester) async {
      await size(tester, const Size(1000, 800));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildQestoTheme(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: QestoExpandableTool(
                title: 'Проверка состояния',
                builder: (context, expanded) => const SizedBox(
                  height: 200,
                  child: TextField(key: Key('retained-input')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('retained-input')),
        'Сохранённый фильтр',
      );
      final element = tester.element(find.byKey(const Key('retained-input')));
      await tester.tap(find.byTooltip('Развернуть Проверка состояния'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.element(find.byKey(const Key('retained-input'))),
        same(element),
      );
      expect(find.text('Сохранённый фильтр'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Развернуть Проверка состояния'), findsOneWidget);
      expect(
        tester.element(find.byKey(const Key('retained-input'))),
        same(element),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final checkpoint in [
    for (final brightness in Brightness.values)
      for (final section in [
        'budget',
        'liquidity',
        'debts',
        'investments',
        'goals',
        'insights',
        'benefits',
      ])
        (section, brightness),
  ]) {
    final (section, brightness) = checkpoint;
    testWidgets('White Silver $section $brightness visual checkpoint', (
      tester,
    ) async {
      await size(tester, const Size(1200, 900));
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: sampleUserFinancialData,
      );
      addTearDown(controller.dispose);
      final Widget page = switch (section) {
        'budget' => DesktopBudgetPage(controller: controller),
        'liquidity' => DesktopAccountsPage(controller: controller),
        'debts' => DesktopDebtsPage(controller: controller),
        'investments' => DesktopInvestmentsPage(controller: controller),
        'goals' => DesktopGoalsPage(controller: controller),
        'insights' => DesktopInsightsPage(controller: controller),
        _ => const DesktopBenefitsPage(
          coupons: [],
          promotions: [],
          trackedProducts: [],
        ),
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: buildQestoTheme(brightness: brightness),
          home: Scaffold(body: page),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/white_silver/${section}_${brightness.name}.png',
        ),
      );
    });
  }

  testWidgets('Hero money stays readable in a narrow enlarged-text surface', (
    tester,
  ) async {
    await size(tester, const Size(320, 640));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.8),
          ),
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: QestoWindow(
                title: 'Долг и накопления',
                child: QestoHeroMoney('−12 345 678 901 ₽'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('−12 345 678 901 ₽'), findsOneWidget);
  });
}
