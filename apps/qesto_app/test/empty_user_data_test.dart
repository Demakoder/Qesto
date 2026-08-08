import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/core/widgets/qesto_elements.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';

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
    },
  );

  testWidgets('чистое приложение открывается без пользовательских данных', (
    tester,
  ) async {
    await tester.pumpWidget(
      const QestoApp(repository: MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(QestoButton), findsNWidgets(3));
  });
}
