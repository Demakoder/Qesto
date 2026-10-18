import 'dart:convert';
import 'dart:io';

double median(Iterable<num> x) {
  final a = x.map((n) => n.toDouble()).toList()..sort();
  return a[a.length ~/ 2];
}

void main() {
  final tests = <Object>[];
  for (final f in Directory(
    'results',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.jsonl'))) {
    final events = f
        .readAsLinesSync()
        .where((s) => s.startsWith('{'))
        .map(jsonDecode)
        .toList();
    final visible = {
      for (final e in events.where((e) => e['type'] == 'testStart'))
        e['test']['id']: e['test']['name'],
    };
    final done = events
        .where(
          (e) =>
              e['type'] == 'testDone' &&
              e['hidden'] != true &&
              visible.containsKey(e['testID']),
        )
        .toList();
    tests.add({
      'file': f.path.replaceAll('\\', '/'),
      'passed': done
          .where((e) => e['result'] == 'success' && e['skipped'] != true)
          .length,
      'failed': done.where((e) => e['result'] != 'success').length,
      'skipped': done.where((e) => e['skipped'] == true).length,
      'success': events
          .where((e) => e['type'] == 'done')
          .lastOrNull?['success'],
    });
  }
  final benches = <Object>[];
  for (final count in [1000, 10000]) {
    for (final mode in ['full', 'effects']) {
      final result = jsonDecode(
        File('results/benchmark-$mode-$count.json').readAsStringSync(),
      );
      final s = (result['samples'] as List).cast<Map>();
      benches.add({
        'mode': mode,
        'count': count,
        'complete': result['complete'],
        'local_ms': median(s.map((s) => s['local']['total_ms'] as num)),
        'sender_ms': median(s.map((s) => s['sender']['total_ms'] as num)),
        'receiver_ms': median(s.map((s) => s['receiver']['total_ms'] as num)),
        'host_cpu_us': median(s.map((s) => s['host_cpu_us'] as num)),
        'peak_rss_mib': s
            .map((s) => (s['peak_rss_bytes'] as num) / 1048576)
            .reduce((a, b) => a > b ? a : b),
        'payload_equivalent_bytes': median(
          s.map((s) => s['local_payload_json_equivalent_bytes'] as num),
        ),
        'last_files_a': s.last['files_a'],
        'last_files_b': s.last['files_b'],
        'last_storage_a': s.last['storage_a'],
        'last_storage_b': s.last['storage_b'],
        'last_http_a': s.last['http_a'],
        'last_http_b': s.last['http_b'],
      });
    }
  }
  final summary = {
    'tests': tests,
    'benchmarks': benches,
    'startup': jsonDecode(
      File('results/startup-50000.json').readAsStringSync(),
    ),
    'analysis': jsonDecode(File('results/analyze.json').readAsStringSync()),
  };
  File(
    'results/summary.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
  stdout.writeln(jsonEncode(summary));
}
