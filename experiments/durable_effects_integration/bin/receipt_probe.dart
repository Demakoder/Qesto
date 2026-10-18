import 'dart:io';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import '../lib/prepared_commit.dart';
import '../lib/storage_request.dart';

Future<void> main(List<String> args) async {
  final dir = args[0], stage = args[1];
  requireOwnedPath('$dir/source.json');
  if (stage == 'before-prepare') exit(86);
  final scope = NotePreparationScope.admit(
    File('$dir/source.json').readAsStringSync(),
    workspace: 'synthetic-4f',
    lineage: '4f-lineage',
    revision: 0,
    generation: 0,
  );
  final p = scope.prepare(
    commandId: 'process-one',
    target: 'container-tx-0',
    note: 'crash-note',
    time: DateTime.utc(2026, 10, 16),
  );
  if (stage == 'after-prepare') exit(86);
  final store = await SqliteContainer.open(
    dir,
    const Partition('synthetic-4f', '4f-lineage'),
    fault: (s) {
      if (s == stage) exit(86);
    },
  );
  try {
    await store.commitEffects(storageRequest(p, store.generation));
    if (stage == 'before-owner-promotion') exit(86);
  } finally {
    await store.close();
  }
}
