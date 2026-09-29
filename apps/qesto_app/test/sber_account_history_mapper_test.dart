import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/bank_browser/sber/sber_account_history_mapper.dart';
import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';

void main() {
  SberTransactionFact row(String id, {String account = '', int minor = 1025}) =>
      SberTransactionFact(
        sourceId: id,
        accountId: account,
        date: DateTime(2026, 9, 8),
        amount: 10,
        exactAmountMinor: minor,
        currency: 'RUB',
        description: 'Shop',
        status: 'POSTED',
        fingerprint: 'fingerprint-$id',
      );
  test('filtered history links only exact bank operation identities', () {
    final mapper = SberAccountHistoryMapper();
    mapper.observe('canonical-a', [row('p1', account: 'card-a')]);
    final result = mapper.apply([row('p1'), row('p2'), row('p1', minor: 1026)]);
    expect(result.map((r) => r.accountId), ['canonical-a', '', '']);
  });
  test('a payment in two product histories stays unresolved', () {
    final mapper = SberAccountHistoryMapper();
    mapper.observe('a', [row('p', account: 'card-a')]);
    mapper.observe('b', [row('p', account: 'card-b')]);
    expect(mapper.apply([row('p')]).single.accountId, isEmpty);
    expect(mapper.conflicts, 1);
  });
  test(
    'scope-less row and existing explicit account are never overwritten',
    () {
      final mapper = SberAccountHistoryMapper();
      mapper.observe('a', [row('p')]);
      expect(mapper.apply([row('p')]).single.accountId, isEmpty);
      mapper.observe('a', [row('p', account: 'card-a')]);
      expect(mapper.apply([row('p', account: 'b')]).single.accountId, 'b');
    },
  );
}
