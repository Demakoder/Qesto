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

    await tester.tap(find.byKey(const Key('mobile-more')));
    await tester.pumpAndSettle();
    final history = find.byKey(const Key('mobile-more-history'));
    await tester.ensureVisible(history);
    await tester.tap(history);
    await tester.pumpAndSettle();

    expect(find.text('История действий'), findsOneWidget);
    expect(
      find.text('Здесь появятся импорт выписок и добавленные операции'),
      findsOneWidget,
    );
  });
}
