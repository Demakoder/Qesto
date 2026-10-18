import 'dart:convert';
import 'dart:io';
import 'package:qesto_windows_boundary_experiment/windows_note_boundary.dart';
import 'package:qesto/data/mutations/transaction_note_boundary.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';

Future<void> main(List<String> args) async {
  try {
    final profile = SyntheticWindowsProfile(args[1], args[2], args[3], args[4]);
    final owner = await WindowsNoteBoundary.open(profile);
    try {
      switch (args[0]) {
        case 'edit':
          await owner.commitNote(
            const TransactionNoteIntent(
              commandId: 'native-one',
              transactionId: 'container-tx-0',
              note: 'Native durable note',
              expectedRevision: 0,
            ),
          );
        case 'verify':
          final s = await owner.load();
          print(
            jsonEncode({
              'revision': s.revision,
              'snapshot': jsonDecode(
                const UserFinancialDataCodec().encode(s.data),
              ),
              'pending': (await owner.pending()).length,
            }),
          );
        case 'kill-worker':
          owner.killWorkerForTest();
          await Future<void>.delayed(const Duration(milliseconds: 50));
          try {
            await owner.load();
            throw StateError('Dead worker accepted work');
          } on NoteBoundaryFailure {
            print('{"fail_closed":true,"hot_restart":false}');
          }
        default:
          throw StateError('Unknown mode');
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
