import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mobile/analytics/mobile_financial_widgets.dart';
import 'package:qesto/mobile/analytics/mobile_upcoming_page.dart';
import 'package:qesto/mobile/capital/mobile_capital_common.dart';
import 'package:qesto/mobile/capital/mobile_capital_editor.dart';
import 'package:qesto/mobile/capital/mobile_capital_pages.dart';
import 'package:qesto/mobile/capital/mobile_investment_pages.dart';
import 'package:qesto/mobile/capital/mobile_debt_pages.dart';
import 'package:qesto/mobile/capital/mobile_goal_pages.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'fixtures/mobile_stage5_data.dart';

BudgetController controller([
  String kind = 'typical',
  Future<void> Function()? save,
]) => BudgetController(
  configuration: budgetConfiguration,
  financialData: stage5Data(kind),
  onChanged: save,
);
Future<void> show(
  WidgetTester t,
  Widget screen, {
  double width = 390,
  double scale = 1,
  double height = 844,
}) async {
  t.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: buildQestoTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: screen),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      280,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
      maxScrolls: 60,
    );
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> enter(WidgetTester t, String key, String value) async {
  final f = find.byKey(Key(key));
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      220,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
  }
  await t.ensureVisible(f);
  await t.enterText(f, value);
  await t.pumpAndSettle();
}

Future<void> launchEditor(
  WidgetTester t,
  Future<String?> Function(BuildContext) open,
) async {
  await show(
    t,
    Builder(
      builder: (ctx) =>
          TextButton(onPressed: () => open(ctx), child: const Text('Edit')),
    ),
  );
  await tap(t, find.text('Edit'));
}

String fingerprint(BudgetController c) =>
    const UserFinancialDataCodec().encode(c.mergeInto(stage5Data()));

