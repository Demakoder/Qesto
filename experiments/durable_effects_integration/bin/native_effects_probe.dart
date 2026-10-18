import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:qesto_storage_spike/native_faults.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import '../lib/prepared_commit.dart';
import '../lib/storage_request.dart';

Future<void> main(List<String> args) async {
  final directory = args[0], fault = args[1];
  requireOwnedPath('$directory/source.json');
  const partition = Partition('synthetic-4f', '4f-lineage');
  final p =
      NotePreparationScope.admit(
        File('$directory/source.json').readAsStringSync(),
        workspace: partition.workspace,
        lineage: partition.lineage,
        revision: 0,
        generation: 0,
      ).prepare(
        commandId: 'native-effects',
        target: 'container-tx-0',
        note: 'native durability',
        time: DateTime.utc(2026, 10, 17),
      );
  final native = NativeFaults(
    '../storage_feasibility/build/hardening/qesto_fault_shim.dll',
  );
  var store = await SqliteContainer.open(
    directory,
    partition,
    fault: (point) {
      if (point == 'local-before-commit')
        native.arm(
          scope: fault.startsWith('checkpoint') ? 1 : 2,
          op: fault == 'fsync' ? 2 : 1,
          code: fault == 'full'
              ? 13
              : fault == 'fsync'
              ? 1034
              : 778,
          mode: fault == 'partial'
              ? 1
              : fault == 'checkpoint-kill'
              ? 2
              : 0,
        );
    },
  );
  native.attach(store.raw);
  final request = storageRequest(p, store.generation);
  Object? failure;
  var acknowledged = false;
  try {
    await store.commitEffects(request);
    acknowledged = true;
  } catch (e) {
    failure = e;
  }
  final hits = native.metric(0), reopen = store.requiresReopen;
  native.disarm();
  await store.close();
  store = await SqliteContainer.open(directory, partition);
  try {
    store.verify();
    final revision = (await store.readSnapshot()).revision;
    final checkpoint = fault == 'checkpoint';
    final expected = checkpoint ? 1 : 0;
    final code = failure is sql.SqliteException
        ? failure.extendedResultCode
        : null;
    if (hits != 1 ||
        acknowledged ||
        failure == null ||
        revision != expected ||
        (await store.readPendingCommands()).length != expected ||
        !reopen ||
        (!checkpoint &&
            code !=
                (fault == 'full'
                    ? 13
                    : fault == 'fsync'
                    ? 1034
                    : 778))) {
      throw StateError(
        'native receipt invariant: hits=$hits ack=$acknowledged rev=$revision code=$code reopen=$reopen error=${failure.runtimeType}',
      );
    }
    final receipt = checkpoint
        ? await store.resolveEffects(request)
        : await store.commitEffects(request);
    await store.verifyEffectsReceipt(receipt, request);
    if ((await store.readSnapshot()).value.json != p.snapshot.json ||
        (await store.readPendingCommands()).length != 1) {
      throw StateError('same immutable ID recovery failed');
    }
    stdout.writeln(
      jsonEncode({
        'fault': fault,
        'hits': hits,
        'sqlite_code': code,
        'error': failure.runtimeType.toString(),
        'receipt_before_reopen': acknowledged,
        'revision_before_recovery': revision,
        'verified_after_reopen': true,
        'kind': 'native VFS injection, not hardware power loss',
      }),
    );
  } finally {
    await store.close();
  }
}
