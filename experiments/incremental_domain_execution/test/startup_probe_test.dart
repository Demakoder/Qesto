import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto_windows_ui_sync_experiment/harness.dart';
import '../lib/harness.dart';

void main() {
  final runs = <Object>[];
  for (final count in [1000, 10000]) {
    for (final mode in ['baseline', 'bounded']) {
      test(
        'native worker $mode startup/reopen $count with normal sync binding',
        () async {
          final UiSyncHarness h = mode == 'bounded'
              ? DomainMemoryHarness()
              : UiSyncHarness(
                  root: '../windows_synthetic_ui_sync',
                  evidence: '../windows_synthetic_ui_sync/results',
                );
          try {
            await h.start(count: count);
            final server = await h.server();
            final watch = Stopwatch()..start();
            var owner = await h.open(server, 0, create: true);
            final startupUs = watch.elapsedMicroseconds;
            await owner.close();
            watch.reset();
            owner = await h.open(server, 0);
            final reopenUs = watch.elapsedMicroseconds;
            // h.open defaults create:false (assert the same original revision).
            expect((await owner.load()).revision, 0);
            await owner.close();
            runs.add({
              'mode': mode,
              'count': count,
              'startup_us': startupUs,
              'reopen_us': reopenUs,
              'runtime':
                  'Dart JIT real Windows worker + AOT server; no UI render',
              'trials': 1,
            });
          } finally {
            await h.close();
          }
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  }
  tearDownAll(
    () =>
        File('results/startup-reopen.json').writeAsStringSync(jsonEncode(runs)),
  );
}
