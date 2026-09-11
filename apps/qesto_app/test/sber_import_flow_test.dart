import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';
import 'package:qesto/features/budget/services/cash_flow_calculation_service.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

void main() {
  BudgetController controllerWith(BudgetTransaction transaction) =>
      BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'user',
            name: 'Пользователь',
            defaultCurrency: 'RUB',
          ),
          referenceDate: DateTime(2026, 8, 31),
          transactions: [transaction],
        ),
      );

  BudgetTransaction existing({
    List<String> tags = const ['sberbank'],
    String currency = 'RUB',
  }) => BudgetTransaction(
    id: 'sber-stable-fingerprint',
    userId: 'user',
    accountId: 'local-default-account',
    date: DateTime(2026, 8, 20),
    amount: 83,
    currency: currency,
    type: TransactionType.expense,
    categoryId: 'other',
    merchant: '+6',
    title: '+6',
    description: '+6 83 ₽ Оплата товаров и услуг',
    tags: tags,
  );

  SberSyncSnapshot snapshot({
    String sourceId = 'source',
    String? connectionId,
    String merchant = 'Scooters',
    String fingerprint = 'stable-fingerprint',
    bool isIncome = false,
    bool isTransfer = false,
    bool isInternalTransfer = false,
    String status = 'POSTED',
    int? exactAmountMinor,
  }) => SberSyncSnapshot(
    connectionId: connectionId,
    observedAt: DateTime(2026, 8, 31),
    accounts: const [],
    transactions: [
      SberTransactionFact(
        sourceId: sourceId,
        accountId: '',
        date: DateTime(2026, 8, 20),
        amount: 83,
        exactAmountMinor: exactAmountMinor,
        currency: 'RUB',
        description: '$merchant · Оплата товаров и услуг',
        merchant: merchant,
        operationType: 'Оплата товаров и услуг',
        status: status,
        fingerprint: fingerprint,
        isIncome: isIncome,
        isTransfer: isTransfer,
        isInternalTransfer: isInternalTransfer,
      ),
    ],
    oldestTransaction: DateTime(2026, 8, 20),
    newestTransaction: DateTime(2026, 8, 20),
    pendingCount: 0,
    pageType: SberPageType.transactions,
  );

  test(
    'provider identity survives changing text and presentation fingerprint',
    () async {
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'user',
            name: 'Test',
            defaultCurrency: 'RUB',
          ),
          referenceDate: DateTime(2026, 8, 31),
        ),
      );
      await controller.importSberSnapshot(snapshot(connectionId: 'profile-a'));
      final result = await controller.importSberSnapshot(
        snapshot(
          connectionId: 'profile-a',
          fingerprint: 'changed-render',
          merchant: 'New bank name',
        ),
      );
      expect(controller.transactions, hasLength(1));
      expect(result.newCount, 0);
      expect(controller.transactions.single.merchant, 'New bank name');
    },
  );

  test(
    'different real provider ids are not merged by equal display facts',
    () async {
      final controller = controllerWith(existing());
      await controller.importSberSnapshot(snapshot(connectionId: 'profile-a'));
      await controller.importSberSnapshot(
        snapshot(
          connectionId: 'profile-a',
          sourceId: 'second-purchase',
          fingerprint: 'another-fingerprint',
        ),
      );
      expect(controller.transactions, hasLength(2));
    },
  );

  test(
    'two browser profiles isolate otherwise identical bank identities',
    () async {
      final controller = controllerWith(existing());
      await controller.importSberSnapshot(snapshot(connectionId: 'profile-a'));
      final result = await controller.importSberSnapshot(
        snapshot(connectionId: 'profile-b'),
      );
      expect(controller.transactions, hasLength(2));
      expect(result.newCount, 1);
    },
  );

  test(
    'review result is not reported as an accepted or unchanged transaction',
    () async {
      final controller = controllerWith(existing(currency: 'USD'));

      final result = await controller.importSberSnapshot(snapshot());

      expect(result.found, 1);
      expect(result.newCount, 0);
      expect(result.updatedCount, 0);
      expect(result.unchangedCount, 0);
      expect(result.unresolvedCount, 1);
      expect(result.transactions.single.change, SberImportChange.needsReview);
      expect(controller.transactions.single.currency, 'USD');
      expect(controller.pendingCandidates, hasLength(1));
    },
  );

  test(
    'Sber replay reports a deleted identity separately and never restores it',
    () async {
      final controller = controllerWith(existing());
      await controller.importSberSnapshot(snapshot());
      final id = controller.transactions.single.id;
      await controller.deleteTransaction(id);
      final result = await controller.importSberSnapshot(snapshot());
      expect(result.deletedCount, 1);
      expect(result.newCount, 0);
      expect(result.updatedCount, 0);
      expect(result.unresolvedCount, 0);
      expect(result.transactions.single.change, SberImportChange.deleted);
      expect(controller.transactions, isEmpty);
      await controller.restoreTrashedTransactions([id]);
      expect(controller.transactions.single.id, id);
    },
  );

  test('sync report compares saved cents instead of rounded labels', () async {
    final controller = BudgetController(
      configuration: budgetConfiguration,
      financialData: UserFinancialData(
        user: const QestoUser(id: 'user', name: 'Test', defaultCurrency: 'RUB'),
        referenceDate: DateTime(2026, 8, 31),
      ),
    );
    await controller.importSberSnapshot(snapshot(exactAmountMinor: 8325));
    final result = await controller.importSberSnapshot(
      snapshot(exactAmountMinor: 8326),
    );
    expect(result.newCount, 0);
    expect(result.updatedCount, 1);
    expect(result.transactions.single.change, SberImportChange.updated);
    expect(controller.transactions.single.amountMinor, 8326);
    final repeated = await controller.importSberSnapshot(
      snapshot(exactAmountMinor: 8326),
    );
    expect(repeated.updatedCount, 0);
    expect(repeated.unchangedCount, 1);
  });

  test(
    'structured internal-transfer semantics survive a shortened display title and reload',
    () async {
      final data = UserFinancialData(
        user: const QestoUser(id: 'user', name: 'Test', defaultCurrency: 'RUB'),
        referenceDate: DateTime(2026, 8, 31),
      );
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: data,
      );
      addTearDown(controller.dispose);
      // The bank row stated "между своими", but its display title only names the product.
      final value = snapshot(
        merchant: 'Платёжный счёт',
        isTransfer: true,
        isInternalTransfer: true,
        exactAmountMinor: 8325,
      );
      await controller.importSberSnapshot(value);
      final transfer = controller.transactions.single;
      expect(transfer.type, TransactionType.transfer);
      expect(transfer.tags, contains(qestoInternalTransferTag));
      final flow = const CashFlowCalculationService().calculate(
        transactions: controller.transactions,
        from: DateTime(2026, 8),
        toExclusive: DateTime(2026, 9),
      );
      expect(flow.netCashFlowMinor, 0);
      final restored = BudgetController(
        configuration: budgetConfiguration,
        financialData: controller.mergeInto(data),
      );
      addTearDown(restored.dispose);
      expect(
        restored.transactions.single.tags,
        contains(qestoInternalTransferTag),
      );
      expect(restored.transactions.single.type, TransactionType.transfer);
      final replay = await restored.importSberSnapshot(value);
      expect(replay.newCount, 0);
      expect(
        restored.transactions.single.tags,
        contains(qestoInternalTransferTag),
      );
    },
  );

  test(
    'sync report shows protected canonical fields, not source proposals',
    () async {
      final controller = controllerWith(existing());
      final result = await controller.importSberSnapshot(snapshot());
      expect(result.recategorizedCount, 0);
      expect(result.transactions.single.title, '+6');
      expect(controller.transactions.single.categoryId, 'other');
      final repeated = await controller.importSberSnapshot(snapshot());
      expect(repeated.updatedCount, 0);
      expect(repeated.unchangedCount, 1);
    },
  );

  test(
    'new automatic sync repairs merchant and category without a duplicate',
    () async {
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'user',
            name: 'Test',
            defaultCurrency: 'RUB',
          ),
          referenceDate: DateTime(2026, 8, 31),
        ),
      );
      await controller.importSberSnapshot(snapshot(merchant: '+6'));

      final result = await controller.importSberSnapshot(snapshot());

      expect(controller.transactions, hasLength(1));
      expect(controller.transactions.single.merchant, 'Scooters');
      expect(controller.transactions.single.categoryId, 'transport');
      expect(result.newCount, 0);
      expect(result.updatedCount, 1);
      expect(result.recategorizedCount, 1);
    },
  );

  test(
    'provider id upgrade replaces an ordinal id without a duplicate',
    () async {
      final legacy =
          existing(
            tags: const ['sberbank', 'sber-live', qestoAutoCategoryTag],
          ).copyWith(
            merchant: 'Scooters',
            title: 'Scooters',
            description: 'Scooters · Оплата товаров и услуг',
          );
      final controller = controllerWith(legacy);
      final upgraded = snapshot(fingerprint: 'provider-document-id');

      final first = await controller.importSberSnapshot(upgraded);
      final second = await controller.importSberSnapshot(upgraded);

      expect(controller.transactions, hasLength(1));
      expect(controller.transactions.single.id, legacy.id);
      expect(first.newCount, 0);
      expect(second.newCount, 0);
    },
  );

  test(
    'stored automatic Sber categories use the current adapter vocabulary',
    () {
      final controller = controllerWith(
        existing(tags: const ['sberbank', qestoAutoCategoryTag]).copyWith(
          merchant: 'KUPIBILET.RU город Санкт-Петербург RUS',
          title: 'KUPIBILET.RU город Санкт-Петербург RUS',
          description: 'Оплата по QR-коду СБП',
        ),
      );

      expect(controller.transactions.single.categoryId, 'travel');
      expect(controller.transactions.single.classificationConfidence, 0.94);
    },
  );

  test('stored person transfer cannot remain marked as internal', () {
    final controller = controllerWith(
      existing(tags: const ['sberbank', qestoInternalTransferTag]).copyWith(
        type: TransactionType.transfer,
        title: 'Дмитрий Аркадьевич Л.',
        description: 'Перевод по СБП Дмитрию Аркадьевичу Л.',
        transferDirection: TransferDirection.outgoing,
      ),
    );

    final transaction = controller.transactions.single;
    expect(transaction.type, TransactionType.expense);
    expect(transaction.tags, contains(qestoExternalTransferTag));
    expect(transaction.tags, isNot(contains(qestoInternalTransferTag)));
    expect(
      controller
          .cashFlowForRange(
            from: DateTime(2026, 8),
            toExclusive: DateTime(2026, 9),
          )
          .externalOutflows,
      83,
    );
  });

  test('manual category override survives adapter refresh', () async {
    final manual = existing(
      tags: const ['sberbank', qestoManualCategoryTag],
    ).copyWith(categoryId: 'fun');
    final controller = controllerWith(manual);

    await controller.importSberSnapshot(snapshot());

    expect(controller.transactions.single.categoryId, 'fun');
    expect(
      controller.transactions.single.tags,
      contains(qestoManualCategoryTag),
    );
  });

  test(
    'external and internal Sber transfers receive distinct semantics',
    () async {
      final controller = controllerWith(existing());
      final base = snapshot();
      final transferSnapshot = SberSyncSnapshot(
        observedAt: base.observedAt,
        accounts: const [],
        transactions: [
          SberTransactionFact(
            sourceId: 'incoming',
            accountId: '',
            date: DateTime(2026, 8, 21),
            amount: 10000,
            currency: 'RUB',
            description: 'Перевод от другого человека',
            status: 'POSTED',
            fingerprint: 'incoming',
            isIncome: true,
            isTransfer: true,
          ),
          SberTransactionFact(
            sourceId: 'outgoing',
            accountId: '',
            date: DateTime(2026, 8, 22),
            amount: 4000,
            currency: 'RUB',
            description: 'Перевод по СБП',
            status: 'POSTED',
            fingerprint: 'outgoing',
            isTransfer: true,
          ),
          SberTransactionFact(
            sourceId: 'internal',
            accountId: '',
            date: DateTime(2026, 8, 23),
            amount: 20000,
            currency: 'RUB',
            description: 'Перевод между своими счетами',
            status: 'POSTED',
            fingerprint: 'internal',
            isTransfer: true,
            isInternalTransfer: true,
          ),
        ],
        oldestTransaction: DateTime(2026, 8, 21),
        newestTransaction: DateTime(2026, 8, 23),
        pendingCount: 0,
        pageType: SberPageType.transactions,
      );

      await controller.importSberSnapshot(transferSnapshot);

      final incoming = controller.transactions.firstWhere(
        (item) => item.id == 'sber-incoming',
      );
      final outgoing = controller.transactions.firstWhere(
        (item) => item.id == 'sber-outgoing',
      );
      final internal = controller.transactions.firstWhere(
        (item) => item.id == 'sber-internal',
      );
      expect(incoming.type, TransactionType.income);
      expect(incoming.tags, contains(qestoExternalTransferTag));
      expect(outgoing.type, TransactionType.expense);
      expect(outgoing.tags, contains(qestoExternalTransferTag));
      expect(internal.type, TransactionType.transfer);
      expect(internal.tags, contains(qestoInternalTransferTag));
    },
  );

  test(
    'sync merges a linked card duplicate without losing operations',
    () async {
      const mainAccount = QestoAccount(
        id: 'sber-account-main',
        userId: 'user',
        title: 'Платёжный счёт · карта •• 1234',
        balance: 10000,
        currency: 'RUB',
        type: AccountType.bankCard,
      );
      const cardDuplicate = QestoAccount(
        id: 'sber-account-card',
        userId: 'user',
        title: 'СберКарта •• 1234',
        balance: 10000,
        currency: 'RUB',
        type: AccountType.bankCard,
      );
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'user',
            name: 'Пользователь',
            defaultCurrency: 'RUB',
          ),
          referenceDate: DateTime(2026, 8, 31),
          accounts: const [mainAccount, cardDuplicate],
          transactions: [
            BudgetTransaction(
              id: 'old-main-operation',
              userId: 'user',
              accountId: mainAccount.id,
              date: DateTime(2026, 8, 20),
              amount: 500,
              currency: 'RUB',
              type: TransactionType.expense,
              categoryId: 'other',
              merchant: 'Магазин 1',
            ),
            BudgetTransaction(
              id: 'old-card-operation',
              userId: 'user',
              accountId: cardDuplicate.id,
              date: DateTime(2026, 8, 21),
              amount: 700,
              currency: 'RUB',
              type: TransactionType.expense,
              categoryId: 'other',
              merchant: 'Магазин 2',
            ),
          ],
        ),
      );
      final result = await controller.importSberSnapshot(
        SberSyncSnapshot(
          observedAt: DateTime(2026, 8, 31),
          accounts: const [
            SberAccountFact(
              id: 'sber-account-new-route',
              name: 'Платёжный счёт',
              type: AccountType.bankCard,
              currency: 'RUB',
              balance: 10000,
              linkedCardLastFours: ['1234'],
            ),
          ],
          transactions: const [],
          oldestTransaction: null,
          newestTransaction: null,
          pendingCount: 0,
          pageType: SberPageType.accounts,
        ),
      );

      expect(result.accountsMerged, 1);
      expect(controller.accounts, hasLength(1));
      expect(controller.accounts.single.balance, 10000);
      expect(controller.transactions.map((item) => item.accountId).toSet(), {
        controller.accounts.single.id,
      });
      expect(controller.transactions, hasLength(2));
    },
  );
}
