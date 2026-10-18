import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/desktop/desktop_app_shell.dart';
import 'package:qesto/mobile/capital/mobile_capital_pages.dart';
import 'package:qesto/mobile/capital/mobile_capital_editor.dart';
import 'package:qesto/mobile/analytics/mobile_budget_page.dart';
import 'package:qesto/mobile/analytics/mobile_overview_page.dart';
import 'package:qesto/desktop/pages/desktop_transactions_page.dart';
import 'package:qesto/mobile/transactions/mobile_transaction_detail.dart';
import 'package:qesto/features/budget/transaction_editor_screen.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';

import 'fixtures/sample_user_financial_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final android = TargetPlatformVariant.only(TargetPlatform.android);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const notificationChannel = MethodChannel('ru.qesto.qesto/notifications');
  const notificationEvents = MethodChannel(
    'ru.qesto.qesto/notification_events',
  );

  setUp(() {
    messenger.setMockMethodCallHandler(notificationChannel, (call) async {
      return switch (call.method) {
        'hasAccess' => true,
        'readNotifications' => <Object?>[],
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(notificationEvents, (_) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(notificationChannel, null);
    messenger.setMockMethodCallHandler(notificationEvents, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    'mobile has four roots, secondary More and separate global add',
    (tester) async {
      await _boot(tester);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(
        bar.destinations.cast<NavigationDestination>().map(
          (item) => item.label,
        ),
        ['Обзор', 'Операции', 'Бюджет', 'Капитал'],
      );
      expect(find.byType(Drawer), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byKey(const Key('mobile-more')), findsOneWidget);
      expect(find.byKey(const Key('mobile-add-data')), findsOneWidget);
      expect(bar.selectedIndex, 0);
      await tester.tap(find.byKey(const Key('mobile-more')));
      await tester.pumpAndSettle();
      for (final item in [
        'benefits',
        'insights',
        'sources',
        'history',
        'trash',
        'categories',
        'settings',
      ]) {
        expect(find.byKey(Key('mobile-more-$item')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets('all four mounted roots retain their State when switching', (
    tester,
  ) async {
    await _boot(tester);
    final rootStates = <String, State>{};
    final pages = <String, Type>{
      'dashboard': MobileOverviewPage,
      'transactions': DesktopTransactionsPage,
      'budget': MobileBudgetPage,
      'capital': MobileCapitalLanding,
    };
    for (final entry in pages.entries) {
      await _selectRoot(tester, entry.key);
      rootStates[entry.key] = tester.state(find.byType(entry.value));
    }
    for (final entry in pages.entries) {
      await _selectRoot(tester, entry.key);
      expect(
        tester.state(find.byType(entry.value)),
        same(rootStates[entry.key]),
        reason: '${entry.key} must retain presentation state',
      );
    }
    expect(tester.takeException(), isNull);
  }, variant: android);

  testWidgets('Operations search survives switching roots and reselect', (
    tester,
  ) async {
    await _boot(tester);
    await _selectRoot(tester, 'transactions');
    await tester.tap(find.text('Поиск и фильтры'));
    await tester.pumpAndSettle();
    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'Поиск по операциям  /',
    );
    await tester.enterText(search, 'Пятёрочка');
    await tester.pumpAndSettle();
    await _selectRoot(tester, 'capital');
    await _selectRoot(tester, 'transactions');
    await _selectRoot(tester, 'transactions');
    expect(tester.widget<TextField>(search).controller?.text, 'Пятёрочка');
    expect(tester.takeException(), isNull);
  }, variant: android);

  testWidgets(
    'Overview period refreshes a retained route and stays selected',
    (tester) async {
      await _boot(tester);
      final before = tester.state(find.byType(MobileOverviewPage));
      await tester.tap(find.byKey(const Key('mobile-overview-period')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Июнь 2026'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<MobileOverviewPage>(find.byType(MobileOverviewPage))
            .period
            .id,
        'budget-2026-06',
      );
      await _selectRoot(tester, 'capital');
      await _selectRoot(tester, 'dashboard');
      expect(tester.state(find.byType(MobileOverviewPage)), same(before));
      expect(
        tester
            .widget<MobileOverviewPage>(find.byType(MobileOverviewPage))
            .period
            .id,
        'budget-2026-06',
      );
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets(
    'source permission attention remains visible from every root',
    (tester) async {
      messenger.setMockMethodCallHandler(notificationChannel, (call) async {
        return switch (call.method) {
          'hasAccess' => false,
          'readNotifications' => <Object?>[],
          _ => null,
        };
      });
      await _boot(tester);
      for (final root in ['dashboard', 'transactions', 'budget', 'capital']) {
        await _selectRoot(tester, root);
        expect(
          find.byKey(const Key('mobile-source-attention-banner')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Badge>(
                find.byKey(const Key('mobile-source-attention-badge')),
              )
              .isLabelVisible,
          isTrue,
        );
      }
      await tester.tap(find.byKey(const Key('mobile-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mobile-more-sources')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('mobile-source-status-page')),
        findsOneWidget,
      );
      expect(
        find.text('Доступ к уведомлениям не предоставлен'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('mobile-source-permission-settings')),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('mobile-source-attention-banner')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets('capital scroll and selected period survive switching roots', (
    tester,
  ) async {
    await _boot(tester);
    await _selectRoot(tester, 'capital');
    await tester.tap(find.text('Ликвидность'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('История: 1М'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3М'));
    await tester.pumpAndSettle();
    final capitalScroll = find
        .descendant(
          of: find.byType(MobileLiquidityPage),
          matching: find.byType(Scrollable),
        )
        .evaluate()
        .map((element) => (element as StatefulElement).state)
        .whereType<ScrollableState>()
        .firstWhere((state) => state.position.axis == Axis.vertical);
    capitalScroll.position.jumpTo(180);
    await tester.pumpAndSettle();
    final offset = capitalScroll.position.pixels;
    final periodElement = tester.state(find.byType(MobileLiquidityPage));
    await _selectRoot(tester, 'budget');
    await _selectRoot(tester, 'capital');
    expect(capitalScroll.position.pixels, offset);
    expect(tester.state(find.byType(MobileLiquidityPage)), same(periodElement));
    expect(tester.takeException(), isNull);
  }, variant: android);

  testWidgets(
    'transaction detail is a route retained across root switching',
    (tester) async {
      await _boot(tester);
      await _selectRoot(tester, 'transactions');
      final page = tester.widget<DesktopTransactionsPage>(
        find.byType(DesktopTransactionsPage),
      );
      expect(page.onOpenTransaction, isNotNull);
      final row = find
          .byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_TransactionTableRow',
          )
          .first;
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(MobileTransactionDetail), findsOneWidget);
      final id = tester
          .widget<MobileTransactionDetail>(find.byType(MobileTransactionDetail))
          .transactionId;
      expect(
        sampleUserFinancialData.transactions.any((item) => item.id == id),
        isTrue,
      );
      await _selectRoot(tester, 'capital');
      expect(find.byType(MobileTransactionDetail), findsNothing);
      await _selectRoot(tester, 'transactions');
      expect(find.byType(MobileTransactionDetail), findsOneWidget);
      expect(
        tester
            .widget<MobileTransactionDetail>(
              find.byType(MobileTransactionDetail),
            )
            .transactionId,
        id,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MobileTransactionDetail), findsNothing);
      expect(find.byType(DesktopTransactionsPage), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets(
    'legacy operation outside budget periods opens without creating a period',
    (tester) async {
      final operation = sampleUserFinancialData.transactions.first.copyWith(
        date: DateTime(2025, 12, 31),
      );
      final data = sampleUserFinancialData.copyWith(transactions: [operation]);
      final repository = _WriteRecordingRepository(financialData: data);
      await _boot(tester, repository: repository);
      final controller = tester
          .widget<DesktopAppShell>(find.byType(DesktopAppShell))
          .controller;
      expect(
        controller.periods.any((period) => period.contains(operation.date)),
        isFalse,
      );
      const codec = UserFinancialDataCodec();
      final before = codec.encode(controller.mergeInto(data));
      await _selectRoot(tester, 'transactions');
      await tester.tap(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget.runtimeType.toString() == '_TransactionTableRow',
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(MobileTransactionDetail), findsOneWidget);
      expect(
        tester
            .widget<MobileTransactionDetail>(
              find.byType(MobileTransactionDetail),
            )
            .transactionId,
        operation.id,
      );
      expect(codec.encode(controller.mergeInto(data)), before);
      expect(repository.writes, 0);
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets(
    'overview drilldown does not overwrite Operations root filters',
    (tester) async {
      await _boot(tester);
      final overviewState = tester.state(find.byType(MobileOverviewPage));
      final overview = tester.widget<MobileOverviewPage>(
        find.byType(MobileOverviewPage),
      );
      final ids = [sampleUserFinancialData.transactions.first.id];
      overview.onOpenFilteredTransactions(ids);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DesktopTransactionsPage>(
              find.byType(DesktopTransactionsPage),
            )
            .initialTransactionIds,
        ids,
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      final scopedState = tester.state(find.byType(DesktopTransactionsPage));
      final scoped = tester.widget<DesktopTransactionsPage>(
        find.byType(DesktopTransactionsPage),
      );
      scoped.onOpenTransaction!(ids.single);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('mobile-transaction-edit')),
        200,
      );
      await tester.tap(find.byKey(const Key('mobile-transaction-edit')));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionEditorScreen), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('transaction-merchant')),
        'Исправленный продавец',
      );
      await tester.tap(find.byKey(const Key('transaction-save')));
      await tester.pumpAndSettle();
      expect(find.byType(MobileTransactionDetail), findsOneWidget);
      expect(find.text('Исправленный продавец'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(DesktopTransactionsPage)),
        same(scopedState),
      );
      expect(
        tester
            .widget<DesktopTransactionsPage>(
              find.byType(DesktopTransactionsPage),
            )
            .initialTransactionIds,
        ids,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.state(find.byType(MobileOverviewPage)),
        same(overviewState),
      );
      await _selectRoot(tester, 'transactions');
      expect(
        tester
            .widget<DesktopTransactionsPage>(
              find.byType(DesktopTransactionsPage),
            )
            .initialTransactionIds,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets('More leaf Back returns More and then the originating root', (
    tester,
  ) async {
    await _boot(tester);
    await _selectRoot(tester, 'capital');
    final capitalState = tester.state(find.byType(MobileCapitalLanding));
    await tester.tap(find.byKey(const Key('mobile-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobile-more-categories')));
    await tester.pumpAndSettle();
    expect(find.text('Категории и теги'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-more-categories')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-more-categories')), findsNothing);
    expect(tester.state(find.byType(MobileCapitalLanding)), same(capitalState));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    expect(tester.takeException(), isNull);
  }, variant: android);

  testWidgets('Back at a root delegates host exit without changing root', (
    tester,
  ) async {
    var hostExits = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') hostExits++;
      return null;
    });
    await _boot(tester);
    await _selectRoot(tester, 'budget');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(hostExits, 1);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(tester.takeException(), isNull);
  }, variant: android);

  testWidgets('global add closes before any root navigation on Back', (
    tester,
  ) async {
    await _boot(tester);
    await _selectRoot(tester, 'capital');
    final state = tester.state(find.byType(MobileCapitalLanding));
    await tester.tap(find.byKey(const Key('mobile-add-data')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-data-manual')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-data-manual')), findsNothing);
    expect(tester.state(find.byType(MobileCapitalLanding)), same(state));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    expect(tester.takeException(), isNull);
  }, variant: android);

  testWidgets(
    'global account editor preserves originating root and Android dirty Back',
    (tester) async {
      await _boot(tester);
      await _selectRoot(tester, 'budget');
      final state = tester.state(find.byType(MobileBudgetPage));
      await tester.tap(find.byKey(const Key('mobile-add-data')));
      await tester.pumpAndSettle();
      final account = find.byKey(const Key('add-data-account'));
      await tester.ensureVisible(account);
      await tester.pumpAndSettle();
      await tester.tap(account);
      await tester.pumpAndSettle();
      expect(find.byType(MobileCapitalEditor), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('account-name-field')),
        'Dirty',
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Отменить изменения?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('capital-discard-confirm')));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(MobileBudgetPage)), same(state));
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(tester.takeException(), isNull);
    },
    variant: android,
  );

  testWidgets('navigation alone never writes or changes financial data', (
    tester,
  ) async {
    final repository = _WriteRecordingRepository();
    await _boot(tester, repository: repository);
    final controller = tester
        .widget<DesktopAppShell>(find.byType(DesktopAppShell))
        .controller;
    const codec = UserFinancialDataCodec();
    final before = codec.encode(controller.mergeInto(sampleUserFinancialData));
    for (final root in ['transactions', 'budget', 'capital', 'dashboard']) {
      await _selectRoot(tester, root);
    }
    await tester.tap(find.byKey(const Key('mobile-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mobile-more-history')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(codec.encode(controller.mergeInto(sampleUserFinancialData)), before);
    expect(repository.writes, 0);
    expect(repository.deletions, 0);
    expect(tester.takeException(), isNull);
  }, variant: android);
}

Future<void> _boot(
  WidgetTester tester, {
  MockQestoRepository? repository,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    QestoApp(
      preferenceStore: MemoryKeyValueStore(),
      repository:
          repository ??
          MockQestoRepository(
            delay: Duration.zero,
            financialData: sampleUserFinancialData,
          ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'initial mobile shell');
}

Future<void> _selectRoot(WidgetTester tester, String root) async {
  await tester.tap(find.byKey(Key('mobile-root-$root')));
  await tester.pumpAndSettle();
}

class _WriteRecordingRepository extends MockQestoRepository {
  _WriteRecordingRepository({UserFinancialData? financialData})
    : super(
        delay: Duration.zero,
        financialData: financialData ?? sampleUserFinancialData,
      );
  int writes = 0;
  int deletions = 0;

  @override
  Future<void> saveUserFinancialData(UserFinancialData data) async {
    writes++;
  }

  @override
  Future<void> deleteUserFinancialData() async {
    deletions++;
  }
}
