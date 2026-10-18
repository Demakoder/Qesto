import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final flutter =
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}/flutter_tools.snapshot';
  final r = await Process.run(Platform.resolvedExecutable, [
    flutter,
    'test',
    '--no-pub',
    '--concurrency=1',
    '--reporter=json',
    'test/storage_recovery_safety_test.dart',
    'test/user_financial_data_codec_test.dart',
    'test/synoball_core_test.dart',
    'test/shared_synoball_core_compatibility_test.dart',
    'test/synoball_safety_test.dart',
    'test/desktop_shell_test.dart',
    'test/cash_flow_calculation_service_test.dart',
    'test/empty_user_data_test.dart',
    'test/classification_test.dart',
  ], workingDirectory: '../../apps/qesto_app');
  File('results/app-regression.jsonl').writeAsStringSync(r.stdout as String);
  File(
    'results/app-regression-stderr.txt',
  ).writeAsStringSync(r.stderr as String);
  final events = (r.stdout as String)
      .split('\n')
      .where((s) => s.startsWith('{'))
      .map(jsonDecode)
      .toList();
  stdout.writeln(
    jsonEncode({
      'exit': r.exitCode,
      'errors': events.where((e) => e['type'] == 'error').toList(),
      'done': events.where((e) => e['type'] == 'done').toList(),
    }),
  );
  exitCode = r.exitCode;
}
