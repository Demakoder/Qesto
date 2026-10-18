import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final commands = <String, (String, List<String>)>{
    'experiment': ('.', ['analyze', 'lib', 'bin', 'test', 'tool']),
    'shared-core': ('../../packages/qesto_synoball_core', ['analyze']),
    'container': ('../storage_feasibility', ['analyze', 'lib/container']),
    'boundary': ('../windows_integration_boundary', ['analyze', 'lib']),
    'coordinator': (
      '../encrypted_client_sync',
      ['analyze', 'lib/coordinator.dart'],
    ),
    'flutter-runner': ('flutter_runner', ['analyze', 'test']),
    'app-seams': (
      '../../apps/qesto_app',
      [
        'analyze',
        'lib/data/mutations/transaction_note_boundary.dart',
        'lib/data/persistence/user_financial_data_codec.dart',
        'lib/features/budget/state/budget_controller.dart',
      ],
    ),
  };
  final results = <Object>[];
  for (final e in commands.entries) {
    final result = await Process.run(
      Platform.resolvedExecutable,
      e.value.$2,
      workingDirectory: e.value.$1,
    );
    File(
      'results/analyze-${e.key}.txt',
    ).writeAsStringSync('${result.stdout}\n${result.stderr}');
    results.add({'target': e.key, 'exit': result.exitCode});
    stdout.writeln('${e.key}: ${result.exitCode}');
    if (result.exitCode != 0) exitCode = result.exitCode;
  }
  File('results/analyze.json').writeAsStringSync(jsonEncode(results));
}
