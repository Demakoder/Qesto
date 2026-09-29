import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/statement_import/domain/bank_statement_models.dart';
import 'package:qesto/features/statement_import/services/sberbank_statement_parser.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/synoball/synoball.dart';

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

const redactedColumnarSberStatementText = '''
900 www.sberbank.ru
Выписка по платёжному счёту
За период 01.07.2026 — 31.07.2026
Номер счёта
40817 810 0 0000 0012345
Расшифровка операций
ДАТА ОПЕРАЦИИ (МСК) КАТЕГОРИЯ
Дата обработки
Описание операции
и код авторизации
07.07.2026 10:30 Супермаркеты 07.07.2026 737816 MAGNIT TEST MOSCOW RUS. Операция по карте ****8505
06.07.2026 13:00 Перевод на карту 06.07.2026 123456 Перевод от И. Имя. Операция по счету
****2345
СУММА В ВАЛЮТЕ СЧЁТА ОСТАТОК СРЕДСТВ
Сумма в валюте
В валюте счёта
операции
84,99
6 010,12
+500,00
6 095,11
\f
Выписка по платёжному счёту Страница 2 из 2
ДАТА ОПЕРАЦИИ (МСК) КАТЕГОРИЯ
Дата обработки
Описание операции
и код авторизации
05.07.2026 19:32 Перевод СБП 05.07.2026 468119 Перевод в другой банк. Операция по счету ****2345
04.07.2026 13:00 Возврат, отмена операции 04.07.2026 659298 CAFE TEST MOSCOW RUS. Операция по карте ****8505
СУММА В ВАЛЮТЕ СЧЁТА ОСТАТОК СРЕДСТВ
652,49
5 595,11
+540,00
6 247,60
''';

