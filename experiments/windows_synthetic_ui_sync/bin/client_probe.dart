import 'dart:convert';
import 'dart:io';
import 'package:qesto_encrypted_sync_experiment/client_identity.dart';
import 'package:qesto_windows_boundary_experiment/windows_note_boundary.dart';
import 'package:qesto_windows_boundary_experiment/note_sync_binding.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_coordinator_domain.dart';

Future<void> main(List<String> args) async {
  try {
    final json = jsonDecode(File(args[0]).readAsStringSync());
    final identity = ClientIdentity.parse(json, json['index'] as int),
        p = identity.principal;
    final directory = args[1],
        meta = jsonDecode(
          File('$directory/sync-binding.json').readAsStringSync(),
        );
    final owner = await WindowsNoteBoundary.open(
      SyntheticWindowsProfile(directory, p.workspace, p.device, identity.epoch),
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
      switch (args[3]) {
        case 'sync':
          await owner.synchronize();
        case 'verify':
          final state = await owner.load(), info = await owner.inspectForTest();
          print(
            jsonEncode({
              'revision': state.revision,
              'checkpoint': info['checkpoint'],
              'pending': (await owner.pending()).length,
              'snapshot': jsonDecode(
                const UserFinancialDataCodec().encode(state.data),
              ),
            }),
          );
        case 'edit':
          final state = await owner.load();
          await owner.commitNote(
            TransactionNoteIntent(
              commandId: 'probe-note',
              transactionId: 'container-tx-0',
              note: 'Native probe note',
              expectedRevision: state.revision,
            ),
          );
        default:
          throw StateError('Unknown synthetic action');
      }
    } finally {
      await owner.close();
    }
  } catch (e) {
    print(
      jsonEncode({
        'error': e is NoteBoundaryFailure ? e.code : '${e.runtimeType}',
      }),
    );
    exitCode = 2;
  }
}
