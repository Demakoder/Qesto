/// CLI for synthetic Windows integration. Each invocation owns one encrypted
/// database for its entire lifetime. No production repository or file client.
import 'dart:convert';
import 'dart:io';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_storage_spike/container/sqlite_container.dart';
import 'package:qesto_storage_spike/container/writer.dart';
import 'package:qesto_storage_spike/storage_spike.dart';
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'package:qesto_encrypted_sync_experiment/bootstrap.dart';
import 'package:qesto_encrypted_sync_experiment/client_identity.dart';
import 'package:qesto_encrypted_sync_experiment/coordinator.dart';
import 'package:qesto_encrypted_sync_experiment/transport.dart';

Future<void> main(List<String> args) async {
  try {
    await run(args);
  } catch (e) {
    // Never dump config, tokens, plaintext profile or arbitrary exception text.
    print(
      jsonEncode({
        'error': e is ContractViolation
            ? e.code
            : e is w.ApiError
            ? e.code
            : '${e.runtimeType}',
      }),
    );
    exitCode = 2;
  }
}

Future<void> run(List<String> args) async {
  final identity = ClientIdentity.parse(
        jsonDecode(File(args[0]).readAsStringSync()),
        int.parse(args[1]),
      ),
      p = identity.principal;
  final base = Uri.parse(args[2]), directory = args[3], action = args[4];
  requireOwnedPath('$directory/container.lock');
  final transport = LoopbackTransport(base, p);
  if (action == 'bootstrap') {
    final fixture = FinancialSnapshot(File(args[5]).readAsStringSync());
    await bootstrap(
      directory,
      fixture,
      p,
      await transport.request('GET', 'snapshot'),
    );
    print(jsonEncode({'bootstrapped': true}));
    return;
  }
  // Test epoch is public metadata in the synthetic harness configuration.
  final partition = Partition(p.workspace, identity.epoch);
  final fault = Platform.environment['QESTO_3B_FAULT'];
  final SyncTransactionContainer store;
  if (fault != null) {
    // Fault-injection executable path only: full PROCESS exit, not Isolate.kill.
    store = await SqliteContainer.open(
      directory,
      partition,
      fault: (stage) {
        if (stage == fault) exit(86);
      },
    );
  } else {
    store = await ContainerWriter.open(directory, partition);
  }
  try {
    final c = Coordinator(store, partition, p, transport.request);
    switch (action) {
      case 'edit':
        final r = await c.edit(args[5], args[6], args[7]);
        if (fault == 'after-local-commit') exit(86);
        print(
          jsonEncode({
            'local_ack': r.locallyDurable,
            'revision': r.revision,
            'state': r.state.name,
            'checkpoint': await store.readCheckpoint(),
          }),
        );
      case 'push':
        await c.push();
        print(
          jsonEncode({
            'pushed': true,
            'checkpoint': await store.readCheckpoint(),
          }),
        );
      case 'pull':
        await c.pull();
        print(jsonEncode({'pulled': true}));
      case 'sync':
        await c.sync();
        final remaining = await store.readPendingCommands();
        print(
          jsonEncode({
            'outcome': remaining.isEmpty
                ? 'synchronized'
                : 'requires_attention',
            'unresolved_commands': remaining.length,
          }),
        );
      case 'verify':
        await c.context();
        final s = await store.readSnapshot(),
            pending = await store.readPendingCommands();
        print(
          jsonEncode({
            'revision': s.revision,
            'checkpoint': await store.readCheckpoint(),
            'snapshot': jsonDecode(s.value.json),
            'pending': [
              for (final p in pending)
                {
                  'id': p.receipt.id,
                  'state': p.receipt.state.name,
                  'intent': commandBody(p),
                  'receipt': p.receipt.serverReceipt,
                },
            ],
          }),
        );
      default:
        throw const ContractViolation('unknown-action');
    }
  } finally {
    await store.close();
  }
}

Map<String, dynamic> commandBody(PendingCommand p) =>
    Coordinator.command(p).body;
