import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_extractors.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/capital/domain/account_capital_service.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

void main() {
  final september = SberSyncRange(
    from: DateTime(2026, 9),
    toExclusive: DateTime(2026, 10),
    label: 'Сентябрь',
  );
  const extractors = SberExtractors();
  const payment = SberAccountFact(
    id: 'sber-account-payment-5023',
    name: 'Платёжный счёт •• 5023',
    type: AccountType.cash,
    currency: 'RUB',
    balance: 2400,
    lastFour: '5023',
  );
  const savings = SberAccountFact(
    id: 'sber-account-savings-1410',
    name: 'Накопительный счёт •• 1410',
    type: AccountType.savings,
    currency: 'RUB',
    balance: 15000,
    lastFour: '1410',
  );

  SberTransactionFact opening({required bool bankProof}) {
    final row = <String, dynamic>{
      'id': 'bank-document-15000',
      'dateIso': '2026-09-26T00:00:00',
      'date': '26 сентября 2026',
      'amount': '15 000 ₽',
      'amountValue': 15000,
      'text':
          'Платёжный счёт •• 5023 15 000 ₽ Накопительный счёт •• 1410 Открытие вклада/счета',
      'merchant': 'Платёжный счёт',
      'description': 'Платёжный счёт',
      'operationType': '',
      if (bankProof) ...{
        'bankOperationCode': 'UfsDepositOpen',
        'sourceProduct': 'Платёжный счёт •• 5023',
        'destinationProduct': 'Накопительный счёт •• 1410',
      },
    };
    return extractors.normalizeTransactionRows([row], range: september).single;
  }

  SberSyncSnapshot snapshot({required bool bankProof}) => SberSyncSnapshot(
    connectionId: 'profile-one',
    observedAt: DateTime(2026, 9, 27),
    accounts: bankProof ? [payment, savings] : [payment],
    transactions: [opening(bankProof: bankProof)],
    oldestTransaction: DateTime(2026, 9, 26),
    newestTransaction: DateTime(2026, 9, 26),
    pendingCount: 0,
    pageType: SberPageType.transactions,
  );

  test(
    'bank proof upgrades existing expense and savings without duplicates',
    () async {
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: UserFinancialData(
          user: const QestoUser(
            id: 'user',
            name: 'Test',
            defaultCurrency: 'RUB',
          ),
          referenceDate: DateTime(2026, 9, 27),
        ),
      );
      final beforeSync = await controller.importSberSnapshot(
        snapshot(bankProof: false),
      );
      final before = controller.cashFlowForRange(
        from: DateTime(2026, 9),
        toExclusive: DateTime(2026, 10),
        currency: 'RUB',
      );
      expect(beforeSync.newCount, 1);
      expect(before.externalOutflowsMinor, 1500000);
      expect(before.externalInflowsMinor, 0);
      expect(before.netCashFlowMinor, -1500000);
      final originalId = controller.transactions.single.id;
      expect(controller.transactions.single.accountId, 'local-default-account');

      final updated = await controller.importSberSnapshot(
        snapshot(bankProof: true),
      );
      final after = controller.cashFlowForRange(
        from: DateTime(2026, 9),
        toExclusive: DateTime(2026, 10),
        currency: 'RUB',
      );
      expect(updated.newCount, 0);
      expect(controller.transactions, hasLength(1));
      expect(controller.transactions.single.id, originalId);
      expect(controller.transactions.single.type, TransactionType.transfer);
      expect(controller.transactions.single.categoryId, 'other');
      expect(after.externalOutflowsMinor, 0);
      expect(after.externalInflowsMinor, 0);
      expect(after.netCashFlowMinor, 0);
      expect(
        controller.accounts.where((a) => a.type == AccountType.savings),
        hasLength(1),
      );
      expect(
        controller.accounts
            .where((a) => a.type == AccountType.savings)
            .single
            .balanceMinor,
        1500000,
      );

      final capital = const AccountCapitalService().calculate(
        accounts: controller.accounts,
        accountPreferences: controller.accountPreferences,
        transactions: controller.transactions,
        upcomingExpenses: controller.upcomingExpenses,
        savingsGoals: controller.savingsGoals,
        synoballState: controller.synoballState,
        asOf: DateTime(2026, 9, 27),
        period: CapitalPeriod.oneMonth,
        baseCurrency: 'RUB',
      );
      expect(capital.totalLiquidAssets, 17400);
      expect(capital.history.first.balance, 17400);
      expect(capital.history.last.balance, 17400);
      expect(capital.change, 0);

      final repeated = await controller.importSberSnapshot(
        snapshot(bankProof: true),
      );
      expect(repeated.newCount, 0);
      expect(controller.transactions, hasLength(1));
      expect(
        controller.accounts.where((a) => a.type == AccountType.savings),
        hasLength(1),
      );
    },
  );
}
