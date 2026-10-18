import 'package:qesto_windows_ui_sync_experiment/harness.dart';
import 'dart:convert';
import 'package:test/test.dart';
import '../lib/windows_driver.dart';
import '../../windows_synthetic_ui_sync/test/integration_test.dart' as previous;

// Existing assertions and financial oracle unchanged; real effects driver and
// freshly compiled effects child process replace the old local implementation.
UiSyncHarness harness() => UiSyncHarness(
  root: '../windows_synthetic_ui_sync',
  evidence: '../windows_synthetic_ui_sync/results',
  incremental: true,
  effectsDriver: const EffectsDriverFactory(),
  serverExecutable: 'build/server/bundle/bin/server.exe',
  probeExecutable: 'build/client_probe/bundle/bin/client_probe.exe',
);
void main() {
  previous.main(harnessFactory: harness, extraCrashStages: ['chunk-after-row']);
  test(
    'effects worker death after COMMIT needs full process restart, keeps outbox',
    () async {
      final h = harness();
      await h.start();
      final s = await h.server();
      try {
        final owner = await h.open(s, 0, create: true);
        await owner.close();
        final killed = await h.child(s, 0, 'kill-worker');
        expect(killed.exitCode, 0, reason: '${killed.stdout} ${killed.stderr}');
        expect(jsonDecode((killed.stdout as String).trim()), {
          'unknown': true,
          'hot_reopen': false,
        });
        // The child process has exited, releasing native handles; only now reopen.
        final again = await h.open(s, 0);
        try {
          expect((await again.load()).revision, 1);
          expect((await again.pending()).single.receipt.id, 'kill-before-ui');
        } finally {
          await again.close();
        }
      } finally {
        await h.close();
      }
    },
  );
}
