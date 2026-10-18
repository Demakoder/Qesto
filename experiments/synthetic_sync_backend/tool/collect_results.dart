import 'dart:convert';
import 'dart:io';
import 'package:qesto_synthetic_sync/config.dart';

Map<String, dynamic> suite(String path) {
  final events = File(path)
      .readAsLinesSync()
      .where((v) => v.trim().startsWith('{'))
      .map((l) => jsonDecode(l) as Map)
      .toList();
  final done = events
      .where((e) => e['type'] == 'testDone' && e['hidden'] != true)
      .toList();
  return {
    'path': path,
    'passed': done
        .where((e) => e['result'] == 'success' && e['skipped'] != true)
        .length,
    'failed': done.where((e) => e['result'] != 'success').length,
    'skipped': done.where((e) => e['skipped'] == true).length,
    'success': events.any((e) => e['type'] == 'done' && e['success'] == true),
    'elapsed_ms': events.last['time'],
  };
}

Future<void> main() async {
  final c = await TestConfig.read('.runtime/cluster.json').connect(admin: true);
  Map<String, dynamic> database;
  try {
    database = (await c.execute(
      "SELECT version(), current_setting('listen_addresses') AS listen_addresses, current_setting('fsync') AS fsync, current_setting('synchronous_commit') AS synchronous_commit",
    )).single.toColumnMap();
  } finally {
    await c.close();
  }
  final results = {
    'stage': '3a',
    'synthetic_only': true,
    'captured_at': DateTime.now().toUtc().toIso8601String(),
    'dart': Platform.version,
    'database': database,
    'suites': [
      for (final name in [
        'tests',
        'shared-core-tests',
        'storage-regression-tests',
        'app-regression-tests',
      ])
        suite('results/$name.jsonl'),
    ],
    'source_check': jsonDecode(
      File('results/source_check.json').readAsStringSync(),
    ),
    'analyzer': File('results/analyze.txt').readAsStringSync().trim(),
    'not_proven': [
      'Production auth/security/TLS',
      'Power loss/hardware faults',
      'Production encrypted client integration',
      'Android runtime',
      'Large dataset performance',
    ],
  };
  File(
    'results/summary.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
  print(const JsonEncoder.withIndent('  ').convert(results));
  if ((results['suites'] as List).any((s) => s['success'] != true) ||
      (results['source_check'] as Map)['passed'] != true)
    exitCode = 1;
}
