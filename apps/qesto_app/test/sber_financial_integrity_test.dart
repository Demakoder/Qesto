import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_extractors.dart';
import 'package:qesto/features/budget/services/cash_flow_calculation_service.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

final _from = DateTime(2026, 8);
final _to = DateTime(2026, 9);
final _range = SberSyncRange(from: _from, toExclusive: _to, label: 'Test');

SberAccountFact _account(String id, String suffix, {int balance = 100}) =>
    SberAccountFact(
      id: id,
      name: 'Платёжный счёт •• $suffix',
      lastFour: suffix,
      type: AccountType.bankCard,
      currency: 'RUB',
      balance: balance,
    );

BudgetController _controller({List<QestoAccount> accounts = const []}) {
  final controller = BudgetController(
    configuration: budgetConfiguration,
    financialData: UserFinancialData(
      user: const QestoUser(id: 'test', name: 'Test', defaultCurrency: 'RUB'),
      referenceDate: _from,
      accounts: accounts,
    ),
  );
  addTearDown(controller.dispose);
  return controller;
}

SberTransactionFact _transaction(
  String id, {
  String accountId = '',
  String currency = 'RUB',
}) => SberTransactionFact(
  sourceId: id,
  accountId: accountId,
  date: _from,
  amount: 10,
  exactAmountMinor: 1025,
  currency: currency,
  description: 'Покупка',
  status: 'POSTED',
  fingerprint: id,
);

SberSyncSnapshot _snapshot({
  List<SberAccountFact> accounts = const [],
  List<SberTransactionFact> transactions = const [],
}) => SberSyncSnapshot(
  observedAt: _to,
  accounts: accounts,
  transactions: transactions,
  oldestTransaction: _from,
  newestTransaction: _from,
  pendingCount: 0,
  pageType: SberPageType.transactions,
);

