import 'package:qesto_incremental_domain_experiment/harness.dart';
import '../../../windows_synthetic_ui_sync/flutter_runner/test/two_ui_hosts_test.dart'
    as existing;

void main() =>
    existing.main(harnessFactory: () => DomainMemoryHarness(location: '..'));
