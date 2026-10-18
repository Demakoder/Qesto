// Test/benchmark input construction through existing Synoball models only.
import 'dart:convert';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import '../storage_spike.dart';
import 'contract.dart';

const syntheticPartition = Partition(
  'synthetic-workspace',
  'synthetic-lineage',
);
FinancialSnapshot syntheticV7(int count) => FinancialSnapshot(
  jsonEncode({
    'schemaVersion': 7,
    'synoball': jsonDecode(syntheticSnapshot(count)),
  }),
);

FinancialSnapshot editSyntheticNote(FinancialSnapshot snapshot, String note) {
  final root = jsonDecode(snapshot.json) as Map<String, dynamic>;
  final state = SynoballState.fromJson(
    root['synoball'] as Map<String, dynamic>,
  );
  // Existing immutable financial model; no alternative classification/reconcile.
  final transactions = state.transactions.toList();
  transactions[0] = transactions[0].copyWith(userNote: note);
  final json = state.toJson();
  json['transactions'] = transactions.map((t) => t.toJson()).toList();
  root['synoball'] = SynoballState.fromJson(json).toJson();
  return FinancialSnapshot(jsonEncode(root));
}

Mutation syntheticMutation(
  FinancialSnapshot input, {
  String id = 'command-1',
  int expected = 0,
  String note = 'synthetic edit',
  List<String> dependencies = const [],
}) => Mutation(
  id: id,
  partition: syntheticPartition,
  expectedRevision: expected,
  snapshot: editSyntheticNote(input, note),
  intentJson: jsonEncode({'kind': 'set-user-note', 'note': note}),
  dependencies: dependencies,
);
