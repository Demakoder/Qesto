import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final root = Directory.current.absolute.path;
  final test = '${Platform.environment['LOCALAPPDATA']}/Pub/Cache/hosted/pub.dev/test-1.31.0/bin/test.dart';
  const directories = {'effects': '../durable_effects_integration', 'storage': '../storage_feasibility',
    'chunks': '../incremental_sync_performance', 'journal': '../core_effects_journal',
    'domain': '../incremental_domain_execution', 'boundary': '../windows_integration_boundary',
    'integration': '.', 'shared': '../../packages/qesto_synoball_core'};
  for (final name in args) {
    final output = Directory('$root/results/regressions/$name');
    output.createSync(recursive: true);
    if (File('${output.path}/tests.jsonl').existsSync()) throw StateError('Evidence exists: $name');
    final target = name == 'shared' ? 'test' : '$root/test/${name == 'integration' ? '' : 'regression_'}${name}_test.dart';
    final result = await Process.run(Platform.resolvedExecutable, [
      '--packages=$root/.dart_tool/package_config.json', test, target, '--reporter=json', '--concurrency=1',
    ], workingDirectory: directories[name], environment: {
      'QESTO_4G_EVIDENCE': output.path, 'QESTO_4G_BINARIES': '$root/build',
    });
    File('${output.path}/tests.jsonl').writeAsStringSync(result.stdout as String);
    File('${output.path}/stderr.txt').writeAsStringSync(result.stderr as String);
    final events = (result.stdout as String).split('\n').where((s) => s.startsWith('{')).map(jsonDecode).toList();
    stdout.writeln(jsonEncode({'suite': name, 'exit': result.exitCode,
      'errors': events.where((e) => e['type'] == 'error').map((e) => e['error']).toList(),
      'done': events.where((e) => e['type'] == 'done').toList()}));
    if (result.exitCode != 0) exitCode = result.exitCode;
  }
}
