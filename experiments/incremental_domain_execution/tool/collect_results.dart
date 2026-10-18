import 'dart:convert';
import 'dart:io';

dynamic read(String name) =>
    jsonDecode(File('results/$name').readAsStringSync());
double mean(Iterable<num> values) {
  final a = values.toList();
  return a.reduce((a, b) => a + b) / a.length;
}
num median(Iterable<num> values) {
  final a = values.toList()..sort();
  return a[a.length ~/ 2];
}

Map<String, Object?> suite(String name) {
  final rows = File(
    'results/$name',
  ).readAsLinesSync().where((s) => s.startsWith('{')).map(jsonDecode).toList();
  final done = rows.where((r) => r['type'] == 'testDone').toList();
  return {
    'file': name,
    'passed': done
        .where(
          (r) =>
              r['result'] == 'success' &&
              r['hidden'] != true &&
              r['skipped'] != true,
        )
        .length,
    'failed': done.where((r) => r['result'] != 'success').length,
    'complete': rows.any((r) => r['type'] == 'done'),
    'success': rows.where((r) => r['type'] == 'done').lastOrNull?['success'],
  };
}

void main() {
  final suites = [
    for (final n in [
      'domain-native.jsonl',
      'domain-ui.jsonl',
      'resource-tests.jsonl',
      'startup-tests.jsonl',
      'boundary-regression.jsonl',
      'shared-parity.jsonl',
      '4c-native-regression.jsonl',
      'client-regression.jsonl',
      'backend-regression.jsonl',
      'storage-regression.jsonl',
      'app-regression.jsonl',
      'matched-1.jsonl',
      'matched-0.jsonl',
      'bounded-50k.jsonl',
    ])
      suite(n),
  ];
  final benchmarks = <Object>[];
  for (final file in [
    'baseline-4c-flutter-baseline-1000-10000.json',
    'baseline-4c-flutter-incremental-1000-10000.json',
    'flutter-baseline-1000-10000.json',
    'flutter-bounded-memory-1000-10000.json',
  ]) {
    for (final run in read(file)['runs']) {
      final s = run['samples'] as List;
      benchmarks.add({
        'file': file,
        'count': run['count'],
        'trials': s.length,
        for (final phase in ['local_edit', 'outbound_sync', 'incoming_sync'])
          '${phase}_mean_ms': mean(s.map((e) => e[phase]['total_ms'] as num)),
        for (final phase in ['local_edit', 'outbound_sync', 'incoming_sync'])
          '${phase}_median_ms': median(s.map((e) => e[phase]['total_ms'] as num)),
        'peak_mib':
            s
                .map((e) => e['peak_rss_bytes'] as num)
                .reduce((a, b) => a > b ? a : b) /
            1048576,
        'host_cpu_mean_ms':
            mean(s.map((e) => e['host_cpu_us_three_phases'] as num)) / 1000,
        'max_ui_timer_gap_ms': s
            .expand(
              (e) => [
                for (final p in [
                  'local_edit',
                  'outbound_sync',
                  'incoming_sync',
                ])
                  e[p]['max_primary_isolate_timer_gap_ms'] as num,
              ],
            )
            .reduce((a, b) => a > b ? a : b),
        'last_files_a': s.last['files_a'],
        'last_files_b': s.last['files_b'],
      });
    }
  }
  final micro = <Object>[];
  for (final mode in ['baseline', 'prepared']) {
    for (final count in [1000, 10000, 50000]) {
      final j = read('domain-$mode-$count.json'),
          s = (j['samples'] as List).where((e) => e['warmup'] != true).toList();
      micro.add({
        'mode': mode,
        'count': count,
        'trials': s.length,
        'domain_mean_ms': mean(s.map((e) => e['domain_us'] as num)) / 1000,
        'domain_encode_receipt_mean_ms':
            mean(s.map((e) => e['domain_encode_receipt_us'] as num)) / 1000,
        'effect_capture_mean_ms':
            mean(s.map((e) => e['effect_capture_us'] as num)) / 1000,
        'peak_including_oracle_mib':
            s
                .map((e) => e['peak_including_oracle_bytes'] as num)
                .reduce((a, b) => a > b ? a : b) /
            1048576,
      });
    }
  }
  final result = {
    'synthetic_only': true,
    'decision':
        'NO-GO incremental integration; separate core effects/commit-publication contract required',
    'suites': suites,
    'total_passed_executions': suites.fold<int>(
      0,
      (n, s) => n + (s['passed'] as int),
    ),
    'known_failed_gate':
        '50k actual worker startup exceeds unchanged 30s deadline',
    'analyzers': [
      for (final f in Directory(
        'results',
      ).listSync().whereType<File>().where((f) => f.path.contains('analyze-')))
        {
          'file': f.path,
          'clean': f.readAsStringSync().contains('No issues found!'),
        },
    ],
    'benchmarks': benchmarks,
    'domain_microbench': micro,
    'startup_reopen': read('startup-reopen.json'),
    'source_verification': read('source-verification.json'),
  };
  File(
    'results/summary.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  stdout.writeln(
    jsonEncode({
      'passed': result['total_passed_executions'],
      'known_failure': result['known_failed_gate'],
    }),
  );
}
