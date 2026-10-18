import 'dart:convert';
import 'dart:io';

void main() {
  final suites = <String, Object>{};
  var total = 0;
  for (final name in [
    'boundary-tests',
    'controller-tests',
    'benchmark-tests',
    'app-regressions',
    'shared-parity',
    'storage-regressions',
  ]) {
    final events = [
      for (final line in File('results/$name.jsonl').readAsLinesSync())
        if (line.startsWith('{')) jsonDecode(line) as Map,
    ];
    final done = events.where((e) => e['type'] == 'done').lastOrNull;
    final tests = events
        .where((e) => e['type'] == 'testDone' && e['hidden'] != true)
        .toList();
    final errors = events.where((e) => e['type'] == 'error').length;
    final skips = tests.where((e) => e['skipped'] == true).length;
    final passed = tests
        .where((e) => e['result'] == 'success' && e['skipped'] != true)
        .length;
    if (done?['success'] != true || errors != 0 || skips != 0)
      throw StateError('Failed/incomplete $name');
    total += passed;
    suites[name] = {
      'passed': passed,
      'errors': errors,
      'skipped': skips,
      'milliseconds': done!['time'],
    };
  }
  final sources = jsonDecode(
    File('results/source_check.json').readAsStringSync(),
  );
  final bench = jsonDecode(
    File('results/flutter-benchmarks.json').readAsStringSync(),
  );
  if (sources['boundary_scope_passed'] != true || bench['complete'] != true)
    throw StateError('Evidence missing');
  for (final log in [
    'analyze.txt',
    'app-analyze.txt',
    'flutter-runner-analyze.txt',
  ]) {
    if (!File('results/$log').readAsStringSync().contains('No issues found!'))
      throw StateError(log);
  }
  File('results/summary.json').writeAsStringSync(
    jsonEncode({
      'time_utc': DateTime.now().toUtc().toIso8601String(),
      'stage': '4a',
      'synthetic_only': true,
      'platform': 'Windows x64',
      'suites': suites,
      'total_passed': total,
      'analyzers_clean': true,
      'source_scope': sources,
      'benchmark_counts': [1000, 10000],
      'installed_app_changed': false,
      'production_data_accessed': false,
    }),
    flush: true,
  );
  print(
    'Verified $total tests, analyzers, allowed production seam and synthetic benchmarks',
  );
}
