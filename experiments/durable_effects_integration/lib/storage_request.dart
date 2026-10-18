import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'prepared_commit.dart';

EffectsCommitRequest storageRequest(
  PreparedFinancialCommit p,
  int generation, {
  String intentJson = '{}',
}) => EffectsCommitRequest(
  mutation: Mutation(
    id: p.binding.commandId,
    partition: Partition(p.binding.workspace, p.binding.lineage),
    expectedRevision: p.binding.baseRevision,
    snapshot: p.snapshot,
    intentJson: intentJson,
  ),
  effectsJson: p.effectsJson,
  binding: p.bindingJson,
  storageGeneration: generation,
);
