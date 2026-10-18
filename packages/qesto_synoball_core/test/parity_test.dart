import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/parity_scenarios.dart';

void main() {
  final actual = runParityScenarios();

  // Independent oracle: these files were captured against the working-tree
  // app implementation BEFORE extraction, not against compatibility exports.
  group('pre-extraction full-state goldens', () {
    for (final scenario in actual.entries) {
      test(scenario.key, () {
        final golden =
            jsonDecode(
                  File(
                    'test/goldens/legacy/${scenario.key}.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        expect(golden['format'], 1);
        expect(golden['scenario'], scenario.key);
        expect(parityIdentityVectors(), golden['identities']);
        expect(scenario.value, golden['steps']);
      });
    }
    test('all frozen scenarios are exercised', () {
      final names = Directory('test/goldens/legacy')
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last.replaceAll('.json', ''));
      expect(actual.keys, unorderedEquals(names));
      expect(actual, hasLength(13));
    });
  });

  Map<String, dynamic> state(String name, [int? step]) =>
      actual[name]![step ?? actual[name]!.length - 1]['state']
          as Map<String, dynamic>;
  List<dynamic> transactions(String name, [int? step]) =>
      state(name, step)['transactions'] as List<dynamic>;

  group('explicit financial safety assertions', () {
    test(
      'replay keeps the original canonical ID and one evidence identity',
      () {
        const name = 'repeated-stable-provider';
        final first = transactions(name, 0).single as Map;
        expect(transactions(name), hasLength(1));
        expect(transactions(name).single['id'], first['id']);
        expect(state(name)['evidence'], hasLength(1));
        expect(actual[name]!.last['outcome']['created'], isEmpty);
        expect(actual[name]!.last['outcome']['matched'], [first['id']]);
      },
    );
    test('similar purchases and one kopeck difference remain separate', () {
      final values = transactions('two-similar-distinct-purchases');
      expect(values, hasLength(3));
      expect(values.map((t) => t['id']).toSet(), hasLength(3));
      expect(values.map((t) => t['amount']['value']), [
        '100.25',
        '100.25',
        '100.26',
      ]);
    });
    test(
      'three sources enrich one fact without losing provenance or receipt',
      () {
        const name = 'notification-statement-receipt';
        expect(transactions(name), hasLength(1));
        expect(state(name)['evidence'], hasLength(3));
        expect(state(name)['receipts'], hasLength(1));
        // This legacy scenario did not supply seed.receiptId. The receipt is
        // retained through its ingestion record/evidence, not an invented link.
        final receipt = (state(name)['receipts'] as List).single;
        expect(
          (state(name)['evidence'] as List).map((e) => e['ingestionRecordId']),
          contains(receipt['ingestionRecordId']),
        );
        expect(receipt['total'], {'value': '100.25', 'currency': 'RUB'});
        expect(state(name)['rawPayloads'], hasLength(3));
      },
    );
    test('source replay and restore preserve user corrections and locks', () {
      final t = transactions('user-overrides-and-field-locks').single as Map;
      expect(t['amount'], {'value': '501.23', 'currency': 'RUB'});
      expect(t['merchantName'], 'User title');
      expect(t['normalizedDescription'], 'User description');
      expect(t['userNote'], 'User note');
      expect(t['userCategoryOverride'], 'sport');
      expect(
        t['tags'],
        containsAll([
          'user-field:amount',
          'user-field:merchant',
          'user-field:description',
          'user-field:note',
          'user-field:category',
        ]),
      );
    });
    for (final lifecycle in ['posted', 'pending', 'cancelled']) {
      test('trash suppresses replay; explicit restore retains $lifecycle', () {
        final name = 'trash-replay-restore-$lifecycle';
        final replay = actual[name]![3];
        final t = transactions(name, 3).single;
        expect(t['status'], 'deleted');
        expect(t['amount']['value'], '100.25');
        expect(replay['outcome']['created'], isEmpty);
        expect(replay['outcome']['matched'], isEmpty);
        expect(replay['outcome']['suppressed'], [t['id']]);
        expect(transactions(name), hasLength(1));
        expect(transactions(name).single['id'], t['id']);
        expect(
          transactions(name).single['status'],
          lifecycle == 'cancelled' ? 'reversed' : lifecycle,
        );
        expect(
          transactions(name).single['tags'],
          isNot(contains(startsWith('trash:'))),
        );
      });
    }
    for (final reverse in [false, true]) {
      test('ambiguous batch does not merge blindly, order=$reverse', () {
        final name = 'ambiguous-cross-source-batch-$reverse';
        final result = actual[name]![1]['outcome'] as Map;
        expect(result['created'], isEmpty);
        expect(result['matched'], isEmpty);
        expect(result['pending'], hasLength(2));
        expect(result['resolved'], [null, null]);
        expect(transactions(name), hasLength(1));
        expect(state(name)['evidence'], hasLength(1));
      });
    }
    test('unconfirmed near-trash identity requires review', () {
      const name = 'unconfirmed-deleted-identity-needs-review';
      expect(transactions(name).single['status'], 'deleted');
      expect(actual[name]!.last['outcome']['pending'], hasLength(1));
      expect(actual[name]!.last['outcome']['created'], isEmpty);
    });
    test('provider identity remains scoped by connection', () {
      const name = 'same-provider-different-source-scope';
      expect(transactions(name), hasLength(2));
      expect(state(name)['ingestionRecords'].map((r) => r['connectionId']), [
        'connection-one',
        'connection-two',
      ]);
    });
    test('existing manual IDs are retained, not regenerated or coalesced', () {
      expect(transactions('manual-ids-remain-distinct').map((t) => t['id']), [
        'existing-manual-001',
        'existing-manual-002',
      ]);
    });
    test(
      'money serialization, currencies, directions and types remain exact',
      () {
        const name = 'money-currencies-directions-and-types';
        final values = transactions(name);
        expect(values, hasLength(12));
        for (final currency in ['RUB', 'USD', 'EUR', 'CNY']) {
          final group = values.where(
            (t) => t['amount']['currency'] == currency,
          );
          expect(group.map((t) => t['amount']['value']), [
            '4861.22',
            '15000.25',
            '15000.00',
          ]);
          expect(group.map((t) => t['direction']), [
            'outflow',
            'inflow',
            'outflow',
          ]);
          expect(group.map((t) => t['eventType']), [
            'observed',
            'observed',
            'observed',
          ]);
          expect(
            group.last['tags'],
            containsAll(['sber-own-transfer', 'transfer']),
          );
          final account = (state(name)['accounts'] as List).singleWhere(
            (a) => a['id'] == 'account-$currency',
          );
          expect(account['balance'], {
            'value': '15000.25',
            'currency': currency,
          });
          expect(account['type'], 'savings');
        }
      },
    );
  });
}
