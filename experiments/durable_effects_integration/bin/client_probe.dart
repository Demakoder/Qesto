import 'dart:convert';
import 'dart:io';
import 'package:qesto_encrypted_sync_experiment/client_identity.dart';
import 'package:qesto_windows_boundary_experiment/windows_note_boundary.dart';
import 'package:qesto_windows_boundary_experiment/note_sync_binding.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_coordinator_domain.dart';
import '../lib/windows_driver.dart';

Future<void> main(List<String> args) async {
  try {
    final raw = jsonDecode(File(args[0]).readAsStringSync());
    final identity = ClientIdentity.parse(raw, raw['index'] as int),
        p = identity.principal;
    final directory = args[1],
        meta = jsonDecode(
          File('$directory/sync-binding.json').readAsStringSync(),
        );
    final owner = await WindowsNoteBoundary.open(
      SyntheticWindowsProfile(directory, p.workspace, p.device, identity.epoch),
      probe: args[3] == 'kill-worker'
          ? BoundaryProbe.afterCommitGate
          : BoundaryProbe.none,
      effectsDriver: const EffectsDriverFactory(),
      synchronization: NoteSyncBinding(
        principal: p,
        endpoint: Uri.parse(args[2]),
        domain: QestoCoordinatorDomain(
          p.user,
          p.workspace,
          identity.epoch,
          meta['policy_digest'],
          (meta['devices'] as List).cast<String>(),
        ),
      ),
    );
    try {
      if (args[3] == 'sync') {
        await owner.synchronize();
      } else if (args[3] == 'edit') {
        await owner.commitDeltaForExperiment(
          TransactionNoteIntent(
            commandId: 'probe-note',
            transactionId: 'container-tx-0',
            note: 'Native probe note',
            expectedRevision: (await owner.load()).revision,
          ),
        );
      } else if (args[3] == 'kill-worker') {
        final gate = owner.stages.first;
        final pending = owner.commitDeltaForExperiment(
          TransactionNoteIntent(
            commandId: 'kill-before-ui',
            transactionId: 'container-tx-0',
            note: 'committed worker killed',
            expectedRevision: (await owner.load()).revision,
          ),
        );
        final outcome = pending.then(
          (_) => false,
          onError: (Object e) => e is NoteBoundaryFailure && e.outcomeUnknown,
        );
        await gate;
        owner.killWorkerForTest();
        if (!await outcome)
          throw StateError('Expected unknown durable outcome');
        stdout.writeln('{"unknown":true,"hot_reopen":false}');
      } else {
        throw StateError('Unsupported probe action');
      }
    } finally {
      await owner.close();
    }
  } catch (e) {
    stdout.writeln(
      jsonEncode({
        'error': e is NoteBoundaryFailure ? e.code : e.runtimeType.toString(),
      }),
    );
    exitCode = 2;
  }
}
