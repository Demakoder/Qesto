import 'package:qesto_windows_ui_sync_experiment/harness.dart';
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'bounded_executor.dart';

class DomainMemoryHarness extends UiSyncHarness {
  DomainMemoryHarness({String location = '.'})
    : super(
        root: '$location/../windows_synthetic_ui_sync',
        evidence: '$location/../windows_synthetic_ui_sync/results',
        incremental: true,
        serverExecutable: '$location/build/server/bundle/bin/server.exe',
        probeExecutable:
            '$location/../incremental_sync_performance/build/client_probe/bundle/bin/client_probe.exe',
      );
  @override
  BoundedCoordinatorDomain domain(int i) => BoundedCoordinatorDomain(
    syntheticUser,
    profiles[i].workspace,
    epoch,
    policyDigest,
    profiles.map((p) => p.device).toList(),
  );
}