void main() {
  test('account identity uses its own label, not a linked card suffix', () {
    final accounts = const SberExtractors().normalizeAccountRows([
      {
        'id': 'own-account',
        'kind': 'account',
        'name': 'Платёжный счёт 2020',
        'identityText': 'Платёжный счёт 2020. Баланс 123,45 руб.',
        'text': 'Карта •• 1111 Платёжный счёт 2020 123,45 ₽',
        'balance': '123,45 ₽',
        'cards': ['1111'],
      },
    ]);
    expect(accounts.single.lastFour, '2020');
    expect(accounts.single.type, AccountType.cash);
    expect(accounts.single.balanceMinor, 12345);
  });

  test(
    'no new transactions is valid only with observed excluded rows and complete history',
    () {
      const empty = SberTransactionExtraction(
        rawRowsSeen: 2,
        outsidePeriodRows: 1,
        rewardRows: 1,
      );
      expect(empty.hasVerifiedEmptyHistory, isTrue);
      expect(
        const SberTransactionExtraction().hasVerifiedEmptyHistory,
        isFalse,
      );
      expect(
        const SberTransactionExtraction(
          rawRowsSeen: 2,
          outsidePeriodRows: 1,
          rejectedRows: 1,
        ).hasVerifiedEmptyHistory,
        isFalse,
      );
      expect(
        const SberTransactionExtraction(
          rawRowsSeen: 2,
          outsidePeriodRows: 2,
          hasMoreRows: true,
        ).hasVerifiedEmptyHistory,
        isFalse,
      );
    },
  );

  test('account ambiguity is not mislabeled as a pagination error', () {
    const report = SberSyncReport(state: SberConnectorState.syncComplete);
    const summary = SberImportSummary(
      found: 1,
      newCount: 1,
      updatedCount: 0,
      unchangedCount: 0,
      accountsFound: 3,
      accountsUpdated: 3,
      unassignedAccountCount: 1,
    );
    expect(report.importFailureReason(summary), 'ACCOUNT_MAPPING_UNRESOLVED');
  });
  test(
    'a separate fee for an internal transfer is an external debit',
    () async {
      final transaction = const SberExtractors().normalizeTransactionRows([
        {
          'id': 'internal-fee',
          'text': 'Комиссия за перевод между своими счетами 10,25 ₽',
          'operationType': 'Комиссия за перевод между своими счетами',
          'amount': '10,25 ₽',
          'dateIso': '2026-08-01',
        },
      ], range: _range).single;
      expect(transaction.isInternalTransfer, isFalse);
      expect(transaction.isIncome, isFalse);
      final controller = _controller();
      await controller.importSberSnapshot(
        _snapshot(transactions: [transaction]),
      );
      expect(
        const CashFlowCalculationService()
            .calculate(
              transactions: controller.transactions,
              from: _from,
              toExclusive: _to,
            )
            .netCashFlowMinor,
        -1025,
      );
    },
  );
  for (final reverse in [false, true]) {
    test(
      'linked product preserves account balance and card route (reverse=$reverse)',
      () async {
        final rows = <Map<String, dynamic>>[
          {
            'id': 'payment-route',
            'name': 'Платёжный счёт',
            'kind': 'account',
            'text': 'Платёжный счёт •• 9000 100,25 ₽',
            'balance': '100,25 ₽',
            'cards': ['1234'],
          },
          {
            'id': 'card-route',
            'name': 'СберКарта',
            'kind': 'card',
            'text': 'СберКарта •• 1234 80,25 ₽',
            'balance': '80,25 ₽',
          },
        ];
        final products = const SberExtractors().normalizeAccountRows(
          reverse ? rows.reversed : rows,
        );
        expect(products, hasLength(1));
        expect(products.single.balanceMinor, 10025);
        expect(products.single.linkedCardLastFours, isNot(contains('9000')));
        final transaction = const SberExtractors().normalizeTransactionRows([
          {
            'id': 'buy',
            'account': 'card-route',
            'dateIso': '2026-08-01',
            'text': 'Магазин 10,25 ₽',
            'amount': '10,25 ₽',
          },
        ], range: _range).single;
        final controller = _controller();
        final summary = await controller.importSberSnapshot(
          _snapshot(accounts: products, transactions: [transaction]),
        );
        expect(controller.transactions.single.accountId, products.single.id);
        expect(summary.unassignedAccountCount, 0);
        expect(controller.accounts.single.balanceMinor, 10025);
      },
    );
  }
  test(
    'history product reference has the same identity as account extraction',
    () {
      const parser = SberExtractors();
      final products = parser.normalizeAccountRows([
        {
          'id': 'provider-product-1',
          'name': 'Платёжный счёт',
          'text': 'Платёжный счёт •• 1234 100,00 ₽',
          'balance': '100,00 ₽',
        },
      ]);
      final rows = parser.normalizeTransactionRows([
        {
          'id': 'purchase-1',
          'account': 'provider-product-1',
          'text': 'Магазин 10,25 ₽ Оплата товаров и услуг',
          'amount': '10,25 ₽',
          'dateIso': '2026-08-01',
        },
      ], range: _range);
      expect(rows.single.accountId, products.single.id);
    },
  );

  test(
    'absent products refresh preserves an explicitly known existing account',
    () async {
      final controller = _controller();
      await controller.importSberSnapshot(
        _snapshot(
          accounts: [
            _account('sber-account-a', '1111'),
            _account('sber-account-b', '2222'),
          ],
        ),
      );
      await controller.importSberSnapshot(
        _snapshot(
          transactions: [
            _transaction('purchase-b', accountId: 'sber-account-b'),
          ],
        ),
      );
      expect(controller.transactions.single.accountId, 'sber-account-b');
    },
  );

  test('unknown Sber account is never assigned to an unrelated bank', () async {
    final controller = _controller(
      accounts: const [
        QestoAccount(
          id: 'another-bank',
          userId: 'test',
          title: 'Т-Банк •• 1234',
          balance: 500,
          currency: 'RUB',
          type: AccountType.bankCard,
        ),
      ],
    );
    await controller.importSberSnapshot(
      _snapshot(transactions: [_transaction('unknown')]),
    );
    expect(controller.transactions.single.accountId, isNot('another-bank'));
    expect(
      controller.transactions.single.tags,
      contains('sber-account-unresolved'),
    );
    final flow = const CashFlowCalculationService().calculate(
      transactions: controller.transactions,
      from: _from,
      toExclusive: _to,
      currency: 'RUB',
    );
    expect(
      flow.netCashFlowMinor,
      -1025,
      reason: 'Known money is retained even when its account is unknown',
    );
    expect(
      controller.accounts.firstWhere((a) => a.id == 'another-bank').balance,
      500,
    );
  });

  test(
    'same display name does not overwrite a different known account',
    () async {
      final controller = _controller();
      await controller.importSberSnapshot(
        _snapshot(accounts: [_account('sber-account-a', '1111')]),
      );
      await controller.importSberSnapshot(
        _snapshot(accounts: [_account('sber-account-b', '2222', balance: 250)]),
      );
      expect(
        controller.accounts.where((a) => a.id.startsWith('sber-account-')),
        hasLength(2),
      );
      expect(
        controller.accounts.firstWhere((a) => a.id == 'sber-account-a').balance,
        100,
      );
    },
  );

  test(
    'same last four does not prove that two bank products are identical',
    () async {
      final controller = _controller();
      await controller.importSberSnapshot(
        _snapshot(accounts: [_account('sber-account-a', '1111')]),
      );
      await controller.importSberSnapshot(
        _snapshot(accounts: [_account('sber-account-b', '1111', balance: 250)]),
      );
      expect(
        controller.accounts.where((a) => a.id.startsWith('sber-account-')),
        hasLength(2),
      );
    },
  );

  test(
    'currency mismatch cannot attach a USD operation to a RUB account',
    () async {
      final controller = _controller();
      await controller.importSberSnapshot(
        _snapshot(
          accounts: [_account('sber-account-a', '1111')],
          transactions: [
            _transaction('usd', accountId: 'sber-account-a', currency: 'USD'),
          ],
        ),
      );
      final transaction = controller.transactions.single;
      expect(transaction.accountId, isNot('sber-account-a'));
      expect(
        controller.accounts
            .firstWhere((a) => a.id == transaction.accountId)
            .currency,
        'USD',
      );
    },
  );

  test('explicit debit sign wins over misleading merchant income words', () {
    final transaction = const SberExtractors().normalizeTransactionRows([
      {
        'id': 'fee',
        'text': 'Комиссия за входящий перевод -10,25 ₽',
        'amount': '-10,25 ₽',
        'dateIso': '2026-08-01',
        'merchant': 'Комиссия за входящий перевод',
        'operationType': 'Комиссия',
      },
    ], range: _range).single;
    expect(transaction.isIncome, isFalse);
    expect(transaction.amountMinor, 1025);
    expect(transaction.isInternalTransfer, isFalse);
  });

  test(
    'explicit credit refund is different from a cancelled unpaid purchase',
    () {
      final rows = const SberExtractors().normalizeTransactionRows([
        {
          'id': 'cancelled',
          'text': 'Магазин 100 ₽ Операция отменена',
          'amount': '100 ₽',
          'dateIso': '2026-08-01',
          'operationType': 'Операция отменена',
        },
        {
          'id': 'refund',
          'text': 'Магазин +32 ₽ Возврат, отмена операций',
          'amount': '+32 ₽',
          'dateIso': '2026-08-02',
          'operationType': 'Возврат, отмена операций',
        },
      ], range: _range);
      expect(
        rows.firstWhere((r) => r.sourceId == 'cancelled').status,
        'CANCELLED',
      );
      expect(rows.firstWhere((r) => r.sourceId == 'refund').status, 'REFUND');
      expect(rows.firstWhere((r) => r.sourceId == 'refund').isIncome, isTrue);
    },
  );
}
