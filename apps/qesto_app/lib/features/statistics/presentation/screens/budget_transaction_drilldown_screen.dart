import 'package:flutter/material.dart';

import '../../../../core/formatters/qesto_formatters.dart';
import '../../../../core/widgets/nested_screen_header.dart';
import '../../../../core/widgets/qesto_card.dart';
import '../../../../data/models/qesto_models.dart';
import '../../../budget/services/cash_flow_calculation_service.dart';
import '../../../budget/state/budget_controller.dart';
import '../widgets/transaction_drilldown_list.dart';

/// Drill-down for aggregates calculated directly from the budget ledger.
/// The selector is re-evaluated on every budget edit so totals and rows stay live.
class BudgetTransactionDrilldownScreen extends StatelessWidget {
  const BudgetTransactionDrilldownScreen({
    required this.controller,
    required this.title,
    required this.selectTransactions,
    required this.from,
    required this.to,
    this.splitCashFlow = false,
    super.key,
  });

  final BudgetController controller;
  final String title;
  final List<BudgetTransaction> Function(BudgetController) selectTransactions;
  final DateTime from;
  final DateTime to;
  final bool splitCashFlow;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final rows = selectTransactions(controller)
          .where((item) {
            final day = DateUtils.dateOnly(item.date);
            return !day.isBefore(from) && !day.isAfter(to);
          })
          .toList(growable: false);
      final income = rows
          .where(
            (item) =>
                controller.cashFlowTreatment(item) ==
                CashFlowTreatment.externalInflow,
          )
          .toList(growable: false);
      final expenses = rows
          .where(
            (item) =>
                controller.cashFlowTreatment(item) ==
                CashFlowTreatment.externalOutflow,
          )
          .toList(growable: false);
      final currency =
          rows.firstOrNull?.currency ??
          controller.accounts.firstOrNull?.currency ??
          'RUB';
      final total = rows.fold<int>(0, (sum, item) => sum + item.amount);
      final incomeTotal = income.fold<int>(0, (sum, item) => sum + item.amount);
      final expenseTotal = expenses.fold<int>(
        0,
        (sum, item) => sum + item.amount,
      );
      return Scaffold(
        appBar: NestedScreenHeader(title: Text(title)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
          children: [
            QestoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatDate(from, includeYear: true)} — ${formatDate(to, includeYear: true)}',
                  ),
                  const SizedBox(height: 6),
                  if (splitCashFlow) ...[
                    Text('Доходы: ${formatMoney(incomeTotal, currency)}'),
                    Text('Расходы: ${formatMoney(expenseTotal, currency)}'),
                    Text(
                      'Итого: ${formatMoney(incomeTotal - expenseTotal, currency, showSign: true)}',
                    ),
                  ] else
                    Text(
                      '${rows.length} операций · ${formatMoney(total, currency)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (splitCashFlow) ...[
              TransactionDrilldownList(
                keyPrefix: 'cashflow-income',
                controller: controller,
                transactions: income,
                title: 'Доходы',
              ),
              const SizedBox(height: 14),
              TransactionDrilldownList(
                keyPrefix: 'cashflow-expense',
                controller: controller,
                transactions: expenses,
                title: 'Расходы',
              ),
            ] else
              TransactionDrilldownList(
                keyPrefix: 'budget-drilldown',
                controller: controller,
                transactions: rows,
                title: 'Операции',
              ),
          ],
        ),
      );
    },
  );
}
