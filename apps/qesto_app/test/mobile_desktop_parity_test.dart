import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/desktop/desktop_destination.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';
import 'package:qesto/mobile/analytics/mobile_analysis_page.dart';
import 'package:qesto/mobile/analytics/mobile_upcoming_page.dart';

import 'fixtures/sample_user_financial_data.dart';

void main() {
  setUp(() {
    final handler = FlutterError.onError!;
    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
      handler(details);
    };
  });
  for (final width in [360.0, 430.0]) {
    for (final route in [
      DesktopDestination.dashboard,
      DesktopDestination.insights,
      ...DesktopDestination.values.where((item) => item.section != null),
      DesktopDestination.settings,
    ]) {
      testWidgets(
        'mobile $width ${route.name} renders shared data without overflow',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            QestoApp(
              preferenceStore: MemoryKeyValueStore(),
              repository: MockQestoRepository(
                delay: Duration.zero,
                financialData: sampleUserFinancialData,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'initial overview');
          expect(find.byKey(const Key('mobile-app-shell')), findsOneWidget);
          final errorHandler = FlutterError.onError!;
          FlutterError.onError = (details) {
            FlutterError.dumpErrorToConsole(details, forceReport: true);
            errorHandler(details);
          };
          expect(find.byType(Drawer), findsNothing);
          await _openMobileDestination(tester, route);
          expect(tester.takeException(), isNull, reason: route.name);
          // Build the lower cards, including lazy lists; a clean first viewport
          // alone does not prove a desktop page can be used on a phone.
          final scrolls = find.byType(Scrollable);
          for (final element in scrolls.evaluate().toList()) {
            final state = (element as StatefulElement).state as ScrollableState;
            if (state.position.axis == Axis.vertical &&
                state.position.hasContentDimensions) {
              state.position.jumpTo(state.position.maxScrollExtent);
            }
          }
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${route.name} bottom',
          );
        },
      );
    }
  }
  testWidgets(
    'mobile add menu exposes every desktop import and Android inbox',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        QestoApp(
          preferenceStore: MemoryKeyValueStore(),
          repository: const MockQestoRepository(delay: Duration.zero),
        ),
      );
      await tester.pumpAndSettle();
      final errorHandler = FlutterError.onError!;
      FlutterError.onError = (details) {
        FlutterError.dumpErrorToConsole(details, forceReport: true);
        errorHandler(details);
      };
      await tester.tap(find.byKey(const Key('mobile-add-data')));
      await tester.pumpAndSettle();
      for (final action in [
        'manual',
        'voice',
        'receipt',
        'screenshot',
        'statement',
        'excel',
        'account',
        'inbox',
      ]) {
        expect(find.byKey(Key('add-data-$action')), findsOneWidget);
      }
      await tester.ensureVisible(find.byKey(const Key('add-data-excel')));
      await tester.tap(find.byKey(const Key('add-data-excel')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _openMobileDestination(
  WidgetTester tester,
  DesktopDestination destination,
) async {
  if (destination == DesktopDestination.dashboard) return;
  final root = switch (destination) {
    DesktopDestination.transactions => 'transactions',
    DesktopDestination.budget ||
    DesktopDestination.expenses ||
    DesktopDestination.cashFlow ||
    DesktopDestination.rhythm ||
    DesktopDestination.recurring => 'budget',
    DesktopDestination.liquidity ||
    DesktopDestination.investments ||
    DesktopDestination.debts ||
    DesktopDestination.goals => 'capital',
    _ => null,
  };
  if (root == null) {
    await tester.tap(find.byKey(const Key('mobile-more')));
    await tester.pumpAndSettle();
    final link = find.byKey(Key('mobile-more-${destination.name}'));
    await tester.ensureVisible(link);
    await tester.tap(link);
  } else {
    await tester.tap(find.byKey(Key('mobile-root-$root')));
    await tester.pumpAndSettle();
    if (destination != DesktopDestination.transactions &&
        destination != DesktopDestination.budget &&
        destination != DesktopDestination.liquidity) {
      final link = find.byKey(Key('mobile-destination-${destination.name}'));
      if (root == 'budget' || root == 'capital') {
        await tester.scrollUntilVisible(
          link,
          300,
          scrollable: find.byType(Scrollable).last,
        );
      }
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();
      if (root == 'budget') {
        expect(
          find.byType(
            destination == DesktopDestination.recurring
                ? MobileUpcomingPage
                : MobileAnalysisPage,
          ),
          findsOneWidget,
        );
      }
    }
  }
  await tester.pumpAndSettle();
}
