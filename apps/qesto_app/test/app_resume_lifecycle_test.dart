import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/app/qesto_app.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/desktop/desktop_app_shell.dart';
import 'package:qesto/mocks/mock_qesto_repository.dart';

void main() {
  for (final failRefresh in [false, true]) {
    testWidgets(
      'resume retains the bank session and financial owner when deals refresh '
      '${failRefresh ? 'fails' : 'succeeds'}',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final repository = _ControlledRepository();
        await tester.pumpWidget(
          QestoApp(
            repository: repository,
            preferenceStore: MemoryKeyValueStore(),
          ),
        );
        await tester.pumpAndSettle();
        final shellFinder = find.byType(DesktopAppShell, skipOffstage: false);
        final original = tester.widget<DesktopAppShell>(shellFinder);
        final manager = original.bankSyncScheduler.manager;
        expect(manager.beginInteractiveSession('sber-lifecycle-test'), isTrue);

        // A pushed bank route retains references to this financial owner.
        // No CEF, real profile, secure storage or bank login is needed here.
        final navigator = Navigator.of(tester.element(shellFinder));
        unawaited(
          navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(
                body: Text('Open bank route', key: Key('bank-route-test')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final pending = Completer<List<Deal>>();
        repository.nextCoupons = pending;
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));

        expect(find.byKey(const Key('bank-route-test')), findsOneWidget);
        expect(
          shellFinder,
          findsOneWidget,
          reason: 'A public deals refresh must not dispose the bank owner.',
        );
        expect(
          tester.widget<DesktopAppShell>(shellFinder).controller,
          same(original.controller),
        );
        expect(repository.financialReads, 1);

        if (failRefresh) {
          pending.completeError(StateError('Public deals unavailable'));
        } else {
          pending.complete(const []);
        }
        await tester.pumpAndSettle();
        expect(
          tester.widget<DesktopAppShell>(shellFinder).bankSyncScheduler,
          same(original.bankSyncScheduler),
        );
        manager.endInteractiveSession('sber-lifecycle-test');
        expect(
          manager.beginInteractiveSession('sber-lifecycle-test'),
          isTrue,
          reason: 'The manager held by the open bank must not be disposed.',
        );
        manager.endInteractiveSession('sber-lifecycle-test');
        navigator.pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _ControlledRepository extends MockQestoRepository {
  _ControlledRepository() : super(delay: Duration.zero);

  Completer<List<Deal>>? nextCoupons;
  int financialReads = 0;

  @override
  Future<UserFinancialData> getUserFinancialData() {
    financialReads++;
    return super.getUserFinancialData();
  }

  @override
  Future<List<Deal>> getCoupons() => nextCoupons?.future ?? super.getCoupons();
}
