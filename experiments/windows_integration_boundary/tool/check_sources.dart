import 'dart:convert';
import 'dart:io';
import '../../synthetic_sync_backend/tool/source_evidence.dart' as source;

void main() {
  source.main(['verify']);
  final result =
      jsonDecode(File('results/source_check.json').readAsStringSync())
          as Map<String, dynamic>;
  const allowed = {
    'apps/qesto_app/lib/features/budget/state/budget_controller.dart',
    'apps/qesto_app/lib/data/mutations/transaction_note_boundary.dart',
    'apps/qesto_app/lib/features/budget/services/transaction_note_preparation.dart',
    'apps/qesto_app/lib/features/transaction_import/services/sber_transaction_projection.dart',
  };
  final changed = (result['changed'] as List).cast<String>().toSet();
  final outside = changed.difference(allowed);
  result['allowed_boundary_files'] = allowed.toList();
  result['unexpected_changes'] = outside.toList();
  result['boundary_scope_passed'] =
      outside.isEmpty && changed.containsAll(allowed);
  File(
    'results/source_check.json',
  ).writeAsStringSync(jsonEncode(result), flush: true);
  exitCode = result['boundary_scope_passed'] == true ? 0 : 1;
  print(
    jsonEncode({
      'boundary_scope_passed': result['boundary_scope_passed'],
      'unexpected_changes': outside.toList(),
    }),
  );
}
