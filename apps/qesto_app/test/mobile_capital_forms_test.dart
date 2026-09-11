import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/desktop/desktop_app_shell.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';

void main() {
  for (final route in ['goals', 'debts', 'investments', 'liquidity']) {
    testWidgets('phone can create $route with shared capital editor', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        QestoApp(
          preferenceStore: MemoryKeyValueStore(),
          repository: const MockQestoRepository(delay: Duration.zero),
        ),
      );
      await tester.pumpAndSettle();
      final handler = FlutterError.onError!;
      FlutterError.onError = (details) {
        FlutterError.dumpErrorToConsole(details, forceReport: true);
        handler(details);
      };
      tester
          .state<ScaffoldState>(find.byKey(const Key('mobile-app-shell')))
          .openDrawer();
      await tester.pumpAndSettle();
      final destination = find.byKey(Key('mobile-destination-$route'));
      await tester.scrollUntilVisible(
        destination,
        250,
        scrollable: find.descendant(
          of: find.byType(Drawer),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(destination);
      await tester.pumpAndSettle();
      final button = route == 'liquidity'
          ? find.text('Добавить счёт')
          : find.byKey(
              Key(switch (route) {
                'goals' => 'goal-add-button',
                'debts' => 'debt-add-button',
                _ => 'investment-add-button',
              }),
            );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'editor $route');
      final fields = switch (route) {
        'goals' => [
          'goal-title-field',
          'goal-target-field',
          'goal-save-button',
        ],
        'debts' => [
          'debt-name-field',
          'debt-balance-field',
          'debt-save-button',
        ],
        'investments' => [
          'investment-name-field',
          'investment-balance-field',
          'investment-save-button',
        ],
        _ => [
          'account-name-field',
          'account-balance-field',
          'account-add-confirm',
        ],
      };
      await tester.enterText(find.byKey(Key(fields[0])), 'Мобильный тест');
      await tester.ensureVisible(find.byKey(Key(fields[1])));
      await tester.enterText(find.byKey(Key(fields[1])), '10000');
      await tester.ensureVisible(find.byKey(Key(fields[2])));
      await tester.tap(find.byKey(Key(fields[2])));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<DesktopAppShell>(find.byType(DesktopAppShell))
          .controller;
      expect(
        route == 'goals'
            ? controller.savingsGoals.any((g) => g.title == 'Мобильный тест')
            : controller.accounts.any((a) => a.title == 'Мобильный тест'),
        isTrue,
      );
      expect(tester.takeException(), isNull, reason: 'saved $route');
    });
  }
}
