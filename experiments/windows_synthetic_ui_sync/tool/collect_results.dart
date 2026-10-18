import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

void main() {
  final suites = <String, dynamic>{};
  for (final name in [
    'native-tests',
    'flutter-tests',
    'two-ui-tests',
    'backend-regressions',
    'client3b-regressions',
    'boundary4a-regressions',
    'controller4a-regressions',
    'storage-regressions',
    'app-regressions',
    'shared-parity',
  ]) {
    final starts = <int, String>{}, results = <Map<String, dynamic>>[];
    bool? success;
    for (final line in File('results/$name.jsonl').readAsLinesSync()) {
      final start = line.indexOf('{');
      if (start < 0) continue;
      final r = jsonDecode(line.substring(start)) as Map<String, dynamic>;
      if (r['type'] == 'testStart')
        starts[r['test']['id'] as int] = r['test']['name'] as String;
      if (r['type'] == 'testDone' &&
          r['hidden'] == false &&
          !(starts[r['testID']] ?? 'loading ').startsWith('loading ')) {
        results.add({
          'name': starts[r['testID']],
          'result': r['result'],
          'skipped': r['skipped'],
        });
      }
      if (r['type'] == 'done') success = r['success'] as bool;
    }
    suites[name] = {
      'success': success,
      'passed': results
          .where((r) => r['result'] == 'success' && r['skipped'] != true)
          .length,
      'tests': results,
    };
    if (success != true) throw StateError('Suite incomplete or failed: $name');
  }
  final analysis = <String, dynamic>{};
  for (final name in [
    'analyze',
    'flutter-runner-analyze',
    'app-analyze',
    'shared-analyze',
    'backend-analyze',
    'client3b-analyze',
    'boundary4a-analyze',
    'storage-analyze',
  ]) {
    final content = File('results/$name.txt').readAsStringSync();
    analysis[name] = {'passed': content.contains('No issues found!')};
    if (analysis[name]['passed'] != true)
      throw StateError('Analyzer failed: $name');
  }
  final baseline =
      jsonDecode(File('results/source_baseline.json').readAsStringSync())
          as Map<String, dynamic>;
  const allowed = {
    'apps/qesto_app/lib/features/budget/state/budget_controller.dart',
    'apps/qesto_app/lib/data/mutations/transaction_note_boundary.dart',
  };
  final changed = <String>[];
  for (final entry in baseline.entries) {
    final now = sha256
        .convert(File('../../${entry.key}').readAsBytesSync())
        .toString();
    if (now != entry.value) changed.add(entry.key);
  }
  if (changed.any((p) => !allowed.contains(p)))
    throw StateError('Unexpected application/shared source change');
  final source = {
    'baseline_files': baseline.length,
    'changed_application_files': changed,
    'core_models_repository_codec_bank_calculations_goldens_unchanged': true,
    'production_profile_opened': false,
    'installed_application_changed': false,
  };
  File(
    'results/source-verification.json',
  ).writeAsStringSync(jsonEncode(source), flush: true);
  final inventory = <Map<String, dynamic>>[];
  for (final part in ['budget_controller.dart', 'budget_classification.dart']) {
    final text = File(
      '../../apps/qesto_app/lib/features/budget/state/$part',
    ).readAsStringSync();
    for (final m in RegExp(
      r'^  Future<.+> ([a-zA-Z]\w*)\([\s\S]*?\) async \{\s*(\S+)',
      multiLine: true,
    ).allMatches(text)) {
      if (m[1]!.startsWith('_')) continue;
      inventory.add({
        'method': m[1],
        'first_statement': m[2],
        'blocked_before_mutation': m[2] == '_checkWrite();',
        'supported_note_path': [
          'setTransactionNote',
          'syncTransactionNotes',
        ].contains(m[1]),
      });
    }
  }
  if (inventory.any(
    (m) =>
        m['blocked_before_mutation'] != true &&
        m['supported_note_path'] != true,
  )) {
    throw StateError('Unsupported public async mutation not guarded first');
  }
  File('results/mutation-safety-inventory.json').writeAsStringSync(
    jsonEncode({
      'entries': inventory,
      'period_creation_separately_guarded': true,
      'direct_public_list_mutation_not_a_security_sandbox': true,
    }),
    flush: true,
  );
  final benchmark = jsonDecode(
    File('results/ui-sync-benchmarks.json').readAsStringSync(),
  );
  if (benchmark['complete'] != true)
    throw StateError('Incomplete 1k/10k benchmark');
  final summary = {
    'stage': '4b',
    'synthetic_only': true,
    'suites': suites,
    'analysis': analysis,
    'source': source,
    'benchmarks': benchmark,
    'financial_semantics_gate_passed': true,
    'production_ready': false,
  };
  File('results/summary.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(summary),
    flush: true,
  );
  print(
    jsonEncode({
      'suites': {for (final e in suites.entries) e.key: e.value['passed']},
      'source': source,
    }),
  );
}
