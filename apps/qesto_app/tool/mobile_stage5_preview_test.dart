// Captures real Flutter mobile routes; exclusively synthetic fixtures.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/desktop/desktop_app_shell.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mobile/capital/mobile_capital_common.dart';
import 'package:qesto/mobile/capital/mobile_capital_pages.dart';
import 'package:qesto/mobile/capital/mobile_investment_pages.dart';
import 'package:qesto/mobile/capital/mobile_debt_pages.dart';
import 'package:qesto/mobile/capital/mobile_goal_pages.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';
import '../test/fixtures/mobile_stage5_data.dart';

const boundaryKey = Key('stage5-preview');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final e in {
      'Onest': 'assets/fonts/white_silver/Onest-Variable.ttf',
      'Prata': 'assets/fonts/white_silver/Prata-Regular.ttf',
      'Noto Serif Display':
          'assets/fonts/white_silver/NotoSerifDisplay-Italic.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(e.key)..addFont(rootBundle.load(e.value))).load();
    }
  });
  testWidgets(
    'Stage 5 real mobile routes render matrix and forms',
    (t) async {
      t.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final messenger = t.binding.defaultBinaryMessenger;
      const channel = MethodChannel('ru.qesto.qesto/notifications');
      const events = MethodChannel('ru.qesto.qesto/notification_events');
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'hasAccess' => true,
          'readNotifications' => <Object?>[],
          _ => null,
        },
      );
      messenger.setMockMethodCallHandler(events, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      addTearDown(() => messenger.setMockMethodCallHandler(events, null));
      late BudgetController c;
      Future<void> app([String kind = 'typical']) async {
        await t.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: QestoApp(
              key: UniqueKey(),
              preferenceStore: MemoryKeyValueStore(),
              repository: MockQestoRepository(
                delay: Duration.zero,
                financialData: stage5Data(kind),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        c = t.widget<DesktopAppShell>(find.byType(DesktopAppShell)).controller;
        await t.tap(find.byKey(const Key('mobile-root-capital')));
        await t.pumpAndSettle();
      }

      BuildContext origin() =>
          t.element(find.byType(MobileCapitalLanding, skipOffstage: false));
      Future<void> route(Widget page, String name) async {
        capitalPush(origin(), '/capital/preview/$name', page);
        await t.pumpAndSettle();
        await capture(t, name);
        Navigator.of(origin()).pop();
        await t.pumpAndSettle();
      }

      Map<String, Widget> screens() => {
        '02-liquidity': MobileLiquidityPage(controller: c),
        '03-accounts': MobileAccountsPage(
          controller: c,
          onOpenFilteredTransactions: (_) {},
        ),
        '04-account-detail': MobileAccountDetail(
          controller: c,
          accountId: c.accounts.first.id,
          onOpenFilteredTransactions: (_) {},
        ),
        '05-investments': MobileInvestmentsPage(controller: c),
        '06-investment-detail': MobileInvestmentDetail(
          controller: c,
          investmentId: c.investmentAccounts.first.id,
        ),
        '07-debts': MobileDebtsPage(controller: c),
        '08-debt-detail': MobileDebtDetail(
          controller: c,
          debtId: c.debts.first.id,
        ),
        '09-goals': MobileGoalsPage(controller: c),
        '10-goal-detail': MobileGoalDetail(
          controller: c,
          goalId: c.savingsGoals.first.id,
        ),
      };
      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        t.view.physicalSize = Size(width, 844);
        await app();
        await capture(t, '01-capital-${width.toInt()}');
        for (final e in screens().entries) {
          await route(e.value, '${e.key}-${width.toInt()}');
        }
      }
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      t.view.physicalSize = const Size(320, 844);
      await app('huge');
      await capture(t, 'capital-huge-scale13');
      for (final e in screens().entries.where(
        (e) => e.key.contains('detail'),
      )) {
        await route(e.value, '${e.key}-scale13');
      }
      t.platformDispatcher.textScaleFactorTestValue = 1;
      t.view.physicalSize = const Size(844, 390);
      await app();
      await capture(t, 'capital-landscape');
      await route(MobileLiquidityPage(controller: c), 'liquidity-landscape');
      t.view.physicalSize = const Size(390, 844);
      for (final kind in ['empty', 'negative', 'overfunded', 'many']) {
        await app(kind);
        await capture(t, 'capital-$kind');
        await route(MobileGoalsPage(controller: c), 'goals-$kind');
      }
      await app();
      capitalPush(
        origin(),
        '/capital/reserve',
        MobileReservePage(controller: c),
      );
      await t.pumpAndSettle();
      await capture(t, '11-reserve');
      Navigator.of(origin()).pop();
      await t.pumpAndSettle();
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      t.view.physicalSize = const Size(320, 844);
      for (final e in <(String, Future<String?> Function(BuildContext))>[
        ('12-account-form', (ctx) => openMobileAccountCreate(ctx, c)),
        (
          '13-investment-form',
          (ctx) => openMobileInvestmentEditor(
            ctx,
            c,
            account: c.investmentAccounts.first,
          ),
        ),
        (
          '14-debt-form',
          (ctx) => openMobileDebtEditor(ctx, c, debt: c.debts.first),
        ),
        (
          '15-goal-form',
          (ctx) => openMobileGoalEditor(ctx, c, goal: c.savingsGoals.first),
        ),
      ]) {
        e.$2(origin());
        await t.pumpAndSettle();
        await capture(t, e.$1);
        t.view.viewInsets = const FakeViewPadding(bottom: 280);
        await t.pumpAndSettle();
        final save = find.byWidgetPredicate((w) => w is FilledButton);
        await t.scrollUntilVisible(
          save,
          250,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .last,
        );
        await t.pumpAndSettle();
        await capture(t, '${e.$1}-keyboard-save');
        t.view.resetViewInsets();
        await t.pumpAndSettle();
        Navigator.of(origin()).pop();
        await t.pumpAndSettle();
      }
      await t.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

Future<void> capture(WidgetTester t, String name) async {
  expect(t.takeException(), isNull, reason: name);
  for (final e in find.byType(AppBar).evaluate()) {
    e.findRenderObject()?.markNeedsPaint();
  }
  await t.pump();
  await t.runAsync(() async {
    final dir = Directory('docs/mobile/stage5-20261006');
    await dir.create(recursive: true);
    final bitmap = await t
        .renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey))
        .toImage();
    try {
      final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      bitmap.dispose();
    }
  });
}
