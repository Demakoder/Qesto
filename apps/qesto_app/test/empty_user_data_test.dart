import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';
import 'package:qesto/mobile/analytics/mobile_overview_page.dart';

void main() {
  test(
    'приложение загружает единый пустой пользовательский документ',
    () async {
      const repository = MockQestoRepository(delay: Duration.zero);

      final appData = await repository.loadAppData();
      final data = appData.financialData;

      expect(data.accounts, isEmpty);
      expect(data.budgetPeriods, isEmpty);
      expect(data.categoryBudgets, isEmpty);
      expect(data.transactions, isEmpty);
      expect(data.upcomingExpenses, isEmpty);
      expect(data.plannedCumulativePoints, isEmpty);
      expect(data.savingsGoals, isEmpty);
      expect(data.trackedProducts, isEmpty);
      expect(data.actions, isEmpty);
    },
  );

  testWidgets('чистое приложение открывается без пользовательских данных', (
    tester,
  ) async {
    await tester.pumpWidget(
      QestoApp(repository: const MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byKey(const Key('mobile-add-data')), findsOneWidget);
    expect(find.byType(MobileOverviewPage), findsOneWidget);
    final controller = tester
        .widget<MobileOverviewPage>(find.byType(MobileOverviewPage))
        .controller;
    // The unchanged controller supplies a technical account, not user data.
    expect(controller.accounts, hasLength(1));
    expect(controller.accounts.single.id, 'local-default-account');
    expect(controller.accounts.single.balanceMinor, 0);
    expect(controller.synoballState.accounts.single.isVirtual, isTrue);
    expect(controller.transactions, isEmpty);
    expect(find.text('Данные о капитале ещё не добавлены'), findsOneWidget);
  });
}
