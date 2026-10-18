import '../../../windows_synthetic_ui_sync/flutter_runner/test/two_ui_hosts_test.dart'
    as contracts;
import 'package:qesto_incremental_sync_experiment/harness.dart';

void main() => contracts.main(
  harnessFactory: () => IncrementalHarness(location: '..'),
  evidenceFile: '../results/two-ui-hosts.json',
);
