import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final suites = <String, (String, List<String>)>{
    'storage': (
      '../storage_feasibility',
      [
        'test/container_contract_test.dart',
        'test/container_process_test.dart',
        'test/contract_test.dart',
        'test/hardening_policy_test.dart',
      ],
    ),
    'chunks': (
      '../incremental_sync_performance',
      ['test/chunk_storage_test.dart', 'test/native_chunk_fault_test.dart'],
    ),
    'shared': ('../../packages/qesto_synoball_core', ['test']),
    'journal': ('../core_effects_journal', ['test']),
    'domain': (
      '../incremental_domain_execution',
      [
        'test/domain_owner_test.dart',
        'test/bounded_executor_test.dart',
        'test/streaming_digest_test.dart',
      ],
    ),
    'boundary': (
      '../windows_integration_boundary',
      ['test/boundary_test.dart'],
    ),
  };
  final test =
      '${Platform.environment['LOCALAPPDATA']}/Pub/Cache/hosted/pub.dev/test-1.31.0/bin/test.dart';
  for (final name in args) {
    final suite = suites[name]!;
    final r = await Process.run(Platform.resolvedExecutable, [
      '--packages=.dart_tool/package_config.json',
      test,
      ...suite.$2,
      '--reporter=json',
      '--concurrency=1',
    ], workingDirectory: suite.$1);
    File(
      'results/regression-$name.jsonl',
    ).writeAsStringSync(r.stdout as String);
    File(
      'results/regression-$name-stderr.txt',
    ).writeAsStringSync(r.stderr as String);
    final events = (r.stdout as String)
        .split('\n')
        .where((s) => s.startsWith('{'))
        .map(jsonDecode)
        .toList();
    stdout.writeln(
      jsonEncode({
        'suite': name,
        'exit': r.exitCode,
        'errors': events
            .where((e) => e['type'] == 'error')
            .map((e) => e['error'])
            .toList(),
        'done': events.where((e) => e['type'] == 'done').toList(),
      }),
    );
    if (r.exitCode != 0) exitCode = r.exitCode;
  }
}
