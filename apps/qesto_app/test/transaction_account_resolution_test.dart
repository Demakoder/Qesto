import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/transaction_import/services/transaction_account_resolver.dart';

void main() {
  const resolver = TransactionAccountResolver();
  QestoAccount account(String id, String title) => QestoAccount(
    id: id,
    userId: 'u',
    title: title,
    balance: 0,
    currency: 'RUB',
    type: AccountType.bankCard,
  );
  test('unknown explicit suffix never falls back to sole bank/card', () {
    expect(
      resolver.resolve(
        accounts: [account('a', 'Сбер •• 1234')],
        bankHint: 'sber',
        accountHint: '*9999',
      ),
      isNull,
    );
  });
  test('both account and linked card suffix are recognized', () {
    for (final suffix in ['1234', '5678']) {
      expect(
        resolver
            .resolve(
              accounts: [account('a', 'Сбер счёт •• 1234 · карта •• 5678')],
              bankHint: 'sber',
              accountHint: '*$suffix',
            )
            ?.accountId,
        'a',
      );
    }
  });
  test('colliding suffixes remain unresolved', () {
    expect(
      resolver.resolve(
        accounts: [account('a', 'Сбер •• 1234'), account('b', 'Сбер •• 1234')],
        bankHint: 'sber',
        accountHint: '*1234',
      ),
      isNull,
    );
  });
  test('bank-name-only is a suggestion, not an automatic mapping', () {
    expect(
      resolver
          .resolve(accounts: [account('a', 'Сбер •• 1234')], bankHint: 'sber')!
          .confidence,
      lessThan(0.9),
    );
  });
}
