import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final root = Directory.current.absolute.path;
  final flutter = '${File(Platform.resolvedExecutable).parent.parent.parent.path}/flutter_tools.snapshot';
  for (final name in args) {
    final out = Directory('$root/results/regressions/flutter-$name')..createSync(recursive: true);
    if (File('${out.path}/tests.jsonl').existsSync()) throw StateError('Evidence exists: $name');
    final r = await Process.run(Platform.resolvedExecutable, [flutter, 'test',
      '$root/flutter_runner/test/regression_${name}_test.dart', '--no-pub', '--concurrency=1', '--reporter=json'],
      workingDirectory: '../durable_effects_integration/flutter_runner',
      environment: {'QESTO_4G_EVIDENCE': out.path});
    File('${out.path}/tests.jsonl').writeAsStringSync(r.stdout as String);
    File('${out.path}/stderr.txt').writeAsStringSync(r.stderr as String);
    final events = (r.stdout as String).split('\n').where((s) => s.startsWith('{')).map(jsonDecode).toList();
    stdout.writeln(jsonEncode({'suite': name, 'exit': r.exitCode,
      'errors': events.where((e) => e['type'] == 'error').map((e) => e['error']).toList(),
      'done': events.where((e) => e['type'] == 'done').toList()}));
    if (r.exitCode != 0) exitCode = r.exitCode;
  }
}
