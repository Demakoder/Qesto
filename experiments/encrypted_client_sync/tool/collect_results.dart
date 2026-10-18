import 'dart:convert';
import 'dart:io';

void main() {
  final suites = <String, Object>{};
  var total = 0;
  for (final name in [
    'tests',
    'backend-regression-tests',
    'shared-core-tests',
    'storage-regression-tests',
    'app-regression-tests',
  ]) {
    final events = <Map>[];
    for (final line in File('results/$name.jsonl').readAsLinesSync()) {
      if (line.startsWith('{')) events.add(jsonDecode(line) as Map);
    }
    final done = events.where((e) => e['type'] == 'done').lastOrNull;
    final tests = events
        .where((e) => e['type'] == 'testDone' && e['hidden'] != true)
        .toList();
    final errors = events.where((e) => e['type'] == 'error').length;
    final skipped = tests.where((e) => e['skipped'] == true).length;
    final passed = tests
        .where((e) => e['result'] == 'success' && e['skipped'] != true)
        .length;
    if (done?['success'] != true || errors != 0 || skipped != 0)
      throw StateError('Suite failed: $name');
    total += passed;
    suites[name] = {
      'passed': passed,
      'errors': errors,
      'skipped': skipped,
      'milliseconds': done!['time'],
    };
  }
  final bench =
      jsonDecode(File('results/benchmarks.json').readAsStringSync()) as Map;
  final sources =
      jsonDecode(File('results/source_check.json').readAsStringSync()) as Map;
  if (bench['complete'] != true || sources['passed'] != true)
    throw StateError('Incomplete evidence');
  for (final file in ['analyze.txt', 'storage-analyze.txt']) {
    if (!File('results/$file').readAsStringSync().contains('No issues found!'))
      throw StateError('Analyzer $file');
  }
  File('results/summary.json').writeAsStringSync(
    jsonEncode({
      'time_utc': DateTime.now().toUtc().toIso8601String(),
      'stage': '3b',
      'platform': 'Windows x64',
      'synthetic_only': true,
      'suites': suites,
      'total_passed': total,
      'analyzers_clean': true,
      'production_and_shared_source_check': sources,
      'benchmark_counts': [1000, 10000],
    }),
    flush: true,
  );
  print(
    'Verified $total tests, clean analyzers and unchanged production/shared sources',
  );
}