const redactedTransferClassificationStatementText = '''
СБЕР 900 www.sberbank.ru
Выписка по платёжному счёту
За период 01.08.2026 — 31.08.2026
Номер счёта 40817 810 0 0000 005023
Расшифровка операций
06.08.2026 12:00 Перевод СБП 305,00 9 000,00
06.08.2026 100001 Перевод в Yandex. Операция по счету ****5023
05.08.2026 12:00 Перевод с карты 1 200,00 9 305,00
05.08.2026 100002 Перевод для И. Имя. Операция по счету ****5023
04.08.2026 12:00 Перевод СБП 13 749,09 10 505,00
04.08.2026 100003 Перевод в другой банк. Операция по счету ****5023
03.08.2026 12:00 Перевод между своими счетами 2 000,00 24 254,09
03.08.2026 100004 Перевод между своими счетами. Операция по счету ****5023
02.08.2026 12:00 Выдача наличных 500,00 26 254,09
02.08.2026 100005 ATM TEST. Операция по карте ****8505
01.08.2026 12:00 Внесение наличных +1 000,00 26 754,09
01.08.2026 100006 ATM TEST. Операция по карте ****8505
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

  test('отделяет доходы, внешние переводы и возвраты от расходов', () {
    final transactions = parser.parse(redactedSberStatementText).transactions;

    expect(transactions[1].kind, StatementTransactionKind.income);
    expect(transactions[1].isIncoming, isTrue);
    expect(transactions[2].kind, StatementTransactionKind.expense);
    expect(transactions[2].isIncoming, isFalse);
    expect(transactions[3].kind, StatementTransactionKind.refund);
    expect(transactions[3].isIncoming, isTrue);
  });

  test('разбирает новый двухколоночный PDF-шаблон Сбербанка', () {
    final statement = parser.parse(redactedColumnarSberStatementText);

    expect(statement.transactions, hasLength(4));
    expect(statement.accountLastFour, '2345');
    expect(statement.transactions.map((item) => item.authorizationCode), [
      '737816',
      '123456',
      '468119',
      '659298',
    ]);
    expect(statement.transactions.map((item) => item.amountMinor), [
      8499,
      50000,
      65249,
      54000,
    ]);
    expect(statement.transactions[0].kind, StatementTransactionKind.expense);
    expect(statement.transactions[1].kind, StatementTransactionKind.income);
    expect(statement.transactions[1].isIncoming, isTrue);
    expect(statement.transactions[2].kind, StatementTransactionKind.expense);
    expect(statement.transactions[3].kind, StatementTransactionKind.refund);
    expect(statement.transactions[3].isIncoming, isTrue);
    expect(statement.transactions[1].cardLastFour, '2345');
  });

  test(
    'считает внешние исходящие переводы расходом, а свои и наличные — переводом',
    () {
      final transactions = parser
          .parse(redactedTransferClassificationStatementText)
          .transactions;

      expect(transactions, hasLength(6));
      expect(
        transactions.take(3).map((item) => item.kind),
        everyElement(StatementTransactionKind.expense),
      );
      expect(transactions[3].kind, StatementTransactionKind.transfer);
      expect(transactions[4].kind, StatementTransactionKind.transfer);
      expect(transactions[5].kind, StatementTransactionKind.transfer);
      expect(transactions[5].isIncoming, isTrue);
    },
  );

  test('двухколоночная выписка входит в Synoball через StatementAdapter', () {
    final statement = parser.parse(redactedColumnarSberStatementText);
    const entityId = 'entity-sber-regression';
    const accountId = 'account-sber-regression';
    final synoball = SynoballCore()
      ..upsertEntity(
        const SynoballEntity(
          id: entityId,
          type: SynoballEntityType.person,
          displayName: 'Тестовый пользователь',
        ),
      );

    final outcome = synoball.ingest(
      StatementAdapter(),
      StatementInput(
        entityId: entityId,
        receivedAt: DateTime(2026, 8, 13),
        rawPayload: redactedColumnarSberStatementText,
        batchName: 'Обезличенная выписка Сбербанка',
        account: const SynoballAccount(
          id: accountId,
          entityId: entityId,
          name: 'Сбер • 2345',
          type: SynoballAccountType.card,
          currency: 'RUB',
          balance: Money(minorUnits: 624760, currency: 'RUB'),
        ),
        transactions: statement.transactions
            .map(
              (item) => TransactionSeed(
                canonicalId: item.id,
                accountId: accountId,
                amount: Money(minorUnits: item.amountMinor, currency: 'RUB'),
                direction: item.isIncoming
                    ? FinancialDirection.inflow
                    : FinancialDirection.outflow,
                occurredAt: item.operationDate,
                description: item.description,
                merchant: item.merchant,
                category: item.category.categoryId,
                subcategoryId: item.category.subcategoryId,
                providerTransactionId: item.id,
                confidence: item.confidence,
              ),
            )
            .toList(growable: false),
      ),
    );

    expect(outcome.createdTransactionIds, hasLength(4));
    expect(synoball.transactions, hasLength(4));
    expect(synoball.state.importBatches.single.totalRecords, 4);
    expect(
      synoball.state.evidence.every(
        (item) =>
            item.sourceType == SynoballSourceType.statement &&
            item.trust == SourceTrustLevel.bankStatement,
      ),
      isTrue,
    );
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

  test(
    'старый внешний перевод Сбербанка становится расходом без миграции Synoball',
    () {
      final controller = _controllerWithStoredTransaction(
        _storedTransfer(
          description: 'Перевод в Yandex. Операция по счету ****5023',
          tags: const [
            'statement-import',
            'sberbank',
            'transfer-outgoing',
            'legacy-type-transfer',
          ],
        ),
      );

      expect(controller.transactions.single.type, TransactionType.expense);
    },
  );

  test('старые свои и ручные переводы остаются нейтральными', () {
    final ownAccount = _controllerWithStoredTransaction(
      _storedTransfer(
        description: 'Перевод между своими счетами',
        tags: const [
          'statement-import',
          'sberbank',
          'transfer-outgoing',
          'legacy-type-transfer',
        ],
      ),
    );
    final manual = _controllerWithStoredTransaction(
      _storedTransfer(
        description: 'Перевод другу',
        tags: const ['legacy-type-transfer'],
      ),
    );

    expect(ownAccount.transactions.single.type, TransactionType.transfer);
    expect(manual.transactions.single.type, TransactionType.transfer);
  });
}

BudgetController _controllerWithStoredTransaction(
  CanonicalTransaction transaction,
) => BudgetController(
  configuration: budgetConfiguration,
  financialData: UserFinancialData(
    user: const QestoUser(
      id: 'test-user',
      name: 'Тест',
      defaultCurrency: 'RUB',
    ),
    referenceDate: DateTime(2026, 8, 23),
    synoballState: SynoballState(transactions: [transaction]),
  ),
);

CanonicalTransaction _storedTransfer({
  required String description,
  required List<String> tags,
}) {
  final now = DateTime(2026, 8, 23);
  return CanonicalTransaction(
    id: 'transaction-${description.hashCode}',
    entityId: 'ent-test-user',
    accountId: 'sber-account',
    status: CanonicalTransactionStatus.posted,
    amount: const Money(minorUnits: 10000, currency: 'RUB'),
    direction: FinancialDirection.outflow,
    occurredAt: now,
    rawDescription: description,
    normalizedDescription: description.toLowerCase(),
    transferDirection: TransferDirection.outgoing.name,
    eventType: FinancialEventType.observed,
    tags: tags,
    createdAt: now,
    updatedAt: now,
    fieldTrust: SourceTrustLevel.bankStatement,
  );
}
