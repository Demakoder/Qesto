import 'dart:convert';
import 'dart:io';

import 'package:qesto_synoball_core/qesto_synoball_core.dart';
import 'package:test/test.dart';

import 'support/parity_scenarios.dart';

StatementInput input({String provider = 'synthetic-operation-001'}) =>
    StatementInput(
      entityId: parityAccount.entityId,
      receivedAt: parityNow.add(const Duration(hours: 1)),
      rawPayload: '{"synthetic":true}',
      batchName: 'Synthetic test',
      account: parityAccount,
      transactions: [
        TransactionSeed(
          accountId: parityAccount.id,
          amount: const Money(minorUnits: 486122, currency: 'RUB'),
          direction: FinancialDirection.outflow,
          occurredAt: parityNow,
          description: 'Synthetic expense',
          providerTransactionId: provider,
          confidence: 1,
        ),
      ],
    );

void main() {
  test('clock injection controls bookkeeping, not source facts', () {
    var now = DateTime.utc(2030, 1, 2, 3, 4, 5);
    final ids = ParityIds();
    final core = SynoballCore(ids: ids, clock: () => now);
    core.ingest(StatementAdapter(ids: ids), input());
    final first = core.transactions.single;
    expect(first.createdAt, now);
    expect(first.updatedAt, now);
    expect(first.occurredAt, parityNow);
    expect(
      core.state.rawPayloads.single.createdAt,
      parityNow.add(const Duration(hours: 1)),
    );
    expect(
      core.state.evidence.single.observedAt,
      parityNow.add(const Duration(hours: 1)),
    );
    expect(core.state.events.every((e) => e.occurredAt == now), isTrue);

    now = now.add(const Duration(days: 1));
    core.updateTransaction(
      first.copyWith(userNote: 'User note'),
      actorId: 'test',
    );
    expect(core.transactions.single.updatedAt, now);
    expect(core.transactions.single.createdAt, first.createdAt);
    expect(core.state.auditEntries.last.occurredAt, now);
    expect(core.state.events.last.occurredAt, now);

    now = now.add(const Duration(days: 1));
    core.deleteTransaction(first.id, actorId: 'test');
    expect(core.transactions, isEmpty);
    expect(core.state.transactions.single.updatedAt, now);
    expect(core.state.events.last.payload['changedAt'], now.toIso8601String());
    expect(core.state.auditEntries.last.occurredAt, now);
    expect(() => core.restoreTransaction(first), throwsStateError);

    now = now.add(const Duration(days: 1));
    expect(core.restoreDeletedTransaction(first.id, actorId: 'test'), isTrue);
    expect(core.transactions.single.updatedAt, now);
    expect(core.state.events.last.payload['changedAt'], now.toIso8601String());
    expect(core.state.auditEntries.last.occurredAt, now);
  });

  test(
    'complete JSON state survives restart without timestamp normalization',
    () {
      final ids = ParityIds();
      final core = SynoballCore(ids: ids, clock: () => parityNow);
      core.ingest(StatementAdapter(ids: ids), input());
      core.updateTransaction(
        core.transactions.single.copyWith(
          userCategoryOverride: 'sport',
          userNote: 'Synthetic persisted note',
          tags: ['user-field:category', 'user-field:note'],
        ),
        actorId: 'test',
      );
      core.deleteTransaction(core.transactions.single.id, actorId: 'test');
      final encoded = jsonEncode(core.state.toJson());
      final decoded = SynoballState.fromJson(jsonDecode(encoded));
      expect(jsonEncode(decoded.toJson()), encoded);
      final restored = SynoballCore(
        initialState: decoded,
        ids: ids,
        clock: () => parityNow,
      );
      expect(restored.state.toJson(), core.state.toJson());
      final outcome = restored.ingest(StatementAdapter(ids: ids), input());
      expect(outcome.createdTransactionIds, isEmpty);
      expect(outcome.suppressedTransactionIds, [
        decoded.transactions.single.id,
      ]);
      expect(
        restored.restoreDeletedTransaction(
          decoded.transactions.single.id,
          actorId: 'test',
        ),
        isTrue,
      );
      expect(restored.transactions.single.amount.minorUnits, 486122);
      expect(restored.transactions.single.userCategoryOverride, 'sport');
      expect(restored.transactions.single.userNote, 'Synthetic persisted note');
    },
  );

  test(
    'default wall clock and production ID factory retain original contract',
    () {
      final start = DateTime.now();
      final core = SynoballCore();
      core.ingest(StatementAdapter(), input());
      final end = DateTime.now();
      final t = core.transactions.single;
      expect(t.createdAt.isBefore(start), isFalse);
      expect(t.createdAt.isAfter(end), isFalse);
      expect(core.state.rawPayloads.single.id, matches(r'^raw-\d+-\d+-\d+$'));
      expect(
        core.state.ingestionRecords.single.id,
        matches(r'^ing-\d+-\d+-\d+$'),
      );
      expect(t.id, matches(r'^txn-cand-\d+-\d+-\d+$'));
      expect(t.occurredAt, parityNow);
    },
  );

  test('bookkeeping clock never silently changes the default ID epoch', () {
    final start = DateTime.now().microsecondsSinceEpoch;
    final core = SynoballCore(clock: () => DateTime.utc(1990));
    core.ingest(StatementAdapter(), input());
    final end = DateTime.now().microsecondsSinceEpoch;
    final eventEpoch = int.parse(core.state.events.first.id.split('-')[1]);
    expect(eventEpoch, inInclusiveRange(start, end));
    expect(core.transactions.single.createdAt, DateTime.utc(1990));
  });

  test('explicit ID clock retains per-process and per-factory sequences', () {
    final a = SynoballIdFactory(clock: () => parityNow);
    final b = SynoballIdFactory(clock: () => parityNow);
    final first = a.next('test').split('-');
    final second = b.next('test').split('-');
    final third = a.next('test').split('-');
    expect(first[1], '${parityNow.microsecondsSinceEpoch}');
    expect(second[1], first[1]);
    expect(int.parse(second[2]), int.parse(first[2]) + 1);
    expect(int.parse(third[2]), int.parse(second[2]) + 1);
    expect([first[3], second[3], third[3]], ['1', '1', '2']);
  });

  test('all library dependencies stay inside a pure offline Dart boundary', () {
    final pattern = RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    expect(files.length, greaterThanOrEqualTo(13));
    for (final file in files) {
      for (final match in pattern.allMatches(file.readAsStringSync())) {
        final uri = match.group(1)!;
        if (uri.startsWith('dart:') || uri.startsWith('package:')) {
          expect(
            uri,
            anyOf(
              'dart:convert',
              'dart:math',
              'dart:collection', // Opt-in journal list interceptors; still pure Dart.
              'package:cryptography/dart.dart',
            ),
            reason: '${file.path}: $uri',
          );
        } else {
          final target = file.absolute.uri.resolve(uri);
          expect(
            target.toString(),
            startsWith(Directory('lib').absolute.uri.toString()),
          );
          expect(File.fromUri(target).existsSync(), isTrue);
        }
      }
    }
  });
}
