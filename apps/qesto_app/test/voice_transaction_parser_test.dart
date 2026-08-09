import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/voice_transaction/domain/voice_transaction_models.dart';
import 'package:qesto/features/voice_transaction/services/voice_transaction_parser.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

void main() {
  const parser = VoiceTransactionParser();
  const accounts = [
    QestoAccount(
      id: 'sber',
      userId: 'user',
      title: 'Карта Сбер',
      balance: 10000,
      currency: 'RUB',
      type: AccountType.bankCard,
    ),
    QestoAccount(
      id: 'savings',
      userId: 'user',
      title: 'Накопительный счёт',
      balance: 20000,
      currency: 'RUB',
      type: AccountType.savings,
    ),
  ];

  test('распознаёт расход, сумму и категорию продуктов', () {
    final draft = parser.parse(
      text: 'Потратил 850 рублей на продукты',
      categories: budgetCategories,
      accounts: accounts,
    );

    expect(draft.kind, VoiceTransactionKind.expense);
    expect(draft.amount, 850);
    expect(draft.categoryId, 'groceries');
    expect(draft.title, 'Продукты');
    expect(draft.sourceAccountId, 'sber');
  });

  test('понимает доход и сумму, произнесённую словами', () {
    final draft = parser.parse(
      text: 'Получил зарплату пятьдесят две тысячи рублей',
      categories: budgetCategories,
      accounts: accounts,
    );

    expect(draft.kind, VoiceTransactionKind.income);
    expect(draft.amount, 52000);
    expect(draft.title, 'Зарплата');
    expect(draft.categoryId, isNull);
  });

  test('находит исходный и конечный счета перевода', () {
    final draft = parser.parse(
      text: 'Перевёл 1 500 рублей с карты Сбер на накопительный счёт',
      categories: budgetCategories,
      accounts: accounts,
    );

    expect(draft.kind, VoiceTransactionKind.transfer);
    expect(draft.amount, 1500);
    expect(draft.sourceAccountId, 'sber');
    expect(draft.destinationAccountId, 'savings');
  });

  test('не создаёт операцию без суммы', () {
    expect(
      () => parser.parse(
        text: 'Купил продукты',
        categories: budgetCategories,
        accounts: accounts,
      ),
      throwsA(isA<VoiceTransactionParseException>()),
    );
  });
}
