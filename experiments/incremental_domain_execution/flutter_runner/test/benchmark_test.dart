import 'dart:io';
import 'package:qesto_incremental_domain_experiment/harness.dart';
import '../../../incremental_sync_performance/flutter_runner/test/benchmark_test.dart'
    as existing;

void main() {
  final baseline = Platform.environment['QESTO_4D_BASELINE'] == '1';
  existing.main(
    harnessFactory: baseline ? null : () => DomainMemoryHarness(location: '..'),
    label: baseline ? 'baseline' : 'bounded-memory',
  );
}