void main() {
  test('money input never rounds unsupported fractional values', () {
    expect(capitalWhole('1 200,00'), 1200);
    expect(capitalWhole('-30'), -30);
    expect(() => capitalWhole('123,45'), throwsFormatException);
    expect(() => capitalWhole('0.01'), throwsFormatException);
  });
  test(
    'mobile uses the same five financial service results and projections',
    () {
      final c = controller();
      addTearDown(c.dispose);
      final before = fingerprint(c);
      final l = mobileLiquidity(c, CapitalPeriod.oneMonth);
      final desktopL = const AccountCapitalService().calculate(
        accounts: c.accounts,
        accountPreferences: c.accountPreferences,
        transactions: c.transactions,
        upcomingExpenses: c.upcomingExpenses,
        savingsGoals: c.savingsGoals,
        goalAllocations: c.goalAllocations,
        debts: c.debts,
        synoballState: c.synoballState,
        asOf: c.referenceDate,
        period: CapitalPeriod.oneMonth,
        baseCurrency: c.user.defaultCurrency,
      );
      expect(l.totalLiquidAssets, desktopL.totalLiquidAssets);
      expect(l.history.length, greaterThan(1));
      expect(
        l.history.map((p) => p.balance),
        desktopL.history.map((p) => p.balance),
      );
      final investment = const InvestmentAnalyticsService().calculate(
        accounts: c.investmentAccounts,
        balanceSnapshots: c.investmentBalanceSnapshots,
        contributions: c.investmentContributions,
        asOf: c.referenceDate,
        period: InvestmentPeriod.threeMonths,
        baseCurrency: c.user.defaultCurrency,
      );
      expect(
        mobileInvestments(c, InvestmentPeriod.threeMonths).totalBalance,
        investment.totalBalance,
      );
      final debt = const DebtAnalyticsService().calculate(
        debts: c.debts,
        balanceSnapshots: c.debtBalanceSnapshots,
        debtPayments: c.debtPayments,
        transactions: c.transactions,
        asOf: c.referenceDate,
        period: DebtAnalyticsPeriod.threeMonths,
        baseCurrency: c.user.defaultCurrency,
      );
      expect(
        mobileDebts(c, DebtAnalyticsPeriod.threeMonths).totalDebt,
        debt.totalDebt,
      );
      final goal = const GoalPlanningService().calculate(
        goals: c.savingsGoals,
        allocations: c.goalAllocations,
        contributions: c.goalContributions,
        asOf: c.referenceDate,
        baseCurrency: c.user.defaultCurrency,
      );
      expect(mobileGoals(c).currentAmount, goal.currentAmount);
      expect(mobileGoals(c).targetAmount, goal.targetAmount);
      final p = mobileGoal(c, c.savingsGoals.first);
      expect(p.progressPercent, goal.goals.first.progressPercent);
      expect(
        const DebtAnalyticsService().projectedPayoffDate(
          c.debts.first,
          asOf: c.referenceDate,
        ),
        isNotNull,
      );
      expect(fingerprint(c), before);
    },
  );
  test(
    'persistence retry resumes create once and compound command at failed step',
    () async {
      var writes = 0;
      final c = controller('empty', () async {
        if (++writes == 1) throw StateError('disk');
      });
      addTearDown(c.dispose);
      final q = CapitalWriteQueue(c);
      var command = 0;
      Future<void> create() async {
        command++;
        await c.addInvestmentAccount(name: 'One', currentBalance: 100);
      }

      await expectLater(q.run([create]), throwsStateError);
      expect(c.investmentAccounts, hasLength(1));
      expect(q.hasApplied, isTrue);
      await q.run([create]);
      expect(command, 1);
      expect(writes, 2);
      expect(c.investmentAccounts, hasLength(1));
      var failing = true;
      var persisted = 0;
      final d = controller('typical', () async {
        persisted++;
        if (failing && persisted == 2) throw StateError('disk');
      });
      addTearDown(d.dispose);
      final queue = CapitalWriteQueue(d);
      final a = d.investmentAccounts.first;
      var invocations = 0;
      final steps = <Future<void> Function()>[
        () => d.updateInvestmentAccount(a.copyWith(name: 'Updated')),
        () async {
          invocations++;
          await d.addInvestmentContribution(
            investmentAccountId: a.id,
            amount: 100,
            type: InvestmentContributionType.contribution,
            date: d.referenceDate,
          );
        },
        () => d.updateInvestmentBalance(
          investmentAccountId: a.id,
          balance: 999,
          date: d.referenceDate,
        ),
      ];
      await expectLater(queue.run(steps), throwsStateError);
      failing = false;
      await queue.run(steps);
      expect(invocations, 1);
      expect(d.investmentContributions, hasLength(1));
      expect(d.investmentAccounts.first.currentBalance, 999);
    },
  );
  testWidgets(
    'account minor units preserved; preferences save and detail Back',
    (t) async {
      final c = controller();
      addTearDown(c.dispose);
      final a = c.accounts.first;
      await show(
        t,
        MobileAccountsPage(controller: c, onOpenFilteredTransactions: (_) {}),
      );
      await tap(t, find.byKey(Key('capital-account-${a.id}')));
      expect(find.byType(MobileAccountDetail), findsOneWidget);
      expect(
        t.widget<CapitalExactMoney>(find.byType(CapitalExactMoney).first).minor,
        a.balanceMinor,
      );
      await tap(t, find.byKey(const Key('capital-account-settings')));
      await tap(t, find.byKey(const Key('reserve')));
      await tap(t, find.byKey(const Key('capital-save')));
      expect(c.accountPreferencesFor(a.id).includeInEmergencyFund, isTrue);
      expect(find.byType(MobileAccountDetail), findsOneWidget);
      await t.tap(find.byIcon(Icons.arrow_back));
      await t.pumpAndSettle();
      expect(find.byType(MobileAccountsPage), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('landing capital parity negative zero and privacy semantics', (
    t,
  ) async {
    for (final kind in ['typical', 'negative', 'empty']) {
      final c = controller(kind);
      addTearDown(c.dispose);
      await show(
        t,
        MobileCapitalLanding(controller: c, onOpenFilteredTransactions: (_) {}),
      );
      final value = find.byKey(const Key('mobile-capital-total'));
      if (kind == 'empty') {
        expect(value, findsNothing);
        continue;
      }
      final expected =
          (c.financialState.assets.minorUnits -
                  c.financialState.debts.minorUnits)
              .round();
      expect(t.widget<CapitalExactMoney>(value).minor, expected);
      if (kind == 'negative') expect(expected, lessThan(0));
      await tap(t, find.byKey(const Key('capital-privacy')));
      expect(t.widget<CapitalExactMoney>(value).hidden, isTrue);
    }
  });
  test('retry cannot resurrect data after a financial reset', () async {
    var fail = true;
    final c = controller('empty', () async {
      if (fail) throw StateError('disk');
    });
    addTearDown(c.dispose);
    final q = CapitalWriteQueue(c);
    await expectLater(
      q.run([
        () async {
          await c.addInvestmentAccount(name: 'Retry', currentBalance: 100);
        },
      ]),
      throwsStateError,
    );
    fail = false;
    await c.clearAllFinancialData();
    await expectLater(
      q.run([
        () async {
          await c.addInvestmentAccount(name: 'Retry', currentBalance: 100);
        },
      ]),
      throwsStateError,
    );
    expect(c.investmentAccounts, isEmpty);
  });
  testWidgets('all entity editors protect unsaved Back', (t) async {
    final c = controller();
    addTearDown(c.dispose);
    for (final e in <(String, Future<String?> Function(BuildContext))>[
      ('account-name-field', (ctx) => openMobileAccountCreate(ctx, c)),
      (
        'investment-name-field',
        (ctx) => openMobileInvestmentEditor(
          ctx,
          c,
          account: c.investmentAccounts.first,
        ),
      ),
      (
        'debt-name-field',
        (ctx) => openMobileDebtEditor(ctx, c, debt: c.debts.first),
      ),
      (
        'goal-title-field',
        (ctx) => openMobileGoalEditor(ctx, c, goal: c.savingsGoals.first),
      ),
    ]) {
      final before = fingerprint(c);
      await launchEditor(t, e.$2);
      await enter(t, e.$1, 'Dirty');
      await t.tap(find.byIcon(Icons.arrow_back));
      await t.pumpAndSettle();
      expect(find.text('Отменить изменения?'), findsOneWidget);
      await tap(t, find.byKey(const Key('capital-discard-confirm')));
      expect(find.byType(MobileCapitalEditor), findsNothing);
      expect(fingerprint(c), before);
    }
  });
  testWidgets(
    'fractional create stays in editor, validates off-screen fields too',
    (t) async {
      final c = controller('empty');
      addTearDown(c.dispose);
      await launchEditor(t, (ctx) => openMobileInvestmentEditor(ctx, c));
      await enter(t, 'investment-name-field', 'Fraction');
      await enter(t, 'investment-balance-field', '123,45');
      await tap(t, find.byKey(const Key('investment-save-button')));
      expect(c.investmentAccounts, isEmpty);
      expect(find.byType(MobileCapitalEditor), findsOneWidget);
      expect(find.textContaining('Дробная сумма'), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('save failure stays in editor and retry creates no duplicate', (
    t,
  ) async {
    var calls = 0;
    final c = controller('empty', () async {
      if (++calls == 1) throw StateError('disk');
    });
    addTearDown(c.dispose);
    await launchEditor(t, (ctx) => openMobileGoalEditor(ctx, c));
    await enter(t, 'goal-title-field', 'Retry goal');
    await enter(t, 'goal-target-field', '10000');
    await tap(t, find.byKey(const Key('goal-save-button')));
    expect(find.byKey(const Key('capital-save-error')), findsOneWidget);
    expect(c.savingsGoals, hasLength(1));
    await tap(t, find.byKey(const Key('goal-save-button')));
    expect(find.byType(MobileCapitalEditor), findsNothing);
    expect(c.savingsGoals, hasLength(1));
    expect(calls, 2);
  });
  testWidgets(
    'rapid double save applies command once while persistence is waiting',
    (t) async {
      final wait = Completer<void>();
      var calls = 0;
      final c = controller('empty', () {
        calls++;
        return wait.future;
      });
      addTearDown(c.dispose);
      await launchEditor(t, (ctx) => openMobileAccountCreate(ctx, c));
      await enter(t, 'account-name-field', 'Double');
      await enter(t, 'account-balance-field', '100');
      final save = find.byKey(const Key('account-add-confirm'));
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pump();
      await t.tap(save);
      await t.pump();
      expect(calls, 1);
      expect(c.accounts.where((a) => a.title == 'Double'), hasLength(1));
      wait.complete();
      await t.pumpAndSettle();
      expect(find.byType(MobileCapitalEditor), findsNothing);
    },
  );
  testWidgets(
    'investment edit valuation contribution archive preserve identity and history',
    (t) async {
      final c = controller();
      addTearDown(c.dispose);
      final a = c.investmentAccounts.first;
      await launchEditor(
        t,
        (ctx) => openMobileInvestmentEditor(ctx, c, account: a),
      );
      await enter(t, 'investment-name-field', 'Updated');
      await tap(t, find.byKey(const Key('investment-save-button')));
      expect(c.investmentAccounts.first.id, a.id);
      expect(c.investmentAccounts.first.name, 'Updated');
      await launchEditor(
        t,
        (ctx) => openMobileInvestmentValue(ctx, c, c.investmentAccounts.first),
      );
      await enter(t, 'valuation', '90000');
      await tap(t, find.byKey(const Key('capital-save')));
      expect(c.investmentAccounts.first.currentBalance, 90000);
      await launchEditor(
        t,
        (ctx) => openMobileInvestmentContribution(
          ctx,
          c,
          c.investmentAccounts.first,
        ),
      );
      await enter(t, 'amount', '500');
      await tap(t, find.byKey(const Key('capital-save')));
      expect(c.investmentContributions, hasLength(1));
      await show(t, MobileInvestmentDetail(controller: c, investmentId: a.id));
      await tap(t, find.text('Архивировать'));
      await tap(t, find.byKey(const Key('capital-save')));
      expect(
        c.investmentAccounts.first.status,
        InvestmentAccountStatus.archived,
      );
      expect(c.investmentBalanceSnapshots, isNotEmpty);
      expect(c.investmentContributions, hasLength(1));
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'debt edit keeps fractional rate; scenarios do not create payments',
    (t) async {
      final c = controller();
      addTearDown(c.dispose);
      final a = c.debts.first;
      await launchEditor(t, (ctx) => openMobileDebtEditor(ctx, c, debt: a));
      await enter(t, 'rate', '13,25');
      await tap(t, find.byKey(const Key('debt-save-button')));
      expect(c.debts.first.interestRate, 13.25);
      final before = fingerprint(c);
      await show(t, MobileDebtScenario(controller: c, debtId: a.id));
      await enter(t, 'capital-scenario-amount', '1000');
      await tap(t, find.byKey(const Key('capital-scenario-calculate')));
      expect(find.textContaining('Прогнозная дата'), findsOneWidget);
      expect(c.debtPayments, isEmpty);
      expect(fingerprint(c), before);
      await tap(t, find.text('Разовый досрочный платёж'));
      await tap(t, find.byKey(const Key('capital-scenario-calculate')));
      expect(find.text('Сократить срок'), findsOneWidget);
      expect(fingerprint(c), before);
      await show(t, MobileDebtDetail(controller: c, debtId: a.id));
      await tap(t, find.text('Архивировать'));
      await tap(t, find.byKey(const Key('capital-save')));
      expect(c.debts.first.status, DebtStatus.archived);
      expect(c.debtPayments, isEmpty);
    },
  );
  testWidgets(
    'goal contribution allocation edit remove archive use existing model',
    (t) async {
      final c = controller();
      addTearDown(c.dispose);
      final g = c.savingsGoals.first;
      await launchEditor(t, (ctx) => openMobileGoalContribution(ctx, c, g));
      await enter(t, 'goal-contribution-amount', '250');
      await tap(t, find.byKey(const Key('capital-save')));
      expect(c.goalContributions, hasLength(1));
      expect(c.savingsGoals.first.savedAmount, g.savedAmount + 250);
      await launchEditor(
        t,
        (ctx) => openMobileGoalAllocation(ctx, c, c.savingsGoals.first),
      );
      await enter(t, 'goal-allocation-amount-field', '500');
      await tap(t, find.byKey(const Key('goal-allocation-save')));
      expect(c.goalAllocations, hasLength(1));
      final id = c.goalAllocations.single.id;
      expect(mobileGoal(c, c.savingsGoals.first).currentAmount, 500);
      await launchEditor(
        t,
        (ctx) => openMobileGoalAllocation(
          ctx,
          c,
          c.savingsGoals.first,
          allocation: c.goalAllocations.single,
        ),
      );
      await enter(t, 'goal-allocation-amount-field', '800');
      await tap(t, find.byKey(const Key('goal-allocation-save')));
      expect(c.goalAllocations.single.id, id);
      expect(c.goalAllocations.single.allocatedAmount, 800);
      await launchEditor(
        t,
        (ctx) => openMobileGoalAllocation(
          ctx,
          c,
          c.savingsGoals.first,
          allocation: c.goalAllocations.single,
        ),
      );
      await tap(t, find.byKey(const Key('remove')));
      await tap(t, find.byKey(const Key('goal-allocation-save')));
      expect(c.goalAllocations, isEmpty);
      await launchEditor(
        t,
        (ctx) => openMobileGoalEditor(ctx, c, goal: c.savingsGoals.first),
      );
      await enter(t, 'goal-title-field', 'Updated goal');
      await tap(t, find.byKey(const Key('goal-save-button')));
      expect(c.savingsGoals.first.id, g.id);
      await show(t, MobileGoalDetail(controller: c, goalId: g.id));
      await tap(t, find.text('Архивировать'));
      await tap(t, find.byKey(const Key('capital-save')));
      expect(c.savingsGoals.first.status, GoalStatus.archived);
      expect(c.goalContributions, hasLength(1));
    },
  );
  testWidgets('reserve editor changes preferences and existing goal only', (
    t,
  ) async {
    final c = controller();
    addTearDown(c.dispose);
    final balances = c.accounts.map((a) => a.balanceMinor).toList();
    await launchEditor(t, (ctx) => openMobileReserveEditor(ctx, c));
    await enter(t, 'reserve-target', '40000');
    await tap(t, find.byKey(const Key('capital-save')));
    expect(
      c.savingsGoals.any(
        (g) => g.category == 'Финансовая подушка' && g.targetAmount == 40000,
      ),
      isTrue,
    );
    expect(c.accounts.map((a) => a.balanceMinor), balances);
  });
  testWidgets('history tap scrub accessible list and privacy', (t) async {
    final points = [
      for (var i = 1; i <= 3; i++)
        (date: DateTime(2026, 10, i), amount: i * 100, confirmed: i == 3),
    ];
    await show(t, MobileCapitalHistory(points: points, currency: 'RUB'));
    final graph = find.byKey(const Key('capital-history-touch'));
    await t.tapAt(t.getTopLeft(graph) + const Offset(2, 60));
    await t.pumpAndSettle();
    expect(find.textContaining('1 октября'), findsOneWidget);
    await t.dragFrom(
      t.getTopLeft(graph) + const Offset(20, 60),
      const Offset(330, 0),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('3 октября'), findsOneWidget);
    await tap(t, find.text('Даты и суммы списком'));
    expect(find.textContaining('Подтверждено'), findsOneWidget);
    await show(
      t,
      MobileCapitalHistory(points: points, currency: 'RUB', hidden: true),
    );
    expect(find.text('История скрыта'), findsOneWidget);
    expect(find.byKey(const Key('capital-history-touch')), findsNothing);
  });
  testWidgets('debt upcoming event opens exact entity without writes', (
    t,
  ) async {
    final c = controller();
    addTearDown(c.dispose);
    final before = fingerprint(c);
    await show(
      t,
      MobileUpcomingPage(
        controller: c,
        asOf: c.referenceDate,
        onOpenFilteredTransactions: (_) {},
      ),
    );
    await tap(t, find.text(c.debts.first.name));
    expect(find.byType(MobileDebtDetail), findsOneWidget);
    expect(
      t.widget<MobileDebtDetail>(find.byType(MobileDebtDetail)).debtId,
      c.debts.first.id,
    );
    expect(fingerprint(c), before);
  });
  testWidgets('history distinguishes two valuations on the same date', (
    t,
  ) async {
    final date = DateTime(2026, 10, 6);
    await show(
      t,
      MobileCapitalHistory(
        points: [
          (date: date, amount: 100, confirmed: true),
          (date: date, amount: 200, confirmed: true),
        ],
        currency: 'RUB',
      ),
    );
    final graph = find.byKey(const Key('capital-history-touch'));
    await t.tapAt(t.getTopLeft(graph) + const Offset(2, 60));
    await t.pumpAndSettle();
    expect(find.textContaining('100 ₽'), findsOneWidget);
    await t.tapAt(t.getTopRight(graph) + const Offset(-2, 60));
    await t.pumpAndSettle();
    expect(find.textContaining('200 ₽'), findsOneWidget);
  });
  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets(
      'capital ten screens width $width scale 1.3 plus form keyboard',
      (t) async {
        final c = controller('huge');
        addTearDown(c.dispose);
        final before = fingerprint(c);
        final pages = <Widget>[
          MobileCapitalLanding(
            controller: c,
            onOpenFilteredTransactions: (_) {},
          ),
          MobileLiquidityPage(controller: c),
          MobileAccountsPage(controller: c, onOpenFilteredTransactions: (_) {}),
          MobileAccountDetail(
            controller: c,
            accountId: c.accounts.first.id,
            onOpenFilteredTransactions: (_) {},
          ),
          MobileInvestmentsPage(controller: c),
          MobileInvestmentDetail(
            controller: c,
            investmentId: c.investmentAccounts.first.id,
          ),
          MobileDebtsPage(controller: c),
          MobileDebtDetail(controller: c, debtId: c.debts.first.id),
          MobileGoalsPage(controller: c),
          MobileGoalDetail(controller: c, goalId: c.savingsGoals.first.id),
        ];
        for (final page in pages) {
          await show(t, page, width: width, scale: 1.3);
          await scrollAll(t);
          expect(
            t.takeException(),
            isNull,
            reason: '${page.runtimeType} $width',
          );
        }
        expect(fingerprint(c), before);
      },
    );
  }
  for (final kind in ['empty', 'many', 'negative', 'overfunded']) {
    testWidgets(
      'capital edge $kind lazy lists and privacy do not mutate data',
      (t) async {
        final c = controller(kind);
        addTearDown(c.dispose);
        final before = fingerprint(c);
        for (final page in <Widget>[
          MobileCapitalLanding(
            controller: c,
            onOpenFilteredTransactions: (_) {},
          ),
          MobileAccountsPage(controller: c, onOpenFilteredTransactions: (_) {}),
          MobileInvestmentsPage(controller: c),
          MobileDebtsPage(controller: c),
          MobileGoalsPage(controller: c),
        ]) {
          await show(t, page, width: 320);
          if (kind == 'many') {
            expect(find.byType(MobileValueRow).evaluate().length, lessThan(50));
          }
          await scrollAll(t, steps: kind == 'many' ? 3 : 8);
          expect(t.takeException(), isNull);
        }
        expect(fingerprint(c), before);
      },
    );
  }
}

Future<void> scrollAll(WidgetTester t, {int steps = 10}) async {
  for (var i = 0; i < steps; i++) {
    final f = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .last;
    await t.drag(f, const Offset(0, -300));
    await t.pumpAndSettle();
  }
}
