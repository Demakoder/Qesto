import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final name = args.isEmpty ? 'coverage' : args.first;
  Directory('results').createSync(recursive: true);
  final r = await Process.run(Platform.resolvedExecutable, [
    '--packages=.dart_tool/package_config.json',
    '${Platform.environment['LOCALAPPDATA']}/Pub/Cache/hosted/pub.dev/test-1.31.0/bin/test.dart',
    name == 'all' ? 'test' : 'test/${name}_test.dart',
    '--reporter=json',
    '--concurrency=1',
  ]);
  File('results/$name-tests.jsonl').writeAsStringSync(r.stdout as String);
  File('results/$name-tests-stderr.txt').writeAsStringSync(r.stderr as String);
  final events = (r.stdout as String)
      .split('\n')
      .where((s) => s.startsWith('{'))
      .map(jsonDecode)
      .toList();
  for (final e in events.where((e) => e['type'] == 'error'))
    stdout.writeln(e['error']);
  stdout.writeln(
    jsonEncode({
      'suite': name,
      'exit': r.exitCode,
      'done': events.where((e) => e['type'] == 'done').toList(),
    }),
  );
  exitCode = r.exitCode;
}
