import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

Map<String, dynamic> read(String path) =>
    jsonDecode(File(path).readAsStringSync().replaceFirst('\ufeff', ''))
        as Map<String, dynamic>;
double median(Iterable<num> values) {
  final a = values.map((n) => n.toDouble()).toList()..sort();
  return a[a.length ~/ 2];
}

Map<String, Object> suite(String name) {
  final file = File('results/$name');
  final tests = <int, Map>{};
  var done = false, success = false, passed = 0, failed = 0;
  for (final line in file.readAsLinesSync()) {
    if (!line.startsWith('{')) continue;
    final r = jsonDecode(line) as Map;
    if (r['type'] == 'testStart')
      tests[r['test']['id'] as int] = r['test'] as Map;
    if (r['type'] == 'testDone' &&
        r['hidden'] != true &&
        !(tests[r['testID']]?['name'] as String? ?? '').startsWith(
          'loading ',
        )) {
      if (r['result'] == 'success' && r['skipped'] != true)
        passed++;
      else if (r['result'] != 'success')
        failed++;
    }
    if (r['type'] == 'done') {
      done = true;
      success = r['success'] == true;
    }
  }
  return {
    'name': name,
    'complete': done,
    'passed': passed,
    'failed': failed,
    'success': success,
  };
}

void main() {
  final names = [
    'native-final.jsonl',
    'ui-final.jsonl',
    'backend-regression.jsonl',
    'client-regression.jsonl',
    'storage-regression.jsonl',
    'shared-parity.jsonl',
    'old4b-regression.jsonl',
    'app-regression.jsonl',
    'flutter-matched-baseline.jsonl',
    'flutter-matched-incremental.jsonl',
    if (File('results/chunk-final-review.jsonl').existsSync())
      'chunk-final-review.jsonl',
  ];
  final suites = names.map(suite).toList();
  final analyzers = <String, Object>{};
  for (final p in [
    'incremental_sync_performance',
    'storage_feasibility',
    'encrypted_client_sync',
    'windows_integration_boundary',
    'windows_synthetic_ui_sync',
    'synthetic_sync_backend',
    'flutter-runner',
  ]) {
    final path = 'results/analyze-$p.txt', text = File(path).readAsStringSync();
    analyzers[p] = text.contains('No issues found!');
  }
  final baseline = read('results/source-baseline.json'),
      changed = <String>[],
      missing = <String>[];
  for (final e in baseline.entries) {
    final f = File('../../${e.key}');
    if (!f.existsSync()) {
      missing.add(e.key);
      continue;
    }
    if (sha256.convert(f.readAsBytesSync()).toString().toUpperCase() != e.value)
      changed.add(e.key);
  }
  final productionChanges = changed
      .where((s) => s.startsWith('apps/') || s.startsWith('packages/'))
      .toList();
  File('results/source-verification.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'checked': baseline.length,
      'changed': changed,
      'missing': missing,
      'production_or_core_changes': productionChanges,
    }),
  );
  final comparison = <Map<String, Object>>[];
  for (final mode in ['baseline', 'incremental']) {
    final data = read('results/flutter-$mode-1000-10000.json');
    if (data['complete'] != true) throw StateError('Incomplete benchmark');
    for (final r in data['runs'] as List) {
      final s = (r['samples'] as List).cast<Map>();
      comparison.add({
        'mode': mode,
        'count': r['count'],
        for (final key in ['local_edit', 'outbound_sync', 'incoming_sync'])
          '$key.median_ms': median(s.map((v) => v[key]['total_ms'] as num)),
        'host_cpu_median_ms':
            median(s.map((v) => v['host_cpu_us_three_phases'] as num)) / 1000,
        'peak_rss_MiB': s
            .map((v) => (v['peak_rss_bytes'] as int) / (1024 * 1024))
            .reduce((a, b) => a > b ? a : b),
        'max_timer_gap_ms': s
            .expand(
              (v) => [
                'local_edit',
                'outbound_sync',
                'incoming_sync',
              ].map((k) => v[k]['max_primary_isolate_timer_gap_ms'] as num),
            )
            .reduce((a, b) => a > b ? a : b),
        'ui_pump_median_ms':
            median(s.map((v) => v['two_details_ui_pump_us'] as num)) / 1000,
      });
    }
  }
  final knownGate = suite('flutter-50k.jsonl');
  final old10k = comparison.singleWhere(
    (r) => r['mode'] == 'baseline' && r['count'] == 10000,
  );
  final new10k = comparison.singleWhere(
    (r) => r['mode'] == 'incremental' && r['count'] == 10000,
  );
  final payload = read('results/chunk-write-evidence.json');
  final budgets = {
    'local_10k_le_3000_ms': (new10k['local_edit.median_ms'] as num) <= 3000,
    'receiver_10k_le_6000_ms':
        (new10k['incoming_sync.median_ms'] as num) <= 6000,
    'peak_rss_growth_le_10_percent':
        (new10k['peak_rss_MiB'] as num) <=
        (old10k['peak_rss_MiB'] as num) * 1.1,
    'financial_payload_lt_5_percent':
        (payload['metrics']['written_payload_bytes'] as num) <
        (payload['full_bytes'] as num) * 0.05,
  };
  final result = {
    'synthetic_only': true,
    'suites': suites,
    'analyzers': analyzers,
    'passed_cases': suites.fold<int>(0, (n, s) => n + (s['passed'] as int)),
    'comparison': comparison,
    'production_changes': productionChanges,
    'known_failed_gate': {
      'result': knownGate,
      'cause':
          '30s WindowsNoteBoundary startup timeout at 50k; not end-to-end verified',
    },
    'budgets': budgets,
    'performance_budgets_met': budgets.values.every((v) => v),
    'measurement_limitations': [
      'Passed cases count suite executions, not unique test definitions; suites overlap.',
      'Server phases.codec_decode.input_bytes in retained evidence is UTF-16 code units, not UTF-8 bytes. profile-baseline.input_bytes, server.server bytes, HTTP and written_payload_bytes are UTF-8 byte counts.',
      'CPU is host GetProcessTimes including both workers, not total system/PostgreSQL CPU.',
      'Frame is Flutter test pump wall time, not release display/raster p95.',
      'Storage payload and HTTP body counts are not physical SSD writes or full wire traffic.',
    ],
    'production_rollout_approved': false,
  };
  File(
    'results/summary.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  if (suites.any((s) => s['success'] != true) ||
      analyzers.values.any((v) => v != true) ||
      productionChanges.isNotEmpty ||
      missing.isNotEmpty)
    exitCode = 1;
}
