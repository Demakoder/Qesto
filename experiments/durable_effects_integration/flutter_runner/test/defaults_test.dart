import 'package:qesto_windows_ui_sync_experiment/harness.dart';
import '../../../windows_synthetic_ui_sync/flutter_runner/test/two_ui_hosts_test.dart'
    as ui;
import '../../../windows_synthetic_ui_sync/flutter_runner/test/semantic_gate_test.dart'
    as semantics;

void main() {
  semantics.main();
  ui.main(
    harnessFactory: () => UiSyncHarness(
      root: '../../windows_synthetic_ui_sync',
      evidence: '../../windows_synthetic_ui_sync/results',
      serverExecutable: '../build/server/bundle/bin/server.exe',
    ),
    evidenceFile: '../results/default-two-ui.json',
  );
}
