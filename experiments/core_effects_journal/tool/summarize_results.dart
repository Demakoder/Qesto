import 'dart:convert';
import 'dart:io';

num median(Iterable<num> input) {
  final values = input.toList()..sort();
  return values[values.length ~/ 2];
}

dynamic read(String name) =>
    jsonDecode(File('results/$name').readAsStringSync());

void main() {
  final suites = <String, dynamic>{};
  for (final name in [
    'shared-before',
    'shared-after',
    'journal-after',
    '4d-regression',
    'app-regression',
  ]) {
    final events = File('results/$name.jsonl')
        .readAsLinesSync()
        .where((l) => l.trimLeft().startsWith('{'))
        .map(jsonDecode)
        .toList();
    final done = events.where((e) => e['type'] == 'done').last;
    final tests = events
        .where((e) => e['type'] == 'testDone' && e['hidden'] == false)
        .toList();
    suites[name] = {
      'success': done['success'],
      'milliseconds': done['time'],
      'passed': tests
          .where((e) => e['result'] == 'success' && e['skipped'] == false)
          .length,
      'skipped': tests.where((e) => e['skipped'] == true).length,
      'failed': tests.where((e) => e['result'] != 'success').length,
    };
    if (done['success'] != true) throw StateError('Failed suite $name');
  }
  final benchmarks = <dynamic>[];
  for (final count in [1000, 10000, 50000]) {
    for (final mode in ['domain-only', 'journal', 'full-diff']) {
      final result = read('$mode-$count.json');
      final samples = (result['samples'] as List)
          .where((e) => e['warmup'] == false)
          .toList();
      if ((result['samples'] as List).any(
        (e) => e['full_codec_parity'] != true,
      ))
        throw StateError('Parity failed');
      final row = <String, dynamic>{
        'mode': mode,
        'count': count,
        'trials': samples.length,
        'admission_and_initial_projection_us':
            result['admission_and_initial_projection_us'],
      };
      for (final key in [
        'execution_us',
        'execution_cpu_us',
        'journal_recording_us',
        'projection_us',
        'full_diff_capture_us',
        'full_diff_cpu_us',
        'result_encode_us',
        'effect_bytes',
        'oracle_verify_us',
        'changed_canonical',
      ]) {
        final values = samples.map((e) => e[key]).whereType<num>().toList();
        row['median_$key'] = values.isEmpty ? null : median(values);
      }
      row['median_full_preparation_us'] = median(
        samples.map(
          (e) =>
              (e['execution_us'] +
                      e['projection_us'] +
                      e['full_diff_capture_us'] +
                      e['result_encode_us'])
                  as num,
        ),
      );
      row['peak_including_oracle_bytes'] = (result['samples'] as List)
          .map((e) => e['peak_including_oracle_bytes'] as int)
          .reduce((a, b) => a > b ? a : b);
      benchmarks.add(row);
    }
  }
  final allocation = <String, dynamic>{};
  for (final mode in ['domain-only', 'journal', 'full-diff']) {
    final r = read('$mode-10000-allocation.json');
    allocation[mode] = {
      'memoryUsage': r['allocation']['memoryUsage'],
      'peak_before_oracle_bytes': r['samples'][0]['peak_before_oracle_bytes'],
      'effect_bytes': r['samples'][0]['effect_bytes'],
    };
  }
  final summary = {
    'synthetic_only': true,
    'generated_at_utc': DateTime.now().toUtc().toIso8601String(),
    'suites': suites,
    'benchmarks': benchmarks,
    'allocation_10000': allocation,
    'retention': read('abort-retention.json'),
    'notes': [
      'Standalone Windows Dart JIT, not UI/server/storage timings.',
      'Full-diff includes app roots; journal is core collections only, not a full substitute.',
      'Timing peaks may include earlier oracle allocations. Separate allocation runs measure before oracle.',
    ],
  };
  File(
    'results/summary.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(summary));
}
