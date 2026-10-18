import '../../windows_synthetic_ui_sync/test/integration_test.dart'
    as contracts;
import 'package:qesto_incremental_sync_experiment/harness.dart';

void main() => contracts.main(
  harnessFactory: () => IncrementalHarness(),
  extraCrashStages: ['chunk-after-row'],
);
