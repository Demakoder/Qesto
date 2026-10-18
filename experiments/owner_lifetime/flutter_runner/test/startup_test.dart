import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:qesto_windows_ui_sync_experiment/harness.dart';
import 'package:qesto_durable_effects_experiment/windows_driver.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto_storage_spike/synthetic_trace.dart';

void main() {
  testWidgets('50k resource gate retains the original readiness deadline', (tester) async {
    final run = Platform.environment['QESTO_4G_RUN']!;
    final count = int.parse(Platform.environment['QESTO_4G_COUNT'] ?? '50000');
    final h = UiSyncHarness(
      root: '../../windows_synthetic_ui_sync', evidence: '../../windows_synthetic_ui_sync/results',
      incremental: true, effectsDriver: EffectsDriverFactory(boundedLifetime: run.contains('bounded')),
      serverExecutable: '../../durable_effects_integration/build/server/bundle/bin/server.exe',
    );
    await tester.runAsync(() async {
      var passed = false;
      String? failure;
      final all = Stopwatch()..start();
      final phases = <String, int>{};
      Future<T> time<T>(String phase, Future<T> Function() fn) async {
        final sw = Stopwatch()..start();
        try { return await fn(); } finally { phases[phase] = sw.elapsedMicroseconds; }
      }
      try {
        await time('fixtureAndServerSeed', () => h.start(count: count));
        final server = await time('serverReady', () => h.server());
        final owner = await time('snapshotFetchAndOwnerReady', () => h.open(server, 0, create: true));
        passed = true;
        final state = await time('loadAndSendPort', () => owner.load());
        final controller = SyntheticTrace.sync('startup.controller', () => BudgetController(
          configuration: budgetConfiguration, financialData: state.data,
        ));
        controller.dispose();
        await owner.close();
      } catch (e) { failure = e.toString(); }
      finally { await h.close(); }
      File('../results/$run/startup-$count.json').writeAsStringSync(jsonEncode({
        'passed': passed, 'failure': failure, 'count': count, 'ownerReadyDeadlineSeconds': 30,
        'phaseUs': phases, 'attemptUs': all.elapsedMicroseconds,
        'peakRss': ProcessInfo.maxRss, 'rss': ProcessInfo.currentRss, 'pid': pid,
        'runtime': 'isolated Flutter test VM + same Stage 4f AOT full server',
        'hotReopenAfterWorkerKill': false,
      }));
      stdout.writeln('Startup readiness: $passed (probe success is not readiness)');
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}
