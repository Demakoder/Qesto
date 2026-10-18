import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final suite = args.isEmpty ? 'delta' : args.first;
  final suffix = suite == 'benchmark' ? '-${args[1]}-${args[2]}' : '';
  final flutter =
      File(Platform.resolvedExecutable).parent.parent.parent.path +
      '/flutter_tools.snapshot';
  final result = await Process.run(
    Platform.resolvedExecutable,
    [
      flutter,
      'test',
      'test/${suite}_test.dart',
      if (suite == 'benchmark') '--enable-vmservice',
      '--no-pub',
      '--concurrency=1',
      '--reporter=json',
    ],
    workingDirectory: 'flutter_runner',
    environment: suite == 'benchmark'
        ? {'QESTO_4F_MODE': args[1], 'QESTO_4F_COUNT': args[2]}
        : null,
  );
  File(
    'results/flutter-$suite$suffix.jsonl',
  ).writeAsStringSync(result.stdout as String);
  File(
    'results/flutter-$suite$suffix-stderr.txt',
  ).writeAsStringSync(result.stderr as String);
  final events = (result.stdout as String)
      .split('\n')
      .where((s) => s.startsWith('{'))
      .map(jsonDecode)
      .toList();
  stdout.writeln(
    jsonEncode({
      'exit': result.exitCode,
      'errors': events
          .where((e) => e['type'] == 'error')
          .map((e) => e['error'])
          .toList(),
      'done': events.where((e) => e['type'] == 'done').toList(),
    }),
  );
  if (result.exitCode != 0) stderr.write(result.stderr);
  exitCode = result.exitCode;
}
