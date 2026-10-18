import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../desktop/widgets/transaction_attention_panel.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/statistics/presentation/state/statistics_controller.dart';

/// Reads the existing quality report, with no private review status/copies.
class MobileAttentionQueue extends StatefulWidget {
  const MobileAttentionQueue({
    required this.controller,
    required this.onOpenTransaction,
    this.statistics,
    super.key,
  });
  final BudgetController controller;
  final ValueChanged<String> onOpenTransaction;
  final StatisticsController? statistics;
  @override
  State<MobileAttentionQueue> createState() => _MobileAttentionQueueState();
}

class _MobileAttentionQueueState extends State<MobileAttentionQueue> {
  late final _statistics =
      widget.statistics ??
      StatisticsController(budgetController: widget.controller);
  @override
  void dispose() {
    if (widget.statistics == null) _statistics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('mobile-attention-queue'),
    appBar: AppBar(title: const Text('Требуют внимания')),
    body: ListenableBuilder(
      listenable: _statistics,
      builder: (context, _) {
        final rows = attentionTransactions(_statistics);
        if (rows.isEmpty) {
          return const Center(child: Text('Все операции проверены'));
        }
        return ListView.builder(
          key: const PageStorageKey('mobile-attention-scroll'),
          padding: const EdgeInsets.all(16),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return Card(
              child: ListTile(
                key: Key('attention-${row.transaction.id}'),
                onTap: () => widget.onOpenTransaction(row.transaction.id),
                title: Text(
                  row.transaction.merchant ??
                      row.transaction.title ??
                      'Операция',
                ),
                subtitle: Text(
                  '${formatDate(row.transaction.date)}\n${row.issues.map((i) => i.title).join(' · ')}',
                ),
                trailing: Text(
                  formatMinorMoney(
                    row.transaction.amountMinor,
                    row.transaction.currency,
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
