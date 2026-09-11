import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/user_financial_data_codec.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';
import 'package:qesto/synoball/synoball.dart';
import 'package:qesto/features/budget/services/cash_flow_calculation_service.dart';
import 'package:qesto/features/transaction_import/services/transaction_account_resolver.dart';
import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';

void main() {
  test('cash flow sums minor units before presentation rounding', () {
    final summary = const CashFlowCalculationService().calculate(
      transactions: [
        for (final id in ['1', '2'])
          BudgetTransaction(
            id: id,
            userId: 'test',
            accountId: 'A',
            date: DateTime(2026, 9, 6),
            amount: 100,
            exactAmountMinor: 10025,
            currency: 'RUB',
            type: TransactionType.expense,
          ),
      ],
      from: DateTime(2026, 9, 1),
      toExclusive: DateTime(2026, 10, 1),
      currency: 'RUB',
    );
    expect(summary.externalOutflowsMinor, 20050);
    expect(summary.netCashFlowMinor, -20050);
    expect(summary.netCashFlow, -201);
  });
  test('bank and currency conflicts cannot use single-account fallback', () {
    const accounts = [
      QestoAccount(
        id: 't',
        userId: 'test',
        title: 'Т-Банк 1234',
        balance: 0,
        currency: 'RUB',
        type: AccountType.bankCard,
      ),
    ];
    const resolver = TransactionAccountResolver();
    expect(
      resolver.resolve(
        accounts: accounts,
        bankHint: 'sber',
        accountHint: '1234',
        currency: 'RUB',
      ),
      isNull,
    );
    expect(
      resolver.resolve(accounts: accounts, bankHint: 'tbank', currency: 'USD'),
      isNull,
    );
  });
  test('wipe invalidates a bank result captured before the deletion', () async {
    final controller = BudgetController(
      configuration: budgetConfiguration,
      financialData: UserFinancialData(
        user: const QestoUser(id: 'test', name: 'Test', defaultCurrency: 'RUB'),
        referenceDate: DateTime(2026, 9, 6),
      ),
    );
    final generation = controller.dataGeneration;
    await controller.clearAllFinancialData();
    await expectLater(
      controller.importSberSnapshot(
        SberSyncSnapshot(
          observedAt: DateTime(2026, 9, 6),
          accounts: const [],
          transactions: const [],
          oldestTransaction: null,
          newestTransaction: null,
          pendingCount: 0,
          pageType: SberPageType.transactions,
        ),
        expectedGeneration: generation,
      ),
      throwsStateError,
    );
    expect(controller.transactions, isEmpty);
  });
  test(
    'statement refresh preserves cents and user fields without false user confirmation',
    () async {
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'test',
            name: 'Test',
            defaultCurrency: 'RUB',
          ),
          referenceDate: DateTime(2026, 9, 6),
        ),
      );
      final row = BudgetTransaction(
        id: 'statement-row',
        userId: 'test',
        accountId: controller.accounts.first.id,
        date: DateTime(2026, 9, 1),
        amount: 100,
        currency: 'RUB',
        type: TransactionType.expense,
        merchant: 'Provider',
        categoryId: 'other',
      );
      Future<void> ingest(BudgetTransaction value, int minor) async {
        await controller.importStatement(
          account: controller.accounts.first,
          transactions: [value],
          createdPeriodIds: {},
          actionTitle: 'Test import',
          exactMinorById: {value.id: minor},
        );
      }

      await ingest(row, 10025);
      await ingest(row, 10025);
      expect(
        controller.synoballState.transactions.single.amount.minorUnits,
        10025,
      );
      expect(
        controller.synoballState.transactions.single.fieldTrust,
        isNot(SourceTrustLevel.userConfirmed),
      );
      await controller.updateTransaction(
        controller.transactions.single.copyWith(
          categoryId: 'travel',
          merchant: 'My title',
          date: DateTime(2026, 9, 2),
        ),
      );
      await ingest(
        row.copyWith(merchant: 'New provider title', categoryId: 'cafes'),
        10025,
      );
      final result = controller.synoballState.transactions.single;
      expect(result.amount.minorUnits, 10025);
      expect(result.effectiveCategory, 'travel');
      expect(result.merchantName, 'My title');
      expect(result.occurredAt, DateTime(2026, 9, 2));
      final projected = const QestoReadModelService()
          .build(controller.synoballState)
          .transactions
          .single;
      expect(projected.amountMinor, 10025);
      final data = UserFinancialData(
        user: controller.user,
        referenceDate: DateTime(2026, 9, 6),
        transactions: [projected],
      );
      expect(
        const UserFinancialDataCodec()
            .decode(const UserFinancialDataCodec().encode(data))
            .transactions
            .single
            .amountMinor,
        10025,
      );
    },
  );
  test('signed balance projection preserves exact minor units', () {
    final view = const QestoReadModelService().build(
      const SynoballState(
        accounts: [
          SynoballAccount(
            id: 'A',
            entityId: 'E',
            name: 'A',
            type: SynoballAccountType.checking,
            currency: 'RUB',
            balance: Money(minorUnits: -100, currency: 'RUB'),
          ),
        ],
      ),
    );
    expect(view.accounts.single.balance, -1);
    expect(view.accounts.single.balanceMinor, -100);
  });
}
