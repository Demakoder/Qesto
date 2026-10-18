import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/core/theme/qesto_theme.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto_windows_ui_sync_experiment/harness.dart';
import 'package:qesto_durable_effects_experiment/windows_driver.dart';
import 'package:qesto_owner_lifetime_experiment/heap_probe.dart';
import '../../../windows_synthetic_ui_sync/flutter_runner/test/two_ui_hosts_test.dart' show NoteHost;

void main() {
  testWidgets('50 alternating two-client durable edits and verified sync cycles', (tester) async {
    final run = Platform.environment['QESTO_4G_RUN']!;
    final count = int.parse(Platform.environment['QESTO_4G_COUNT'] ?? '1000');
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = UiSyncHarness(root: '../../windows_synthetic_ui_sync',
      evidence: '../../windows_synthetic_ui_sync/results', incremental: true,
      effectsDriver: const EffectsDriverFactory(boundedLifetime: true),
      serverExecutable: '../../durable_effects_integration/build/server/bundle/bin/server.exe');
    final boundaries = <EffectsNoteBoundary>[], controllers = <BudgetController>[];
    final evidence = <Object>[], gc = <Object>[];
    Future<void> capture(int n) async {
      gc.add(await captureHeap('../results/$run/cycles-heap-$n.json', 'cycle-$n'));
      File('../results/$run/cycles-gc.json').writeAsStringSync(jsonEncode(gc));
    }
    Future<void> cycle(int n) async {
      final sender = n % 2, receiver = 1 - sender;
      final tx = n % 3 == 2 ? 3 : n % 3;
      await controllers[sender].setTransactionNote('container-tx-$tx', 'Cycle $n', commandId: 'cycle-$n');
      expect(controllers[sender].lastNotePublicationWasDelta, true);
      await controllers[sender].syncTransactionNotes();
      await controllers[receiver].syncTransactionNotes();
      final page = await boundaries[receiver].inner.pageForTest();
      await boundaries[receiver].inner.applyPageForTest(page);
      // Empty pull and repeated page must not discard a verified owner.
      await controllers[receiver].syncTransactionNotes();
      const codec = UserFinancialDataCodec();
      final a = jsonDecode(codec.encode(controllers[0].mergeInto((await boundaries[0].inner.load()).data)));
      final b = jsonDecode(codec.encode(controllers[1].mergeInto((await boundaries[1].inner.load()).data)));
      expect(a, b); expect(a, (await h.serverState())['state']);
      final states = <Object>[];
      for (final boundary in boundaries) {
        expect(await boundary.inner.pending(), isEmpty);
        final state = await boundary.inner.inspectForTest();
        final cache = state['cache_metrics'] as Map;
        expect(cache['payloadBytes'], lessThanOrEqualTo(64 * 1024 * 1024));
        expect(cache['stagedEntries'], 0);
        states.add({'revision': state['revision'], 'cache': cache,
          'lifetime': state['lifetime_metrics'], 'checkpoint': state['checkpoint']});
      }
      evidence.add({'cycle': n + 1, 'fullParity': true, 'clients': states});
      File('../results/$run/cycles.json').writeAsStringSync(jsonEncode(evidence));
    }
    try {
      await tester.runAsync(() async {
        await h.start(count: count); final server = await h.server();
        for (var i = 0; i < 2; i++) {
          final b = EffectsNoteBoundary(await h.open(server, i, create: true));
          boundaries.add(b);
          controllers.add(BudgetController(configuration: budgetConfiguration,
            financialData: (await b.inner.load()).data, noteBoundary: b));
        }
      });
      await tester.pumpWidget(MaterialApp(theme: buildQestoTheme(), home: Scaffold(body: Row(children: [
        for (var i = 0; i < 2; i++) Expanded(child: NoteHost('$i', controllers[i], () {}, () {})),
      ]))));
      await tester.runAsync(() => capture(0));
      for (var n = 0; n < 50; n++) {
        await tester.runAsync(() => cycle(n));
        await tester.pump(); expect(tester.takeException(), isNull);
        if ([10, 25, 50].contains(n + 1)) await tester.runAsync(() => capture(n + 1));
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
      for (final c in controllers) { c.dispose(); }
      await tester.runAsync(() async {
        for (final b in boundaries) { await b.close(cancelPending: true); }
        await h.close();
      });
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
