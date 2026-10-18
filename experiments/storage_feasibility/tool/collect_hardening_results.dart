import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

dynamic read(String path) => jsonDecode(File(path).readAsStringSync());
double median(Iterable<num> values) {
  final sorted = values.map((n) => n.toDouble()).toList()..sort();
  final n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

void main() {
  final tests = <String, Object?>{};
  for (final name in [
    'hardening_contracts_ab',
    'hardening_contracts_c',
    'hardening_shared_parity',
    'hardening_plugin_tests',
    'hardening_app_regression',
  ]) {
    final events = File('results/$name.jsonl')
        .readAsLinesSync()
        .where((l) => l.startsWith('{'))
        .map((l) => jsonDecode(l) as Map)
        .toList();
    final completed = events
        .where((e) => e['type'] == 'testDone' && e['hidden'] != true)
        .toList();
    tests[name] = {
      'passed': completed
          .where((e) => e['result'] == 'success' && e['skipped'] != true)
          .length,
      'skipped': completed.where((e) => e['skipped'] == true).length,
      'failed': completed.where((e) => e['result'] != 'success').length,
      'success': events.lastWhere((e) => e['type'] == 'done')['success'],
    };
  }
  final bench = read('results/hardening_benchmarks.json') as Map;
  final benchmarkSummary = <Object?>[];
  for (final count in [1000, 10000, 50000]) {
    final runs = (bench['runs'] as List)
        .cast<Map>()
        .where((r) => r['count'] == count)
        .toList();
    final initial = runs
        .map((r) => (r['samples'] as List).first as Map)
        .toList();
    final edits = runs
        .expand((r) => (r['samples'] as List).skip(1).cast<Map>())
        .toList();
    benchmarkSummary.add({
      'count': count,
      'initialMedianMs': median(initial.map((s) => s['totalMs'] as num)),
      'initialSerializeMedianMs': median(
        initial.map((s) => s['serializeAndConstructMs'] as num),
      ),
      'initialCommitCheckpointMedianMs': median(
        initial.map((s) => s['commitAndCheckpointMs'] as num),
      ),
      'initialCpuMedianMs': median(
        initial.map((s) => s['processCpuMs'] as num),
      ),
      'editTotalMedianMs': median(edits.map((s) => s['totalMs'] as num)),
      'editCpuMedianMs': median(edits.map((s) => s['processCpuMs'] as num)),
      'peakRssBytes': edits
          .map((s) => s['peakRss'] as int)
          .reduce((a, b) => a > b ? a : b),
      'currentRssBytesMedian': median(
        runs.map(
          (r) => ((r['samples'] as List).last as Map)['currentRss'] as num,
        ),
      ),
      'mainIsolateWorstTimerIntervalMs': runs
          .map((r) => r['maxTimerIntervalMs'] as int)
          .reduce((a, b) => a > b ? a : b),
      'afterClose': runs.first['afterClose'],
    });
  }
  final baseline = read('results/hardening_baseline.json') as Map;
  final changed = <String>[], missing = <String>[];
  final root = Directory.current.parent.parent;
  for (final entry in (baseline['files'] as Map).entries) {
    final file = File('${root.path}/${entry.key}');
    if (!file.existsSync()) {
      missing.add(entry.key as String);
      continue;
    }
    if (sha256.convert(file.readAsBytesSync()).toString() != entry.value)
      changed.add(entry.key as String);
  }
  final native = read('results/hardening_native.json'),
      keys = read('results/hardening_keys.json');
  final summary = {
    'date': DateTime.now().toUtc().toIso8601String(),
    'syntheticOnly': true,
    'native': {'passed': native['passed'], 'failed': native['failed']},
    'keys': {'passed': keys['passed'], 'failed': keys['failed']},
    'contracts': tests,
    'ownerQueue': bench['queueTest'],
    'benchmarkMedians': benchmarkSummary,
    'sourceIntegrity': {
      'baselineOrigin': baseline['baselineOrigin'],
      'checked': (baseline['files'] as Map).length,
      'changed': changed,
      'missing': missing,
      'profilesNotOpenedOrChecksummed': true,
    },
    'analyzers': {
      for (final name in ['hardening_analyze', 'hardening_plugin_analyze'])
        name: File(
          'results/$name.txt',
        ).readAsStringSync().contains('No issues found'),
    },
    'notPerformed': [
      'Android emulator or physical device (user deferred)',
      'Physical disk exhaustion or actual failing hardware',
      'Real power-cut durability',
      'Production integration, migration or installation',
      'Full application test rerun (unchanged app; targeted regressions run)',
    ],
    'readyForProduction': false,
    'stage2bStarted': false,
  };
  File(
    'results/hardening_summary.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
  if (native['failed'] != 0 ||
      keys['failed'] != 0 ||
      changed.isNotEmpty ||
      missing.isNotEmpty ||
      tests.values.cast<Map>().any((r) => r['success'] != true))
    exitCode = 1;
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(summary));
}
