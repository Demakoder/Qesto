import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/desktop/pages/desktop_recurring_page.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/statistics/presentation/sections/secondary_statistics_sections.dart';
import 'package:qesto/features/statistics/presentation/state/statistics_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/synoball/synoball.dart';
import 'recurring_detection_test.dart' show monthlyFixture;

void main() {
  BudgetController controller({int observations = 4}) {
    final data = UserFinancialData(
      user: const QestoUser(
        id: 'test',
        name: 'Test User',
        defaultCurrency: 'RUB',
      ),
      referenceDate: DateTime(2026, 4, 10),
      synoballState: SynoballState(
        transactions: monthlyFixture().take(observations).toList(),
      ),
    );
    // The stored cache is intentionally empty: first app open must rebuild it.
    const codec = UserFinancialDataCodec();
    return BudgetController(
      configuration: budgetConfiguration,
      financialData: codec.decode(codec.encode(data)),
    );
  }

  for (final width in [390.0, 1200.0]) {
    for (final stats in [false, true]) {
      testWidgets(
        'restored streams visible ${stats ? 'statistics' : 'desktop/mobile'} width $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final budget = controller();
          final statistics = StatisticsController(budgetController: budget);
          final scroll = ScrollController();
          addTearDown(budget.dispose);
          addTearDown(statistics.dispose);
          addTearDown(scroll.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildQestoTheme(),
              home: Scaffold(
                body: stats
                    ? RecurringStatisticsSection(
                        controller: statistics,
                        scrollController: scroll,
                      )
                    : DesktopRecurringPage(
                        controller: budget,
                        asOf: DateTime(2026, 4, 10),
                      ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(budget.upcomingExpenses, isEmpty);
          expect(budget.synoballState.recurringStreams, hasLength(1));
          expect(find.text('Unknown Cloud Service'), findsWidgets);
          expect(find.text('Регулярные платежи пока не найдены'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('two-payment series shown as possible repeat, not subscription', (
    tester,
  ) async {
    final budget = controller(observations: 2);
    addTearDown(budget.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildQestoTheme(),
        home: Scaffold(
          body: DesktopRecurringPage(
            controller: budget,
            asOf: DateTime(2026, 4, 10),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Возможные повторы'), findsOneWidget);
    expect(budget.financialState.mandatoryExpenses.minorUnits, 0);
  });

  testWidgets(
    'manual payment can be created, edited and removed without a transaction',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final budget = controller(observations: 0);
      addTearDown(budget.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildQestoTheme(),
          home: Scaffold(
            body: DesktopRecurringPage(
              controller: budget,
              asOf: DateTime(2026, 9, 30),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recurring-add-payment')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Название'),
        'Playerok',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Сумма'),
        '3000',
      );
      await tester.tap(find.text('Не повторять'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Еженедельно').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(budget.upcomingExpenses, hasLength(1));
      expect(budget.upcomingExpenses.single.recurrenceRule, 'weekly');
      expect(budget.transactions, isEmpty);
      expect(find.text('Playerok'), findsWidgets);

      final stored = const UserFinancialDataCodec().decode(
        const UserFinancialDataCodec().encode(
          budget.mergeInto(
            UserFinancialData(
              user: budget.user,
              referenceDate: budget.referenceDate,
            ),
          ),
        ),
      );
      expect(stored.upcomingExpenses.single.recurrenceRule, 'weekly');
      expect(stored.transactions, isEmpty);

      await tester.tap(find.text('Playerok').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Сумма'),
        '4500',
      );
      await tester.ensureVisible(find.text('Сохранить'));
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(budget.upcomingExpenses.single.amount, 4500);
      await tester.tap(find.text('Playerok').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Удалить'));
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();
      expect(budget.upcomingExpenses, isEmpty);
      expect(budget.transactions, isEmpty);
    },
  );

  // Explicit opt-in; no repository/native storage/bank calls. The ignored
  // private snapshot is never copied into fixtures or test failure messages.
  final directory = Platform.environment['QESTO_RECURRING_AUDIT_DIR'];
  test(
    'local snapshot: unchanged facts, codecs and diagnostic counts',
    () {
      final root = Directory(directory!).absolute.resolveSymbolicLinksSync();
      final allowed = Directory(
        '../../.codex_tmp',
      ).absolute.resolveSymbolicLinksSync();
      expect(root.startsWith('$allowed${Platform.pathSeparator}'), isTrue);
      final data = const UserFinancialDataCodec().decode(
        File('$root/financial-snapshot.json').readAsStringSync(),
      );
      final before = data.synoballState!;
      final diagnostics = <RecurringDiagnostic>[];
      final streams = const EnrichmentEngine().detectRecurring(
        before.transactions,
        onDiagnostic: diagnostics.add,
      );
      final budget = BudgetController(
        configuration: budgetConfiguration,
        financialData: data,
      );
      addTearDown(budget.dispose);
      final after = budget.synoballState;
      expect(after.transactions.length, before.transactions.length);
      for (var i = 0; i < before.transactions.length; i++) {
        Map<String, dynamic> facts(CanonicalTransaction t) => t.toJson()
          ..remove('isRecurring')
          ..remove('recurringStreamId');
        // Boolean comparison keeps sensitive field values out of a failure diff.
        expect(
          jsonEncode(facts(before.transactions[i])) ==
              jsonEncode(facts(after.transactions[i])),
          isTrue,
        );
      }
      expect(
        jsonEncode(before.accounts.map((a) => a.toJson()).toList()) ==
            jsonEncode(after.accounts.map((a) => a.toJson()).toList()),
        isTrue,
      );
      expect(after.recurringStreams.length, streams.length);
      final decoded = const UserFinancialDataCodec().decode(
        const UserFinancialDataCodec().encode(budget.mergeInto(data)),
      );
      expect(decoded.synoballState!.recurringStreams.length, streams.length);
      final reasons = <String, int>{};
      for (final d in diagnostics) {
        reasons.update(d.reason, (n) => n + 1, ifAbsent: () => 1);
      }
      File('$root/replay-report.json').writeAsStringSync(
        jsonEncode({
          'transactions': before.transactions.length,
          'previousStreams': before.recurringStreams.length,
          'newStreams': streams.length,
          'tentativeStreams': streams.where((s) => s.isTentative).length,
          'reasons': reasons,
          'financialFactsUnchanged': true,
          'balancesUnchanged': true,
          'persistenceRoundTrip': true,
        }),
      );
    },
    skip: directory == null ? 'Private local fixture not supplied' : false,
  );
}
