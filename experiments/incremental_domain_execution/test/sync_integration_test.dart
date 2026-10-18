import '../../windows_synthetic_ui_sync/test/integration_test.dart' as existing;
import '../lib/harness.dart';

void main() => existing.main(
  harnessFactory: () => DomainMemoryHarness(),
  extraCrashStages: ['chunk-after-row'],
);
