import 'dart:convert';
import 'dart:io';

void main() {
  final entries = <Map<String, Object>>[];
  for (final part in ['budget_controller.dart', 'budget_classification.dart']) {
    final path = '../../apps/qesto_app/lib/features/budget/state/$part';
    final lines = File(path).readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final match = RegExp(
        r'^  Future<.+> ([a-zA-Z]\w*)\(',
      ).firstMatch(lines[i]);
      if (match != null)
        entries.add({
          'method': match[1]!,
          'file': path.substring(6),
          'line': i + 1,
          'route': match[1] == 'setTransactionNote'
              ? 'optional staged boundary; legacy by default'
              : 'existing in-memory before onChanged save',
        });
    }
  }
  File('results/mutation-inventory.json').writeAsStringSync(
    jsonEncode({
      'entries': entries,
      'default_persistence_entry':
          'QestoAppShell._saveFinancialData → LocalQestoRepository.saveUserFinancialData',
      'repository_or_storage_changed': false,
    }),
    flush: true,
  );
  print('Inventoried ${entries.length} public asynchronous financial methods');
}
