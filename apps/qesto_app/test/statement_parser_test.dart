import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/statement_import/domain/bank_statement_models.dart';
import 'package:qesto/features/statement_import/services/sberbank_statement_parser.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

const redactedSberStatementText = '''
СБЕР 900 www.sberbank.ru
Выписка по платёжному счёту
За период 01.07.2026 — 31.07.2026
Номер счёта 40817 810 0 0000 0012345
Расшифровка операций
07.07.2026 10:30 Супермаркеты 84,99 6 010,12
07.07.2026 737816 MAGNIT TEST MOSCOW RUS. Операция по карте
****8505
06.07.2026 13:00 Перевод на карту +500,00 6 095,11
06.07.2026 123456 Перевод от И. Имя. Операция по счету ****2345
05.07.2026 19:32 Перевод СБП 652,49 5 595,11
05.07.2026 468119 Перевод в другой банк. Операция по счету ****2345
04.07.2026 13:00 Возврат, отмена операции +540,00 6 247,60
04.07.2026 659298 CAFE TEST MOSCOW RUS. Операция по карте ****8505
''';

void main() {
  const parser = SberbankStatementParser();

  test('разбирает операции, суммы, период и последние цифры счёта', () {
    final statement = parser.parse(redactedSberStatementText);

    expect(statement.bankName, 'Сбербанк');
    expect(statement.periodStart, DateTime(2026, 7, 1));
    expect(statement.periodEnd, DateTime(2026, 7, 31));
    expect(statement.accountLastFour, '2345');
    expect(statement.transactions, hasLength(4));

    final purchase = statement.transactions.first;
    expect(purchase.amountMinor, 8499);
    expect(purchase.balanceMinor, 601012);
    expect(purchase.authorizationCode, '737816');
    expect(purchase.cardLastFour, '8505');
    expect(purchase.merchant, 'MAGNIT TEST MOSCOW RUS');
    expect(purchase.category.categoryId, 'groceries');
    expect(purchase.kind, StatementTransactionKind.expense);
  });

  test('отделяет доходы, переводы и возвраты от расходов', () {
    final transactions = parser.parse(redactedSberStatementText).transactions;

    expect(transactions[1].kind, StatementTransactionKind.transfer);
    expect(transactions[1].isIncoming, isTrue);
    expect(transactions[2].kind, StatementTransactionKind.transfer);
    expect(transactions[2].isIncoming, isFalse);
    expect(transactions[3].kind, StatementTransactionKind.refund);
    expect(transactions[3].isIncoming, isTrue);
  });

  test('в список потребительских операций входят расход и возврат', () {
    final statement = parser.parse(redactedSberStatementText);

    expect(statement.transactions, hasLength(4));
    expect(statement.transactions.map((item) => item.authorizationCode), [
      '737816',
      '123456',
      '468119',
      '659298',
    ]);
  });

  test('отклоняет документ другого банка', () {
    expect(
      () => parser.parse('Выписка другого банка'),
      throwsA(isA<UnsupportedBankStatementException>()),
    );
  });

  test('контроллер создаёт недостающий месяц и не добавляет дубль', () async {
    final controller = BudgetController(
      configuration: budgetConfiguration,
      financialData: UserFinancialData(
        user: const QestoUser(
          id: 'test-user',
          name: 'Тест',
          defaultCurrency: 'RUB',
        ),
        referenceDate: DateTime(2026, 8, 8),
      ),
    );
    final period = controller.periodForOrCreate(DateTime(2026, 5, 4));
    final transaction = BudgetTransaction(
      id: 'sber-test-operation',
      userId: period.userId,
      accountId: controller.accounts.first.id,
      date: DateTime(2026, 5, 4),
      amount: 100,
      currency: 'RUB',
      type: TransactionType.expense,
      categoryId: 'other',
    );

    await controller.addImportedTransactions([transaction, transaction]);

    expect(period.startDate, DateTime(2026, 5));
    expect(controller.periods, hasLength(2));
    expect(controller.transactions, hasLength(1));
  });
}
