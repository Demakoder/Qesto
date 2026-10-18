import 'dart:convert';
import 'dart:io';

double median(Iterable<num> values) {
  final v = values.map((e) => e.toDouble()).toList()..sort();
  return v.length.isOdd
      ? v[v.length ~/ 2]
      : (v[v.length ~/ 2 - 1] + v[v.length ~/ 2]) / 2;
}

void main() {
  final tests = <String, Object?>{};
  for (final name in [
    'container_tests',
    'container_legacy_contracts',
    'container_plain_contracts',
    'container_shared_parity',
    'container_app_regression',
  ]) {
    final events = File('results/$name.jsonl')
        .readAsLinesSync()
        .where((l) => l.startsWith('{'))
        .map((l) => jsonDecode(l) as Map)
        .toList();
    final done = events
        .where((e) => e['type'] == 'testDone' && e['hidden'] != true)
        .toList();
    tests[name] = {
      'passed': done
          .where((e) => e['result'] == 'success' && e['skipped'] != true)
          .length,
      'failed': done.where((e) => e['result'] != 'success').length,
      'skipped': done.where((e) => e['skipped'] == true).length,
      'success': events.lastWhere((e) => e['type'] == 'done')['success'],
    };
  }
  final bench =
      jsonDecode(File('results/container_benchmarks.json').readAsStringSync())
          as Map;
  final performance = <Object>[];
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
    performance.add({
      'count': count,
      'trials': runs.length,
      'migrationTotalMedianMs': median(initial.map((s) => s['totalMs'] as num)),
      'editSerializeMedianMs': median(
        edits.map((s) => s['serializeMs'] as num),
      ),
      'editTotalMedianMs': median(edits.map((s) => s['totalMs'] as num)),
      'editCommitCheckpointMedianMs': median(
        edits.map((s) => (s['totalMs'] as num) - (s['serializeMs'] as num)),
      ),
      'editCpuMedianMs': median(edits.map((s) => s['cpuMs'] as num)),
      'peakRssBytes': edits
          .map((s) => s['peakRssBytes'] as int)
          .reduce((a, b) => a > b ? a : b),
      'afterClose': runs.first['afterClose'],
    });
  }
  final result = {
    'date': '2026-10-11',
    'scope': 'isolated synthetic Windows x64 only',
    'tests': tests,
    'benchmarks': performance,
    'benchmarksComplete': bench['complete'],
    'sourceCheck': jsonDecode(
      File('results/container_source_check.json').readAsStringSync(),
    ),
    'wal': jsonDecode(File('results/container_wal.json').readAsStringSync()),
    'codecMigration': jsonDecode(
      File('results/container_codec_migration.json').readAsStringSync(),
    ),
    'codecEdited': jsonDecode(
      File('results/container_codec_edited.json').readAsStringSync(),
    ),
    'android': 'not run, explicitly deferred by user',
    'productionIntegrated': false,
    'nativeFaults': jsonDecode(
      File('results/container_native_faults.json').readAsStringSync(),
    ),
    'ownerRestart': jsonDecode(
      File('results/container_owner_restart.json').readAsStringSync(),
    ),
    'legacyNativePassed': File(
      'results/container_native_regression.txt',
    ).readAsLinesSync().where((l) => l.startsWith('PASS ')).length,
    'legacyKeysPassed': File(
      'results/container_key_regression.txt',
    ).readAsLinesSync().where((l) => l.startsWith('PASS ')).length,
    'analyzerClean': File(
      'results/container_analyze.txt',
    ).readAsStringSync().contains('No issues found!'),
  };
  File(
    'results/container_summary.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  print(const JsonEncoder.withIndent('  ').convert(result));
  if (tests.values.cast<Map>().any((t) => t['success'] != true) ||
      bench['complete'] != true ||
      (result['sourceCheck'] as Map)['passed'] != true ||
      result['analyzerClean'] != true ||
      result['legacyNativePassed'] != 31 ||
      result['legacyKeysPassed'] != 13)
    exitCode = 1;
}
