import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

void main() {
  final date = DateTime(2026, 9, 8);
  BudgetController engine() => BudgetController(
    configuration: budgetConfiguration,
    financialData: UserFinancialData(
      user: const QestoUser(id: 'user', name: 'Test', defaultCurrency: 'RUB'),
      referenceDate: date,
    ),
  );
  SberSyncSnapshot snapshot(
    String profile, {
    bool product = true,
    bool explicitReference = false,
  }) => SberSyncSnapshot(
    connectionId: profile,
    observedAt: date,
    accounts: product
        ? [
            const SberAccountFact(
              id: 'sber-account-bank-product',
              name: 'Сбер •• 1234',
              type: AccountType.bankCard,
              currency: 'RUB',
              balance: 100,
              exactBalanceMinor: 10025,
            ),
          ]
        : [],
    transactions: [
      SberTransactionFact(
        sourceId: 'bank-operation',
        accountId: product || explicitReference
            ? 'sber-account-bank-product'
            : '',
        date: date,
        amount: 20,
        exactAmountMinor: 2025,
        currency: 'RUB',
        description: 'Shop',
        merchant: 'Shop',
        status: 'POSTED',
        fingerprint: 'display-fingerprint',
      ),
    ],
    oldestTransaction: date,
    newestTransaction: date,
    pendingCount: 0,
    pageType: SberPageType.transactions,
  );

  test(
    'PDF and web merge on a confirmed account without changing current balance',
    () async {
      final core = engine();
      await core.importSberSnapshot(snapshot('p1'));
      final account = core.accounts.single;
      final result = await core.importStatement(
        account: account,
        transactions: [
          BudgetTransaction(
            id: 'pdf-row',
            userId: 'user',
            accountId: account.id,
            date: date.add(const Duration(hours: 12)),
            amount: 20,
            exactAmountMinor: 2025,
            currency: 'RUB',
            type: TransactionType.expense,
            categoryId: 'other',
            title: 'Shop',
            merchant: 'Shop',
            description: 'Shop',
            tags: ['statement-import'],
          ),
        ],
        createdPeriodIds: {},
        actionTitle: 'PDF',
        institutionId: 'sberbank',
        confirmedSourceAccountKey: 'full-account-hash',
      );
      expect(result, 0);
      expect(core.transactions, hasLength(1));
      expect(core.accounts.single.balanceMinor, 10025);
      expect(core.rememberedStatementAccount('full-account-hash'), account.id);
      final replay = await core.importSberSnapshot(
        snapshot('p1', product: false),
      );
      expect(replay.unassignedAccountCount, 0);
      expect(core.transactions.single.accountId, account.id);
    },
  );

  test(
    'retained product references resolve without fresh discovery within profile',
    () async {
      final core = engine();
      await core.importSberSnapshot(snapshot('p1'));
      await core.importSberSnapshot(snapshot('p2'));
      final before = {for (final t in core.transactions) t.id: t.accountId};
      final replay = await core.importSberSnapshot(
        snapshot('p1', product: false, explicitReference: true),
      );
      expect(replay.unassignedAccountCount, 0);
      expect(core.accounts, hasLength(2));
      expect({for (final t in core.transactions) t.id: t.accountId}, before);
    },
  );

  test(
    'bank products persist in separate profile scopes and replay stays stable',
    () async {
      final core = engine();
      await core.importSberSnapshot(snapshot('p1'));
      await core.importSberSnapshot(snapshot('p2'));
      expect(core.accounts, hasLength(2));
      expect(core.transactions, hasLength(2));
      expect(core.synoballState.accounts.map((a) => a.connectionId).toSet(), {
        'p1',
        'p2',
      });
      await core.importSberSnapshot(snapshot('p1'));
      expect(core.accounts, hasLength(2));
      expect(core.transactions, hasLength(2));
    },
  );
}
