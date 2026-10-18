import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final exe = File(
    'build/container_probe/bundle/bin/container_probe.exe',
  ).absolute.path;
  final runs = <Object>[];
  for (final count in [1000, 10000, 50000]) {
    for (var trial = 1; trial <= 3; trial++) {
      final result = await Process.run(exe, ['bench', '$count']);
      if (result.exitCode != 0) throw StateError('${result.stderr}');
      runs.add({
        ...jsonDecode((result.stdout as String).trim()) as Map<String, dynamic>,
        'trial': trial,
      });
      File('results/container_benchmarks.json').writeAsStringSync(
        jsonEncode({'runs': runs, 'complete': runs.length == 9}),
      );
      print('Verified count=$count trial=$trial');
    }
  }
}
