import 'package:flutter/material.dart';

import '../../../../core/formatters/qesto_formatters.dart';
import '../../../../core/theme/qesto_theme.dart';
import '../../../../core/widgets/nested_screen_header.dart';
import '../../../../core/widgets/qesto_card.dart';
import '../../../../core/widgets/states.dart';
import '../../../../data/models/qesto_models.dart';
import '../../../budget/transaction_details_screen.dart';
import '../../domain/models/statistics_models.dart';
import '../state/statistics_controller.dart';
import '../widgets/statistics_components.dart';
import 'statistics_drilldown_screens.dart';

class TrackedStatisticsScreen extends StatelessWidget {
  const TrackedStatisticsScreen({required this.controller, super.key});

  final StatisticsController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Scaffold(
        appBar: NestedScreenHeader(
          title: Text(
            'Отслеживаемое',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        body: controller.tracked.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(18),
                child: EmptyState(
                  message:
                      'Добавляйте категории и продавцов звездой на детальных экранах',
                  icon: Icons.star_border_rounded,
                ),
              )
            : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                itemCount: controller.tracked.length,
                onReorderItem: controller.reorderTracked,
                itemBuilder: (context, index) {
                  final item = controller.tracked[index];
                  final stat = _statFor(item);
                  return Padding(
                    key: ValueKey('${item.type}-${item.id}'),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: QestoCard(
                      onTap: () => _open(context, item),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.label,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              IconButton(
                                tooltip: item.isPinned
                                    ? 'Открепить'
                                    : 'Закрепить',
                                onPressed: () => controller.togglePinned(index),
                                icon: Icon(
                                  item.isPinned
                                      ? Icons.push_pin_rounded
                                      : Icons.push_pin_outlined,
                                  color: QestoColors.primary,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Удалить из отслеживаемого',
                                onPressed: () => controller.toggleTracked(
                                  item.type,
                                  item.id,
                                  item.label,
                                ),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: QestoColors.secondaryText,
                                ),
                              ),
                              const Icon(
                                Icons.drag_handle_rounded,
                                color: QestoColors.secondaryText,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 18,
                            runSpacing: 10,
                            children: [
                              _TrackedValue(
                                label: 'Этот период',
                                value: stat == null
                                    ? 'Нет данных'
                                    : formatMoney(stat.amount, 'RUB'),
                              ),
                              _TrackedValue(
                                label: 'Покупки',
                                value: stat == null ? '—' : '${stat.count}',
                              ),
                              _TrackedValue(
                                label: 'Изменение',
                                value: _change(stat?.changePercent),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  StatisticsGroupStat? _statFor(TrackedStatisticsItem item) =>
      switch (item.type) {
        TrackedStatisticsType.category =>
          controller.snapshot.categories
              .where((stat) => stat.id == item.id)
              .firstOrNull,
        TrackedStatisticsType.merchant =>
          controller.snapshot.merchants
              .where((stat) => stat.id == item.id)
              .firstOrNull,
        _ => null,
      };

  String _change(double? value) => value == null
      ? 'Нет сравнения'
      : '${value >= 0 ? '↑' : '↓'} ${value.abs().toStringAsFixed(0)}%';

  void _open(BuildContext context, TrackedStatisticsItem item) {
    final route = switch (item.type) {
      TrackedStatisticsType.category => StatisticsCategoryScreen(
        controller: controller,
        categoryId: item.id,
      ),
      TrackedStatisticsType.merchant => StatisticsMerchantScreen(
        controller: controller,
        merchant: item.id,
      ),
      _ => StatisticsOperationsScreen(
        controller: controller,
        title: item.label,
        transactions: const [],
      ),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => route));
  }
}

class _TrackedValue extends StatelessWidget {
  const _TrackedValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 115,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class ExploreStatisticsScreen extends StatelessWidget {
  const ExploreStatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text(
          'Исследовать данные',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
        children: [
          QestoCard(
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                    color: QestoColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.manage_search_rounded,
                    size: 38,
                    color: QestoColors.primary,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Собственный финансовый запрос',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  'Здесь можно будет самостоятельно выбирать показатель, способ группировки, фильтры и вид графика.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: QestoColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          QestoCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const StatisticsSectionHeader(
                  title: 'Примеры будущего анализа',
                ),
                const SizedBox(height: 10),
                for (final text in const [
                  'Как изменился средний чек в кафе за полгода?',
                  'В какие дни я чаще совершаю крупные покупки?',
                  'Какие продавцы сильнее всего повлияли на рост расходов?',
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_graph_rounded,
                          color: QestoColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(text)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Назад к статистике'),
          ),
        ],
      ),
    );
  }
}

class DataQualityScreen extends StatelessWidget {
  const DataQualityScreen({required this.controller, super.key});

  final StatisticsController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final report = controller.snapshot.dataQuality;
        final transfers = controller.snapshot.transactions
            .where((item) => item.type == TransactionType.transfer)
            .toList();
        final incomingTransfers = transfers
            .where(
              (item) => item.transferDirection == TransferDirection.incoming,
            )
            .fold<int>(0, (sum, item) => sum + item.amount);
        final outgoingTransfers = transfers
            .where(
              (item) => item.transferDirection != TransferDirection.incoming,
            )
            .fold<int>(0, (sum, item) => sum + item.amount);
        final currency = transfers.firstOrNull?.currency ?? 'RUB';
        return Scaffold(
          appBar: NestedScreenHeader(
            title: Text(
              'Полнота данных',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
            children: [
              QestoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Полнота статистики',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: QestoColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${report.score}%',
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      minHeight: 9,
                      borderRadius: BorderRadius.circular(8),
                      value: report.score / 100,
                      backgroundColor: QestoColors.border,
                      valueColor: AlwaysStoppedAnimation(
                        report.score < 70
                            ? QestoColors.danger
                            : report.score < 90
                            ? QestoColors.orange
                            : QestoColors.green,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${report.issues.length} проблем · ${report.criticalCount} критических',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (transfers.isNotEmpty) ...[
                QestoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: QestoColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.swap_horiz_rounded,
                              color: QestoColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Переводы',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text('${transfers.length} операций'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Входящие\n+${formatMoney(incomingTransfers, currency)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Исходящие\n−${formatMoney(outgoingTransfers, currency)}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (report.issues.isEmpty)
                const EmptyState(
                  message: 'Все операции выбранного периода проверены',
                  icon: Icons.verified_rounded,
                )
              else
                QestoCard(
                  child: Column(
                    children: [
                      const StatisticsSectionHeader(title: 'Требуют внимания'),
                      const SizedBox(height: 8),
                      for (final issue in report.issues)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          minTileHeight: 64,
                          onTap: () => _showIssue(context, issue),
                          leading: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color:
                                  (issue.isCritical
                                          ? QestoColors.danger
                                          : QestoColors.orange)
                                      .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              issue.isCritical
                                  ? Icons.error_outline_rounded
                                  : Icons.warning_amber_rounded,
                              color: issue.isCritical
                                  ? QestoColors.danger
                                  : const Color(0xFFB76500),
                            ),
                          ),
                          title: Text(
                            issue.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            issue.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showIssue(BuildContext context, DataQualityIssue issue) async {
    final transaction = issue.transactionId == null
        ? null
        : controller.budgetController.transactions
              .where((item) => item.id == issue.transactionId)
              .firstOrNull;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(issue.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              issue.description,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 18),
            if (transaction != null)
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TransactionDetailsScreen(
                        controller: controller.budgetController,
                        period: controller.periodFor(transaction),
                        transactionId: transaction.id,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Открыть операцию'),
              ),
            if (transaction != null) const SizedBox(height: 10),
            if (transaction != null)
              OutlinedButton.icon(
                onPressed: () {
                  if (issue.type == DataQualityIssueType.potentialDuplicate) {
                    controller.budgetController.deleteTransaction(
                      transaction.id,
                    );
                  } else if (issue.type == DataQualityIssueType.uncategorized) {
                    controller.budgetController.updateTransaction(
                      transaction.copyWith(
                        categoryId: 'other',
                        classificationConfidence: 1,
                        isConfirmed: true,
                      ),
                    );
                  } else {
                    controller.budgetController.updateTransaction(
                      transaction.copyWith(
                        isConfirmed: true,
                        isPotentialDuplicate: false,
                        classificationConfidence: 1,
                      ),
                    );
                  }
                  Navigator.of(sheetContext).pop();
                },
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: Text(
                  issue.type == DataQualityIssueType.potentialDuplicate
                      ? 'Объединить дубль'
                      : 'Подтвердить и исправить',
                ),
              ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () {
                controller.ignoreQualityIssue(issue.id);
                Navigator.of(sheetContext).pop();
              },
              icon: const Icon(Icons.visibility_off_outlined),
              label: const Text('Игнорировать проблему'),
            ),
          ],
        ),
      ),
    );
  }
}
