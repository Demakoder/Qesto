import 'dart:convert';
import 'package:test/test.dart';
import 'package:qesto_storage_spike/container/contract.dart';
import 'package:qesto_synthetic_sync/domain.dart' as domain;
import 'package:qesto_synthetic_sync/protocol.dart' as w;
import 'package:qesto_encrypted_sync_experiment/profile_adapter.dart';
import 'package:qesto_encrypted_sync_experiment/client_identity.dart';
import 'harness.dart' show fixture;

w.NoteCommand cmd(String target, String note) => w.NoteCommand.parse({
  'protocol_version': 1,
  'domain_version': 1,
  'workspace_id': 'synthetic',
  'device_id': 'device-a',
  'workspace_epoch': 'epoch-test',
  'change_id': 'note-test',
  'kind': 'transaction.set_note',
  'transaction_id': target,
  'base_revision': '0',
  'note': note,
});
void main() {
  test(
    'client identity is scoped to one device and rejects server credentials',
    () {
      final input = {
        'marker': 'qesto.encrypted-sync-client.v1',
        'index': 0,
        'token': 'synthetic-token-with-more-than-32-characters',
        'user': 'synthetic-user',
        'device': 'a',
        'workspace': 'synthetic',
        'epoch': 'epoch-test',
      };
      expect(ClientIdentity.parse(input, 0).principal.device, 'a');
      expect(() => ClientIdentity.parse(input, 1), throwsA(anything));
      for (final field in ['db_password', 'cursor_key', 'principals']) {
        expect(
          () => ClientIdentity.parse({...input, field: 'not-for-client'}, 0),
          throwsA(anything),
        );
      }
    },
  );
  test(
    'existing shared core result is used, not a second note/financial algorithm',
    () {
      final before = fixture(),
          command = cmd('container-tx-0', 'Точная заметка 13 ₽'),
          now = DateTime.utc(2026, 10, 11);
      final actual = ProfileAdapter.note(before, command, 'demo-user', now);
      final expected = domain.applyNote(
        ProfileAdapter.core(before),
        command,
        'demo-user',
        now,
      );
      expect(ProfileAdapter.root(actual)['synoball'], expected.toJson());
      final initial = ProfileAdapter.root(before),
          next = ProfileAdapter.root(actual);
      for (final field in initial.keys.where(
        (f) => f != 'synoball' && f != 'transactions',
      )) {
        expect(next[field], initial[field]);
      }
    },
  );
  test(
    'unrelated legacy comments are retained even when not identical to canonical note',
    () {
      final root = ProfileAdapter.root(fixture());
      final legacy = root['transactions'] as List;
      final target = Map<String, dynamic>.from(legacy.last as Map);
      legacy.add({
        ...target,
        'id': 'container-tx-1',
        'comment': 'Independent legacy fallback',
      });
      final before = FinancialSnapshot(jsonEncode(root)),
          command = cmd('container-tx-0', 'Changed');
      final local = ProfileAdapter.note(
        before,
        command,
        'demo-user',
        DateTime.utc(2026, 10, 11),
      );
      final entity = {
        'revision': '1',
        'transaction': domain.transactionWire(
          ProfileAdapter.core(local).transactions.first,
        ),
      };
      final incoming = ProfileAdapter.incoming(before, [entity]);
      final projected = ProfileAdapter.project(before, incoming, {});
      for (final value in [local, incoming, projected]) {
        final rows = ProfileAdapter.root(value)['transactions'] as List;
        expect(rows.last['comment'], 'Independent legacy fallback');
        expect(
          rows.firstWhere((t) => t['id'] == 'container-tx-0')['comment'],
          'Changed',
        );
      }
    },
  );
  test(
    'blank note clears only the targeted comment; immutable fields and trash stay intact',
    () {
      final before = fixture(),
          result = ProfileAdapter.note(
            before,
            cmd('container-tx-0', ''),
            'demo-user',
            DateTime.utc(2026, 10, 11),
          );
      final a = ProfileAdapter.core(before), b = ProfileAdapter.core(result);
      expect(b.transactions.first.userNote, '');
      for (var i = 0; i < a.transactions.length; i++) {
        for (final key in [
          'id',
          'entityId',
          'accountId',
          'amount',
          'direction',
          'status',
          'occurredAt',
          'tags',
          'userCategoryOverride',
        ]) {
          expect(
            b.transactions[i].toJson()[key],
            a.transactions[i].toJson()[key],
          );
        }
      }
    },
  );
  test('unsupported financial mutation and inserts fail closed', () {
    final before = fixture(),
        transaction = domain.transactionWire(
          ProfileAdapter.core(before).transactions.first,
        );
    for (final field in ['id', 'amount', 'direction', 'userCategoryOverride']) {
      final changed = w.object(jsonDecode(jsonEncode(transaction)));
      switch (field) {
        case 'id':
          changed['id'] = 'unknown';
        case 'amount':
          changed['amount']['minor_units'] = '99';
        case 'direction':
          changed['direction'] = 'inflow';
        case 'userCategoryOverride':
          changed['userCategoryOverride'] = 'other';
      }
      expect(
        () => ProfileAdapter.incoming(before, [
          {'revision': '1', 'transaction': changed},
        ]),
        throwsA(isA<ContractViolation>()),
      );
    }
  });
}
