import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/synoball/synoball.dart';

void main() {
  const entityId = 'ent-ivan';
  const cashAccount = 'acc-cash';

  SynoballCore core() {
    final value = SynoballCore();
    value.upsertEntity(
      const SynoballEntity(
        id: entityId,
        type: SynoballEntityType.person,
        displayName: 'Иван',
      ),
    );
    value.upsertAccount(
      const SynoballAccount(
        id: cashAccount,
        entityId: entityId,
        name: 'Основной счёт',
        type: SynoballAccountType.card,
        currency: 'RUB',
        balance: Money(minorUnits: 19000000, currency: 'RUB'),
      ),
    );
    return value;
  }

  TransactionSeed seed({
    required DateTime date,
    int amountMinor = 149000,
    String accountId = cashAccount,
    String merchant = 'Пятёрочка',
    String? providerId,
    String? canonicalId,
    String? receiptId,
  }) => TransactionSeed(
    canonicalId: canonicalId,
    accountId: accountId,
    amount: Money(minorUnits: amountMinor, currency: 'RUB'),
    direction: FinancialDirection.outflow,
    occurredAt: date,
    description: merchant,
    merchant: merchant,
    category: 'groceries',
    providerTransactionId: providerId,
    receiptId: receiptId,
    tags: const ['legacy-type-expense'],
    confidence: 0.9,
  );

  test('notification, bank operation and receipt become one transaction', () {
    final synoball = core();
    final date = DateTime(2026, 8, 12, 12, 1);
    synoball.ingest(
      AndroidNotificationAdapter(),
      AndroidNotificationInput(
        entityId: entityId,
        receivedAt: date,
        rawPayload: 'Покупка 1 490 ₽ ПЯТЕРОЧКА',
        notificationKey: 'notification-1',
        packageName: 'ru.sberbankmobile',
        transaction: seed(date: date, providerId: 'notification-1'),
      ),
    );
    final bank = synoball.ingest(
      StatementAdapter(),
      StatementInput(
        entityId: entityId,
        receivedAt: date.add(const Duration(minutes: 5)),
        rawPayload: '12.08.2026 PYATEROCHKA -1490.00',
        batchName: 'Statement August 2026',
        account: const SynoballAccount(
          id: 'acc-sber',
          entityId: entityId,
          name: 'Сбер • 1234',
          type: SynoballAccountType.card,
          currency: 'RUB',
          balance: Money(minorUnits: 5000000, currency: 'RUB'),
        ),
        transactions: [
          seed(
            date: date.add(const Duration(minutes: 4)),
            accountId: 'acc-sber',
            merchant: 'PYATEROCHKA 1834 MOSCOW',
            providerId: 'bank-1',
          ),
        ],
      ),
    );
    final receipt = synoball.ingest(
      ReceiptAdapter(),
      ReceiptInput(
        entityId: entityId,
        receivedAt: date.add(const Duration(hours: 6)),
        rawPayload: 't=20260812T1201&s=1490.00&fn=1&i=2&fp=3&n=1',
        transaction: seed(
          date: date,
          merchant: 'ПЯТЕРОЧКА',
          providerId: '1:2:3',
          receiptId: 'receipt-1:2:3',
        ),
        fiscalFingerprint: '1:2:3',
        rawText: 'ПЯТЕРОЧКА\n1490 РУБ',
        merchant: 'Пятёрочка',
        items: const [
          ReceiptItem(
            name: 'Молоко',
            total: Money(minorUnits: 12000, currency: 'RUB'),
          ),
        ],
      ),
    );

    expect(synoball.transactions, hasLength(1));
    expect(bank.createdTransactionIds, isEmpty);
    expect(bank.matchedTransactionIds, hasLength(1));
    expect(receipt.createdTransactionIds, isEmpty);
    expect(receipt.matchedTransactionIds, hasLength(1));
    expect(synoball.state.evidence, hasLength(3));
    expect(synoball.transactions.single.merchantName, 'Пятёрочка');
    expect(synoball.transactions.single.effectiveCategory, 'groceries');
    expect(synoball.transactions.single.receiptId, 'receipt-1:2:3');
  });

  test('two similar notifications remain two real purchases', () {
    final synoball = core();
    final date = DateTime(2026, 8, 12, 12);
    for (var index = 0; index < 2; index++) {
      synoball.ingest(
        AndroidNotificationAdapter(),
        AndroidNotificationInput(
          entityId: entityId,
          receivedAt: date.add(Duration(minutes: index * 5)),
          rawPayload: 'Покупка 1490 ₽ Пятёрочка',
          notificationKey: 'notification-repeat-$index',
          packageName: 'ru.sberbankmobile',
          transaction: seed(
            date: date.add(Duration(minutes: index * 5)),
            providerId: 'notification-repeat-$index',
          ),
        ),
      );
    }

    expect(synoball.transactions, hasLength(2));
    expect(synoball.state.evidence, hasLength(2));
  });

  test('same amount and time with another merchant is not a duplicate', () {
    final synoball = core();
    final date = DateTime(2026, 8, 12, 12);
    synoball.ingest(
      AndroidNotificationAdapter(),
      AndroidNotificationInput(
        entityId: entityId,
        receivedAt: date,
        rawPayload: 'Покупка 1490 ₽ Пятёрочка',
        notificationKey: 'notification-merchant-a',
        packageName: 'ru.sberbankmobile',
        transaction: seed(date: date, providerId: 'notification-merchant-a'),
      ),
    );
    final receipt = synoball.ingest(
      ReceiptAdapter(),
      ReceiptInput(
        entityId: entityId,
        receivedAt: date.add(const Duration(minutes: 3)),
        rawPayload: 'receipt-magnit',
        transaction: seed(
          date: date.add(const Duration(minutes: 3)),
          merchant: 'Магнит',
          providerId: 'fiscal-magnit',
          receiptId: 'receipt-magnit',
        ),
        fiscalFingerprint: 'fiscal-magnit',
        rawText: 'Магнит 1490 ₽',
        merchant: 'Магнит',
      ),
    );

    expect(receipt.createdTransactionIds, hasLength(1));
    expect(synoball.transactions, hasLength(2));
  });

  test('one notification can match only one row from a statement', () {
    final synoball = core();
    final date = DateTime(2026, 8, 12, 10);
    synoball.ingest(
      AndroidNotificationAdapter(),
      AndroidNotificationInput(
        entityId: entityId,
        receivedAt: date,
        rawPayload: 'Покупка 1490 ₽ Пятёрочка',
        notificationKey: 'notification-one-to-one',
        packageName: 'ru.sberbankmobile',
        transaction: seed(date: date, providerId: 'notification-one-to-one'),
      ),
    );
    final statement = synoball.ingest(
      StatementAdapter(),
      StatementInput(
        entityId: entityId,
        receivedAt: date.add(const Duration(days: 1)),
        rawPayload: 'two equal rows',
        batchName: 'Statement',
        account: const SynoballAccount(
          id: 'acc-sber',
          entityId: entityId,
          name: 'Сбер',
          type: SynoballAccountType.card,
          currency: 'RUB',
          balance: Money(minorUnits: 0, currency: 'RUB'),
        ),
        transactions: [
          seed(
            date: date,
            accountId: 'acc-sber',
            providerId: 'statement-row-1',
          ),
          seed(
            date: date.add(const Duration(minutes: 5)),
            accountId: 'acc-sber',
            providerId: 'statement-row-2',
          ),
        ],
      ),
    );

    expect(statement.matchedTransactionIds, hasLength(1));
    expect(statement.createdTransactionIds, hasLength(1));
    expect(synoball.transactions, hasLength(2));
  });

  test('statement enriches account but keeps precise receipt time', () {
    final synoball = core();
    final purchaseTime = DateTime(2026, 8, 12, 12, 34);
    synoball.ingest(
      ReceiptAdapter(),
      ReceiptInput(
        entityId: entityId,
        receivedAt: purchaseTime,
        rawPayload: 'receipt',
        transaction: seed(
          date: purchaseTime,
          providerId: 'fiscal-time',
          receiptId: 'receipt-time',
        ),
        fiscalFingerprint: 'fiscal-time',
        rawText: 'Пятёрочка 1490 ₽',
        merchant: 'Пятёрочка',
      ),
    );
    final statement = synoball.ingest(
      StatementAdapter(),
      StatementInput(
        entityId: entityId,
        receivedAt: purchaseTime.add(const Duration(days: 1)),
        rawPayload: 'statement',
        batchName: 'Statement',
        account: const SynoballAccount(
          id: 'acc-sber',
          entityId: entityId,
          name: 'Сбер',
          type: SynoballAccountType.card,
          currency: 'RUB',
          balance: Money(minorUnits: 0, currency: 'RUB'),
        ),
        transactions: [
          seed(
            date: DateTime(2026, 8, 12),
            accountId: 'acc-sber',
            merchant: 'PYATEROCHKA MOSCOW',
            providerId: 'statement-time',
          ),
        ],
      ),
    );

    expect(statement.matchedTransactionIds, hasLength(1));
    expect(synoball.transactions.single.occurredAt, purchaseTime);
    expect(synoball.transactions.single.accountId, 'acc-sber');
    expect(synoball.transactions.single.merchantName, 'Пятёрочка');
  });

  test(
    'three monthly payments create a recurring stream and expected event',
    () {
      final synoball = core();
      for (final date in [
        DateTime(2026, 6, 5),
        DateTime(2026, 7, 5),
        DateTime(2026, 8, 5),
      ]) {
        synoball.ingest(
          ManualInputAdapter(),
          ManualInput(
            entityId: entityId,
            receivedAt: date,
            rawPayload: 'Яндекс Плюс 399 ₽',
            transaction: seed(
              date: date,
              amountMinor: 39900,
              merchant: 'Яндекс Плюс',
              providerId: date.toIso8601String(),
            ),
          ),
        );
      }

      expect(synoball.state.recurringStreams, hasLength(1));
      final stream = synoball.state.recurringStreams.single;
      expect(stream.frequency, RecurrenceFrequency.monthly);
      expect(stream.nextExpectedAt, DateTime(2026, 9, 5));
      expect(synoball.transactions.every((item) => item.isRecurring), isTrue);
    },
  );

  test(
    'derived refresh does not modify an unrelated transaction timestamp',
    () async {
      final synoball = core();
      synoball.ingest(
        ManualInputAdapter(),
        ManualInput(
          entityId: entityId,
          receivedAt: DateTime(2026, 7, 1),
          rawPayload: 'Первая покупка',
          transaction: seed(
            date: DateTime(2026, 7, 1),
            merchant: 'Первый магазин',
          ),
        ),
      );
      final originalUpdatedAt = synoball.transactions.single.updatedAt;
      await Future<void>.delayed(const Duration(milliseconds: 2));

      synoball.ingest(
        ManualInputAdapter(),
        ManualInput(
          entityId: entityId,
          receivedAt: DateTime(2026, 7, 2),
          rawPayload: 'Вторая покупка',
          transaction: seed(
            date: DateTime(2026, 7, 2),
            merchant: 'Второй магазин',
          ),
        ),
      );

      expect(synoball.transactions.first.updatedAt, originalUpdatedAt);
    },
  );

  test('recurring flags are cleared when the sequence becomes incomplete', () {
    final synoball = core();
    for (final date in [
      DateTime(2026, 6, 5),
      DateTime(2026, 7, 5),
      DateTime(2026, 8, 5),
    ]) {
      synoball.ingest(
        ManualInputAdapter(),
        ManualInput(
          entityId: entityId,
          receivedAt: date,
          rawPayload: 'Подписка 399 ₽',
          transaction: seed(
            date: date,
            amountMinor: 39900,
            merchant: 'Подписка',
          ),
        ),
      );
    }
    final lastTransactionId = synoball.transactions.last.id;
    expect(synoball.transactions.every((item) => item.isRecurring), isTrue);

    synoball.deleteTransaction(lastTransactionId, actorId: 'ivan');

    expect(synoball.state.recurringStreams, isEmpty);
    expect(synoball.transactions.every((item) => !item.isRecurring), isTrue);
    expect(
      synoball.transactions.every((item) => item.recurringStreamId == null),
      isTrue,
    );
  });

  test('recurring streams are isolated between entities', () {
    final synoball = core();
    const secondEntityId = 'ent-maria';
    const secondAccountId = 'acc-maria';
    synoball.upsertEntity(
      const SynoballEntity(
        id: secondEntityId,
        type: SynoballEntityType.person,
        displayName: 'Мария',
      ),
    );
    synoball.upsertAccount(
      const SynoballAccount(
        id: secondAccountId,
        entityId: secondEntityId,
        name: 'Счёт Марии',
        type: SynoballAccountType.card,
        currency: 'RUB',
        balance: Money(minorUnits: 0, currency: 'RUB'),
      ),
    );

    for (final entity in [
      (id: entityId, accountId: cashAccount),
      (id: secondEntityId, accountId: secondAccountId),
    ]) {
      for (final date in [
        DateTime(2026, 6, 5),
        DateTime(2026, 7, 5),
        DateTime(2026, 8, 5),
      ]) {
        synoball.ingest(
          ManualInputAdapter(),
          ManualInput(
            entityId: entity.id,
            receivedAt: date,
            rawPayload: 'Общая подписка 399 ₽',
            transaction: seed(
              date: date,
              accountId: entity.accountId,
              amountMinor: 39900,
              merchant: 'Общая подписка',
            ),
          ),
        );
      }
    }

    expect(synoball.state.recurringStreams, hasLength(2));
    expect(
      synoball.state.recurringStreams.map((item) => item.entityId).toSet(),
      {entityId, secondEntityId},
    );
    expect(
      synoball.state.recurringStreams.every(
        (stream) => stream.transactionIds.every(
          (id) => synoball.transactionById(id)!.entityId == stream.entityId,
        ),
      ),
      isTrue,
    );
  });

  test('voice input remains a candidate until user confirmation', () {
    final synoball = core();
    final outcome = synoball.ingest(
      VoiceInputAdapter(),
      VoiceInput(
        entityId: entityId,
        receivedAt: DateTime(2026, 8, 12),
        rawPayload: 'Запиши вчера 700 рублей на такси',
        transcript: 'Запиши вчера 700 рублей на такси',
        transaction: seed(
          date: DateTime(2026, 8, 11),
          amountMinor: 70000,
          merchant: 'Такси',
        ),
      ),
    );

    expect(outcome.pendingCandidateIds, hasLength(1));
    expect(synoball.transactions, isEmpty);
    synoball.confirmCandidate(
      outcome.pendingCandidateIds.single,
      actorId: 'ivan',
    );
    expect(synoball.transactions, hasLength(1));
    expect(synoball.transactions.single.amount.minorUnits, 70000);
    expect(synoball.state.auditEntries.single.action, 'candidate.confirmed');
  });

  test('statement import enriches existing notification records', () {
    final synoball = core();
    final dates = [DateTime(2026, 8, 10, 10), DateTime(2026, 8, 11, 11)];
    for (var index = 0; index < dates.length; index++) {
      synoball.ingest(
        AndroidNotificationAdapter(),
        AndroidNotificationInput(
          entityId: entityId,
          receivedAt: dates[index],
          rawPayload: 'Покупка ${index + 1}',
          notificationKey: 'notification-$index',
          packageName: 'ru.sberbankmobile',
          transaction: seed(
            date: dates[index],
            amountMinor: 100000 + index * 10000,
            merchant: 'Магазин $index',
          ),
        ),
      );
    }
    final outcome = synoball.ingest(
      StatementAdapter(),
      StatementInput(
        entityId: entityId,
        receivedAt: DateTime(2026, 8, 12),
        rawPayload: 'statement raw data',
        batchName: 'August statement',
        account: const SynoballAccount(
          id: 'acc-bank',
          entityId: entityId,
          name: 'Bank',
          type: SynoballAccountType.card,
          currency: 'RUB',
          balance: Money(minorUnits: 1000000, currency: 'RUB'),
        ),
        transactions: [
          seed(
            date: dates[0],
            amountMinor: 100000,
            accountId: 'acc-bank',
            merchant: 'Магазин 0',
            providerId: 'bank-0',
          ),
          seed(
            date: dates[1],
            amountMinor: 110000,
            accountId: 'acc-bank',
            merchant: 'Магазин 1',
            providerId: 'bank-1',
          ),
          seed(
            date: DateTime(2026, 8, 12, 12),
            amountMinor: 120000,
            accountId: 'acc-bank',
            merchant: 'Магазин 2',
            providerId: 'bank-2',
          ),
        ],
      ),
    );

    expect(
      outcome.matchedTransactionIds,
      hasLength(2),
      reason:
          'created=${outcome.createdTransactionIds}, matched=${outcome.matchedTransactionIds}',
    );
    expect(outcome.createdTransactionIds, hasLength(1));
    expect(synoball.transactions, hasLength(3));
    expect(synoball.state.importBatches.single.matchedTransactions, 2);
  });

  test('financial state is derived and AI receives only relevant facts', () {
    final synoball = core();
    synoball.ingest(
      ManualInputAdapter(),
      ManualInput(
        entityId: entityId,
        receivedAt: DateTime(2026, 8, 1),
        rawPayload: 'Зарплата 130000',
        transaction: TransactionSeed(
          accountId: cashAccount,
          amount: const Money(minorUnits: 13000000, currency: 'RUB'),
          direction: FinancialDirection.inflow,
          occurredAt: DateTime(2026, 8, 1),
          description: 'Зарплата',
          merchant: 'Работодатель',
          category: 'income',
          confidence: 1,
        ),
      ),
    );
    synoball.ingest(
      ManualInputAdapter(),
      ManualInput(
        entityId: entityId,
        receivedAt: DateTime(2026, 8, 2),
        rawPayload: 'Расход 56000',
        transaction: seed(
          date: DateTime(2026, 8, 2),
          amountMinor: 5600000,
          merchant: 'Расходы',
        ),
      ),
    );

    final state = const FinancialStateService().calculate(
      state: synoball.state,
      entityId: entityId,
      asOf: DateTime(2026, 8, 12),
      plannedExpensesMinor: 1000000,
    );
    expect(state.monthlyIncome.minorUnits, 13000000);
    expect(state.monthlyExpenses.minorUnits, 5600000);
    expect(state.freeCashflow.minorUnits, 6400000);
    expect(state.liquidMoney.minorUnits, 19000000);

    final context = const AiContextService().build(
      purpose: AiContextPurpose.purchaseDecision,
      state: state,
      proposedPurchaseMinor: 6000000,
    );
    expect(context.facts['monthlyIncome'], '130000.00');
    expect(context.facts['proposedPurchase'], '60000.00');
    expect(context.toJson().toString(), isNot(contains('transactions')));
  });

  test('mock CBR adapter keeps canonical schema independent', () {
    final synoball = core();
    final fixture = File(
      'test/fixtures/cbr_open_finance_v1.json',
    ).readAsStringSync();
    final input = const CbrOpenFinanceFixtureParser().parse(
      entityId: entityId,
      receivedAt: DateTime(2026, 8, 12),
      source: fixture,
    );
    synoball.ingest(CbrOpenFinanceAdapter(), input);

    expect(synoball.state.connections.single.adapterVersion, 'mock-1.0.0');
    expect(synoball.transactions.single.amount.value, '1490.00');
    expect(
      synoball.state.evidence.single.sourceType,
      SynoballSourceType.regulatedApi,
    );
  });

  test('Synoball raw, canonical and evidence survive Qesto persistence', () {
    final synoball = core();
    synoball.ingest(
      ManualInputAdapter(),
      ManualInput(
        entityId: entityId,
        receivedAt: DateTime(2026, 8, 12),
        rawPayload: 'Оригинальная ручная запись',
        transaction: seed(date: DateTime(2026, 8, 12)),
      ),
    );
    final document = UserFinancialData(
      user: const QestoUser(id: 'ivan', name: 'Иван', defaultCurrency: 'RUB'),
      referenceDate: DateTime(2026, 8, 12),
      synoballState: synoball.state,
    );

    const codec = UserFinancialDataCodec();
    final restored = codec.decode(codec.encode(document)).synoballState!;
    expect(restored.rawPayloads.single.body, 'Оригинальная ручная запись');
    expect(restored.transactions.single.amount.value, '1490.00');
    expect(
      restored.evidence.single.transactionId,
      restored.transactions.single.id,
    );
  });
}
