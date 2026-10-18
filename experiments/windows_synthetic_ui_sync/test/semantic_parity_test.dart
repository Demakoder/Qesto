import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/services/transaction_note_preparation.dart';
import 'package:qesto_synthetic_sync/domain.dart' show CommandIds;
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'package:qesto_windows_boundary_experiment/synthetic_fixture.dart';
import 'package:qesto_windows_ui_sync_experiment/qesto_note_executor.dart';

w.NoteCommand command(String target, String note, String id) =>
    w.NoteCommand.parse({
      'protocol_version': 1,
      'domain_version': 1,
      'workspace_id': 'synthetic-4a-parity',
      'device_id': 'synthetic-4a-a',
      'workspace_epoch': 'synthetic-4a-epoch',
      'change_id': id,
      'kind': 'transaction.set_note',
      'transaction_id': target,
      'base_revision': '0',
      'note': note,
    });
void main() {
  const executor = QestoNoteExecutor(), codec = UserFinancialDataCodec();
  test(
    'STOP GATE: complete configured application/server results including tags/audit/events are identical',
    () {
      final initial = syntheticFixture(), time = DateTime.utc(2026, 10, 13);
      var before = initial;
      for (final c in [
        command('container-tx-0', 'Точная заметка 13 ₽', 'first'),
        command('container-tx-1', 'Configured merchant rule', 'second'),
        command('container-tx-0', '', 'clear'),
      ]) {
        final local = prepareTransactionNote(
          before,
          c.target,
          c.note,
          clock: () => time,
          ids: CommandIds(c.changeId),
        );
        final server = executor.execute(
          codec.encode(before),
          c,
          syntheticUser,
          time,
        );
        expect(jsonDecode(server.stored), jsonDecode(codec.encode(local.data)));
        expect(server.core.toJson(), local.core.state.toJson());
        expect(server.core.transactions.first.amount.minorUnits, 486122);
        expect(server.core.transactions[1].amount.currency, 'USD');
        expect(server.core.transactions.last.status.name, 'deleted');
        expect(
          server.core.transactions.first.userCategoryOverride,
          'fitness-custom',
        );
        expect(
          server.core.transactions.first.tags,
          contains('user-field:note'),
        );
        expect(
          server.core.transactions[1].tags,
          contains('user-category-rule:synthetic-rule'),
        );
        before = local.data;
      }
      File('results/semantic-parity.json').writeAsStringSync(
        jsonEncode({
          'passed': true,
          'synthetic_only': true,
          'tags_excluded': false,
          'audit_events_compared': true,
          'canonical_legacy_full_profile_compared': true,
          'clock_ids_controlled': true,
          'user': syntheticUser,
          'entity': executor.entityFor(syntheticUser),
          'network_used': false,
        }),
        flush: true,
      );
    },
  );
  test('synthetic owner/entity binding and trash fail closed', () {
    final data = syntheticFixture(),
        encoded = codec.encode(data),
        time = DateTime.utc(2026, 10, 13);
    for (final owner in ['local-user', 'wrong-user', 'synthetic-4a-other']) {
      expect(
        () => executor.execute(
          encoded,
          command('container-tx-0', 'x', 'bad'),
          owner,
          time,
        ),
        throwsA(isA<w.ApiError>()),
      );
    }
    expect(
      () => executor.execute(
        encoded,
        command('container-tx-2', 'cannot edit trash', 'trash'),
        syntheticUser,
        time,
      ),
      throwsA(isA<w.ApiError>()),
    );
    final malformed = jsonDecode(encoded);
    malformed['synoball']['transactions'][0]['entityId'] = syntheticUser;
    expect(
      () => executor.read(jsonEncode(malformed), syntheticUser),
      throwsA(isA<w.ApiError>()),
    );
  });
}
