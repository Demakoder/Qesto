import 'dart:convert';
import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:qesto_synthetic_sync/domain.dart';
import 'package:qesto_synthetic_sync/protocol.dart';
import 'package:test/test.dart';

Map<String, dynamic> body() => {
  'protocol_version': 1,
  'domain_version': 1,
  'workspace_id': 'w',
  'device_id': 'd',
  'workspace_epoch': 'e',
  'change_id': 'c',
  'kind': 'transaction.set_note',
  'transaction_id': 'synthetic-tx-0',
  'base_revision': '0',
  'note': 'Копейки 0,13 ₽',
};

void main() {
  test(
    'strict command schema rejects mass assignment and unsupported kinds',
    () {
      expect(
        () => NoteCommand.parse({...body(), 'amount': 1}),
        throwsA(isA<ApiError>()),
      );
      expect(
        () => NoteCommand.parse({...body(), 'kind': 'transaction.delete'}),
        throwsA(isA<ApiError>()),
      );
      expect(
        () => NoteCommand.parse({...body(), 'base_revision': 0}),
        throwsA(isA<ApiError>()),
      );
      expect(
        () => NoteCommand.parse({...body(), 'note': null}),
        throwsA(isA<ApiError>()),
      );
      expect(
        () => NoteCommand.parse({...body(), 'note': 'x' * 4097}),
        throwsA(isA<ApiError>()),
      );
      expect(NoteCommand.parse({...body(), 'note': ''}).note, '');
    },
  );
  test('canonical digest stable for property order, changes for content', () {
    final b = body();
    expect(digest(b), digest(Map.fromEntries(b.entries.toList().reversed)));
    expect(digest(b), isNot(digest({...b, 'note': 'other'})));
  });
  test('independent protocol and domain mismatch fail closed', () {
    for (final field in ['protocol_version', 'domain_version']) {
      expect(
        () => NoteCommand.parse({...body(), field: 2}),
        throwsA(isA<ApiError>()),
      );
    }
  });
  test('signed cursor is partition/epoch bound and tamper resistant', () {
    final c = CursorCodec(List.filled(32, 3));
    final token = c.encode('w', 'e', 2, 4);
    expect(c.decode(token, 'w', 'e'), (after: 2, high: 4));
    for (final args in [
      (token, 'foreign', 'e'),
      (token, 'w', 'new'),
      ('${token}x', 'w', 'e'),
    ]) {
      expect(
        () => c.decode(args.$1, args.$2, args.$3),
        throwsA(isA<ApiError>()),
      );
    }
  });
  test(
    'note executor exactly matches shared core with identical clock and IDs',
    () {
      final state = syntheticState('synthetic-owner');
      final command = NoteCommand.parse(body());
      final time = DateTime.utc(2026, 10, 11, 12);
      final expected = SynoballCore(
        initialState: state,
        clock: () => time,
        ids: CommandIds('c'),
      );
      expected.updateTransaction(
        expected
            .transactionById(command.target)!
            .copyWith(userNote: command.note),
        actorId: 'synthetic-owner',
        purpose: 'Synthetic sync transaction.set_note',
      );
      final actual = applyNote(state, command, 'synthetic-owner', time);
      expect(actual.toJson(), expected.state.toJson());
      final roundtrip = SynoballState.fromJson(
        jsonDecode(jsonEncode(actual.toJson())) as Map<String, dynamic>,
      );
      expect(roundtrip.toJson(), actual.toJson());
      for (var i = 0; i < 2; i++) {
        final before = state.transactions[i];
        final after = roundtrip.transactions[i];
        expect(after.id, before.id);
        expect(after.accountId, before.accountId);
        expect(after.amount.minorUnits, before.amount.minorUnits);
        expect(after.amount.currency, before.amount.currency);
        expect(after.direction, before.direction);
        expect(after.status, before.status);
        expect(after.userCategoryOverride, before.userCategoryOverride);
        expect(after.tags, before.tags);
        expect(transactionWire(after)['amount'], {
          'minor_units': '${before.amount.minorUnits}',
          'currency': before.amount.currency,
          'scale': 2,
        });
      }
      expect(roundtrip.auditEntries.length, state.auditEntries.length + 1);
    },
  );
  test('foreign entity and deleted transaction are not note-editable', () {
    final state = syntheticState('owner');
    expect(
      () =>
          applyNote(state, NoteCommand.parse(body()), 'other', DateTime.now()),
      throwsA(isA<ApiError>()),
    );
    final core = SynoballCore(initialState: state)
      ..deleteTransaction('synthetic-tx-0', actorId: 'owner');
    expect(
      () => applyNote(
        core.state,
        NoteCommand.parse(body()),
        'owner',
        DateTime.now(),
      ),
      throwsA(isA<ApiError>()),
    );
  });
}
