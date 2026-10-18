import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto_synthetic_sync/domain.dart' as server;
import 'package:qesto_synthetic_sync/protocol.dart' as wire;
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto/features/budget/services/transaction_note_preparation.dart';

void main() {
  test(
    'actual configured Qesto note semantics must be aligned before connecting 3a server',
    () {
      final before = syntheticFixture();
      final cmd = wire.NoteCommand.parse({
        'protocol_version': 1,
        'domain_version': 1,
        'workspace_id': 'synthetic-4a-gate',
        'device_id': 'synthetic-4a-device',
        'workspace_epoch': 'synthetic-4a-epoch',
        'change_id': 'semantic-gate',
        'kind': 'transaction.set_note',
        'transaction_id': 'container-tx-0',
        'base_revision': '0',
        'note': 'Same synthetic note',
      });
      final time = DateTime.utc(2026, 10, 12);
      final app = prepareTransactionNote(
        before,
        cmd.target,
        cmd.note,
        clock: () => time,
        ids: SyntheticIds(cmd.changeId),
      );
      final remote = server.applyNote(
        before.synoballState!,
        cmd,
        'ent-$syntheticUser',
        time,
      );
      final a = app.data.synoballState!.transactions.first.toJson(),
          b = remote.transactions.first.toJson();
      final different = {
        for (final k in {...a.keys, ...b.keys})
          if (jsonEncode(a[k]) != jsonEncode(b[k])) k,
      }.toList();
      expect(different, contains('tags'));
      expect(a['amount'], b['amount']);
      expect(a['id'], b['id']);
      expect(a['userNote'], b['userNote']);
      File('results/server-semantics-gate.json').writeAsStringSync(
        jsonEncode({
          'synthetic_only': true,
          'expected_blocker_confirmed': true,
          'same_note_and_money': true,
          'different_canonical_fields': different,
          'application_entity_id': 'ent-$syntheticUser',
          'required_next_step':
              'Use existing app bridge and configured policy on both sides; align owner/entity mapping before test UI sync',
          'network_used': false,
        }),
        flush: true,
      );
    },
  );
}
