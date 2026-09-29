import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/add_expense_screen.dart';
import '../../features/statistics/domain/models/statistics_models.dart';
import '../../features/statistics/presentation/state/statistics_controller.dart';
import '../desktop_financial_helpers.dart';

/// A grouped view of the existing quality report, never a second status store.
class AttentionTransaction {
  const AttentionTransaction(this.transaction, this.issues);
  final BudgetTransaction transaction;
  final List<DataQualityIssue> issues;
}

List<AttentionTransaction> attentionTransactions(
  StatisticsController statistics,
) {
  final snapshot = statistics.snapshot;
  final byId = {
    for (final transaction in statistics.budgetController.transactions)
      transaction.id: transaction,
  };
  final grouped = <String, List<DataQualityIssue>>{};
  for (final issue in snapshot.dataQuality.issues) {
    final id = issue.transactionId;
    if (id == null || !byId.containsKey(id)) continue;
    grouped.putIfAbsent(id, () => []).add(issue);
  }
  final items = [
    for (final entry in grouped.entries)
      AttentionTransaction(byId[entry.key]!, List.unmodifiable(entry.value)),
  ];
  items.sort((a, b) => b.transaction.date.compareTo(a.transaction.date));
  return items;
}

Future<void> showTransactionAttentionPanel(
  BuildContext context,
  StatisticsController statistics,
) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Закрыть проверку операций',
  barrierColor: Colors.black.withValues(alpha: .36),
  pageBuilder: (dialogContext, _, _) => Align(
    alignment: Alignment.centerRight,
    child: SizedBox(
      width: MediaQuery.sizeOf(dialogContext).width < 650
          ? MediaQuery.sizeOf(dialogContext).width
          : 520,
      height: double.infinity,
      child: Material(
        color: dialogContext.qestoColors.surface,
        child: SafeArea(
          child: TransactionAttentionPanel(statistics: statistics),
        ),
      ),
    ),
  ),
);

Future<void> showQestoNotificationCenter(
  BuildContext context,
  StatisticsController statistics, {
  required Future<void> Function() onOpenInbox,
}) => showDialog<void>(
  context: context,
  builder: (dialogContext) => ListenableBuilder(
    listenable: statistics,
    builder: (dialogContext, _) {
      final count = attentionTransactions(statistics).length;
      return AlertDialog(
        key: const Key('qesto-notification-center'),
        title: const Text('Уведомления'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('notification-attention-entry'),
                leading: Icon(
                  count == 0
                      ? Icons.verified_outlined
                      : Icons.warning_amber_rounded,
                  color: count == 0
                      ? dialogContext.qestoColors.positive
                      : dialogContext.qestoColors.warning,
                ),
                title: Text(
                  count == 0
                      ? 'Нет операций для проверки'
                      : '$count операций требуют внимания',
                ),
                subtitle: const Text(
                  'Проверьте данные, чтобы аналитика Qesto была точнее.',
                ),
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  showTransactionAttentionPanel(context, statistics);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.notifications_none_rounded),
                title: const Text('Уведомления и SMS'),
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  onOpenInbox();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      );
    },
  ),
);

enum _AttentionFilter { all, category, merchant, duplicates, other }

class TransactionAttentionPanel extends StatefulWidget {
  const TransactionAttentionPanel({required this.statistics, super.key});
  final StatisticsController statistics;

  @override
  State<TransactionAttentionPanel> createState() =>
      _TransactionAttentionPanelState();
}

class _TransactionAttentionPanelState extends State<TransactionAttentionPanel> {
  var _filter = _AttentionFilter.all;

  bool _matches(AttentionTransaction item) => switch (_filter) {
    _AttentionFilter.all => true,
    _AttentionFilter.category => item.issues.any(
      (issue) =>
          issue.type == DataQualityIssueType.uncategorized ||
          issue.type == DataQualityIssueType.lowConfidence,
    ),
    _AttentionFilter.merchant => item.issues.any(
      (issue) => issue.type == DataQualityIssueType.unknownMerchant,
    ),
    _AttentionFilter.duplicates => item.issues.any(
      (issue) => issue.type == DataQualityIssueType.potentialDuplicate,
    ),
    _AttentionFilter.other => item.issues.any(
      (issue) =>
          issue.type == DataQualityIssueType.unconfirmedOperation ||
          issue.type == DataQualityIssueType.missingAccount,
    ),
  };

  Future<void> _edit(AttentionTransaction item) async {
    final transaction = item.transaction;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddExpenseScreen(
          controller: widget.statistics.budgetController,
          period: widget.statistics.periodFor(transaction),
          initialTransaction: transaction,
          attentionReasons: item.issues.map((issue) => issue.title).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.statistics,
    builder: (context, _) {
      final all = attentionTransactions(widget.statistics);
      final visible = all.where(_matches).toList();
      return Column(
        key: const Key('transaction-attention-panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Требуют внимания',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              all.isEmpty
                  ? 'Все операции проверены'
                  : '${all.length} операций · проверьте данные, в которых Qesto не уверен',
              style: TextStyle(color: context.qestoColors.secondaryText),
            ),
          ),
          if (all.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  for (final filter in _AttentionFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(switch (filter) {
                          _AttentionFilter.all => 'Все',
                          _AttentionFilter.category => 'Категория',
                          _AttentionFilter.merchant => 'Продавец',
                          _AttentionFilter.duplicates => 'Дубли',
                          _AttentionFilter.other => 'Другие',
                        }),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: all.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_rounded, size: 42),
                        SizedBox(height: 10),
                        Text('Всё проверено'),
                        Text('Сейчас нет операций, требующих вашего внимания.'),
                      ],
                    ),
                  )
                : visible.isEmpty
                ? const Center(child: Text('В этом фильтре операций нет'))
                : ListView.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      final transaction = item.transaction;
                      final budget = widget.statistics.budgetController;
                      return ListTile(
                        key: Key('attention-transaction-${transaction.id}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        title: Text(
                          desktopTransactionTitle(transaction),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${formatDate(transaction.date, includeYear: true)} · '
                              '${desktopCategoryName(budget, transaction)} · '
                              '${desktopSourceLabel(budget, transaction.id)}',
                            ),
                            for (final issue in item.issues)
                              Text(
                                issue.title,
                                style: TextStyle(
                                  color: context.qestoColors.warning,
                                ),
                              ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              transaction.amountMinor % 100 == 0
                                  ? formatMoney(
                                      desktopSignedAmount(transaction),
                                      transaction.currency,
                                      showSign: true,
                                    )
                                  : formatMinorMoney(
                                      desktopSignedAmount(transaction) < 0
                                          ? -transaction.amountMinor
                                          : transaction.amountMinor,
                                      transaction.currency,
                                    ),
                            ),
                            const Icon(Icons.chevron_right_rounded, size: 18),
                          ],
                        ),
                        onTap: () => _edit(item),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}
