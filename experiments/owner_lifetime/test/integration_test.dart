import 'package:qesto_windows_ui_sync_experiment/harness.dart';
import 'package:qesto_durable_effects_experiment/windows_driver.dart';
import '../../windows_synthetic_ui_sync/test/integration_test.dart' as previous;
import 'evidence_redirect.dart';

void main() {
  redirectEvidence();
  previous.main(harnessFactory: () => UiSyncHarness(
    root: '../windows_synthetic_ui_sync', evidence: '../windows_synthetic_ui_sync/results',
    incremental: true, effectsDriver: const EffectsDriverFactory(boundedLifetime: true),
    serverExecutable: '../durable_effects_integration/build/server/bundle/bin/server.exe',
    probeExecutable: 'build/client_probe/bundle/bin/client_probe.exe'),
    extraCrashStages: ['chunk-after-row']);
}
