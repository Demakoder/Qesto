import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/data/persistence/local_key_value_store.dart';
import 'package:qesto/data/repositories/local_qesto_repository.dart';
import 'package:qesto/features/budget/services/cash_flow_calculation_service.dart';
import 'package:qesto/features/budget/state/budget_controller.dart';
import 'package:qesto/features/capital/domain/account_capital_service.dart';
import 'package:qesto/mocks/fixtures/budget_categories.dart';

// Opt-in, read-only replay of an ignored local snapshot. No native store,
// browser session, network request or write to the user's financial profile.
void main() {
  final directory = Platform.environment['QESTO_SBER_SAVINGS_REPLAY_DIR'];
  test(
    'real persisted own-transfer leaves aggregate liquidity unchanged',
    () async {
      final root = Directory(directory!).absolute.resolveSymbolicLinksSync();
      final allowed = Directory(
        '../../.codex_tmp',
      ).absolute.resolveSymbolicLinksSync();
      expect(root.startsWith('$allowed${Platform.pathSeparator}'), isTrue);
      final source = File(
        '$root${Platform.pathSeparator}financial-snapshot.json',
      ).readAsStringSync();
      final store = MemoryKeyValueStore({
        'qesto.user-financial-data.v1': source,
      });
      final data = await LocalQestoRepository(
        store: store,
        publicStore: store,
      ).getUserFinancialData();
      final controller = BudgetController(
        configuration: budgetConfiguration,
        financialData: data,
      );
      addTearDown(controller.dispose);

      final routed = controller.transactions
          .where(
            (item) =>
                item.amountMinor == 1500000 &&
                item.date.year == 2026 &&
                item.date.month == 9 &&
                item.tags.any(
                  (tag) => tag.startsWith(
                    qestoInternalTransferDestinationAccountPrefix,
                  ),
                ),
          )
          .toList();
      expect(routed, hasLength(1));
      final transfer = routed.single;
      expect(transfer.type, TransactionType.transfer);
      expect(transfer.tags, contains(qestoInternalTransferTag));
      final sourceId = transfer.tags
          .singleWhere(
            (tag) => tag.startsWith(qestoInternalTransferSourceAccountPrefix),
          )
          .substring(qestoInternalTransferSourceAccountPrefix.length);
      final destinationId = transfer.tags
          .singleWhere(
            (tag) =>
                tag.startsWith(qestoInternalTransferDestinationAccountPrefix),
          )
          .substring(qestoInternalTransferDestinationAccountPrefix.length);
      final sourceAccount = controller.accounts.singleWhere(
        (a) => a.id == sourceId,
      );
      final savingsAccount = controller.accounts.singleWhere(
        (a) => a.id == destinationId,
      );
      expect(sourceAccount.type, AccountType.cash);
      expect(savingsAccount.type, AccountType.savings);
      expect(savingsAccount.balanceMinor, 1500000);

      final cashFlow = controller.cashFlowForRange(
        from: DateTime(2026, 9),
        toExclusive: DateTime(2026, 10),
        currency: 'RUB',
      );
      expect(
        const CashFlowCalculationService().treatment(transfer),
        CashFlowTreatment.internalTransfer,
      );
      expect(cashFlow.externalOutflowsMinor, 2309312);
      expect(cashFlow.externalInflowsMinor, 3908522);
      expect(cashFlow.netCashFlowMinor, 1599210);

      AccountCapitalSnapshot capital(List<BudgetTransaction> transactions) =>
          const AccountCapitalService().calculate(
            accounts: controller.accounts,
            accountPreferences: controller.accountPreferences,
            transactions: transactions,
            upcomingExpenses: controller.upcomingExpenses,
            savingsGoals: controller.savingsGoals,
            goalAllocations: controller.goalAllocations,
            debts: controller.debts,
            synoballState: controller.synoballState,
            asOf: DateTime(2026, 9, 27),
            period: CapitalPeriod.oneMonth,
            baseCurrency: 'RUB',
          );
      final observed = capital(controller.transactions);
      final withoutTransfer = capital(
        controller.transactions
            .where((item) => item.id != transfer.id)
            .toList(),
      );
      expect(observed.totalLiquidAssets, 17400);
      expect(observed.totalLiquidAssets, withoutTransfer.totalLiquidAssets);
      expect(
        {for (final point in observed.history) point.date: point.balance},
        {
          for (final point in withoutTransfer.history)
            point.date: point.balance,
        },
      );
      expect(
        File(
          '$root${Platform.pathSeparator}financial-snapshot.json',
        ).readAsStringSync(),
        source,
      );
    },
    skip: directory == null,
  );
}
