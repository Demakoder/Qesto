import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final runs = <Object>[];
  for (final count in [1000, 10000]) {
    final r = await Process.run(
      File('build/benchmark/bundle/bin/benchmark.exe').absolute.path,
      ['$count'],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0) throw StateError('${r.stderr}');
    runs.add(jsonDecode((r.stdout as String).trim()));
    File('results/benchmarks.json').writeAsStringSync(
      jsonEncode({
        'runs': runs,
        'complete': runs.length == 2,
        'synthetic_only': true,
        'cpu_scope':
            'client/coordinator process, excludes PostgreSQL and server processes',
      }),
      flush: true,
    );
    print('Verified $count synthetic transactions');
  }
}
