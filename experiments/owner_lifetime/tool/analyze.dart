import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  const targets = <String, (String, List<String>)>{
    'stage4g': ('.', ['lib', 'bin', 'test', 'tool']),
    'effects': ('../durable_effects_integration', ['lib', 'test']),
    'storage': ('../storage_feasibility', ['lib/container', 'lib/synthetic_trace.dart']),
    'boundary': ('../windows_integration_boundary', ['lib']),
    'coordinator': ('../encrypted_client_sync', ['lib/coordinator.dart']),
    'executor': ('../windows_synthetic_ui_sync', ['lib/qesto_note_executor.dart']),
    'core': ('../../packages/qesto_synoball_core', ['lib']),
    'app-seams': ('../../apps/qesto_app', ['lib/data/mutations/transaction_note_boundary.dart',
      'lib/data/persistence/user_financial_data_codec.dart',
      'lib/features/budget/state/budget_controller.dart']),
  };
  final outcomes = <Object>[];
  Directory('results/analyzer').createSync(recursive: true);
  for (final target in targets.entries) {
    final r = await Process.run(Platform.resolvedExecutable, ['analyze', ...target.value.$2],
      workingDirectory: target.value.$1);
    File('results/analyzer/${target.key}.txt').writeAsStringSync('${r.stdout}\n${r.stderr}');
    outcomes.add({'target': target.key, 'exit': r.exitCode});
    stdout.writeln('${target.key}: ${r.exitCode}');
    if (r.exitCode != 0) exitCode = r.exitCode;
  }
  File('results/analyzer/summary.json').writeAsStringSync(jsonEncode(outcomes));
}
