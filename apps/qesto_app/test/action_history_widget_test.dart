import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';

void main() {
  testWidgets('history button opens the action journal', (tester) async {
    await tester.pumpWidget(
      QestoApp(repository: const MockQestoRepository(delay: Duration.zero)),
    );
    await tester.pumpAndSettle();

    tester
        .state<ScaffoldState>(find.byKey(const Key('mobile-app-shell')))
        .openDrawer();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('action-history-button')),
      250,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const Key('action-history-button'))),
      alignment: 1,
    );
    await tester.tap(find.byKey(const Key('action-history-button')));
    await tester.pumpAndSettle();

    expect(find.text('История действий'), findsOneWidget);
    expect(
      find.text('Здесь появятся импорт выписок и добавленные операции'),
      findsOneWidget,
    );
  });
}
