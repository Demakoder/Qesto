import 'package:flutter/material.dart';

import '../../../../core/formatters/qesto_formatters.dart';
import '../../../../core/theme/qesto_theme.dart';
import '../../../../core/widgets/nested_screen_header.dart';
import '../../../../core/widgets/qesto_card.dart';
import '../../../../core/widgets/states.dart';
import '../../../../data/models/qesto_models.dart';
import '../../../budget/transaction_details_screen.dart';
import '../../../budget/widgets/budget_category_icon.dart';
import '../../domain/models/statistics_models.dart';
import '../state/statistics_controller.dart';
import '../widgets/statistics_charts.dart';
import '../widgets/statistics_components.dart';

class StatisticsOperationsScreen extends StatelessWidget {
  const StatisticsOperationsScreen({
    required this.controller,
    required this.title,
    required this.transactions,
    this.transactionSelector,
    super.key,
  });

  final StatisticsController controller;
  final String title;
  final List<BudgetTransaction> transactions;
  final List<BudgetTransaction> Function(StatisticsController)?
  transactionSelector;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _buildCurrent(context),
    );
  }

  Widget _buildCurrent(BuildContext context) {
    final ids = transactions.map((transaction) => transaction.id).toSet();
    final currentTransactions =
        transactionSelector?.call(controller) ??
        controller.snapshot.transactions
            .where((transaction) => ids.contains(transaction.id))
            .toList();
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      body: currentTransactions.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: EmptyState(
                message: 'В выбранном периоде пока нет операций',
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
              itemCount: currentTransactions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 9),
              itemBuilder: (context, index) {
                final transaction = currentTransactions[index];
                final category = transaction.categoryId == null
                    ? null
                    : controller.budgetController.categories
                          .where((item) => item.id == transaction.categoryId)
                          .firstOrNull;
                return QestoCard(
                  padding: EdgeInsets.zero,
                  onTap: () => _openTransaction(context, transaction),
                  child: ListTile(
                    minTileHeight: 68,
                    leading: BudgetCategoryIcon(
                      iconKey: category?.iconKey ?? 'other',
                      color: Color(category?.colorValue ?? 0xFF8A8F9C),
                      size: 42,
                    ),
                    title: Text(
                      controller.calculationService.merchantName(transaction),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${formatDate(transaction.date)} · ${category?.name ?? 'Без категории'}',
                    ),
                    trailing: Text(
                      formatMoney(
                        controller.calculationService.signedExpense(
                          transaction,
                        ),
                        transaction.currency,
                        showSign: transaction.type == TransactionType.refund,
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: transaction.type == TransactionType.refund
                            ? context.qestoColors.green
                            : context.qestoColors.text,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _openTransaction(BuildContext context, BudgetTransaction transaction) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionDetailsScreen(
          controller: controller.budgetController,
          period: controller.periodFor(transaction),
          transactionId: transaction.id,
        ),
      ),
    );
  }
}

class StatisticsCategoryScreen extends StatelessWidget {
  const StatisticsCategoryScreen({
    required this.controller,
    required this.categoryId,
    super.key,
  });

  final StatisticsController controller;
  final String categoryId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final category = controller.budgetController.categories
            .where((item) => item.id == categoryId)
            .firstOrNull;
        final stat = controller.snapshot.categories
            .where((item) => item.id == categoryId)
            .firstOrNull;
        final transactions = controller.transactionsForCategory(categoryId);
        final points = controller.calculationService.dailyPoints(
          controller.query.period,
          transactions,
        );
        return Scaffold(
          appBar: NestedScreenHeader(
            title: Text(
              category?.name ?? 'Категория',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            actions: [
              IconButton(
                tooltip:
                    controller.isTracked(
                      TrackedStatisticsType.category,
                      categoryId,
                    )
                    ? 'Не отслеживать'
                    : 'Отслеживать',
                onPressed: () => controller.toggleTracked(
                  TrackedStatisticsType.category,
                  categoryId,
                  category?.name ?? categoryId,
                ),
                icon: Icon(
                  controller.isTracked(
                        TrackedStatisticsType.category,
                        categoryId,
                      )
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: context.qestoColors.primary,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: stat == null
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: EmptyState(
                    message: 'В выбранном периоде нет расходов этой категории',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                  children: [
                    StatisticsMetricStrip(
                      items: [
                        StatisticsMetricItem(
                          label: 'Расходы',
                          value: formatMoney(stat.amount, 'RUB'),
                          caption: statisticsRangeLabel(
                            controller.query.period,
                          ),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                        StatisticsMetricItem(
                          label: 'Покупки',
                          value: '${stat.count}',
                          caption: 'за выбранный период',
                          icon: Icons.receipt_long_outlined,
                        ),
                        StatisticsMetricItem(
                          label: 'Средний чек',
                          value: formatMoney(stat.averageCheck.round(), 'RUB'),
                          caption:
                              'обычный ${formatMoney(stat.medianCheck.round(), 'RUB')}',
                          icon: Icons.calculate_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    StatisticsLineChartCard(
                      title: 'Динамика категории',
                      points: points,
                    ),
                    const SizedBox(height: 14),
                    QestoCard(
                      child: Column(
                        children: [
                          const StatisticsSectionHeader(
                            title: 'Продавцы категории',
                          ),
                          const SizedBox(height: 8),
                          for (final merchant in _merchantStats(
                            transactions,
                          ).take(5))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                merchant.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text('${merchant.count} покупок'),
                              trailing: Text(
                                formatMoney(merchant.amount, 'RUB'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => _openOperations(
                        context,
                        transactions,
                        category?.name ?? 'Операции',
                      ),
                      icon: const Icon(Icons.receipt_long_rounded),
                      label: const Text('Открыть операции'),
                    ),
                  ],
                ),
        );
      },
    );
  }

  List<StatisticsGroupStat> _merchantStats(
    List<BudgetTransaction> transactions,
  ) => controller.calculationService.merchantStats(
    current: transactions,
    comparison: const [],
  );

  void _openOperations(
    BuildContext context,
    List<BudgetTransaction> transactions,
    String title,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatisticsOperationsScreen(
          controller: controller,
          title: title,
          transactions: transactions,
          transactionSelector: (statistics) =>
              statistics.transactionsForCategory(categoryId),
        ),
      ),
    );
  }
}

class StatisticsMerchantScreen extends StatelessWidget {
  const StatisticsMerchantScreen({
    required this.controller,
    required this.merchant,
    super.key,
  });

  final StatisticsController controller;
  final String merchant;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final stat = controller.snapshot.merchants
            .where((item) => item.id == merchant)
            .firstOrNull;
        final transactions = controller.transactionsForMerchant(merchant);
        final points = controller.calculationService.dailyPoints(
          controller.query.period,
          transactions,
        );
        return Scaffold(
          appBar: NestedScreenHeader(
            title: Text(
              merchant,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            actions: [
              IconButton(
                tooltip:
                    controller.isTracked(
                      TrackedStatisticsType.merchant,
                      merchant,
                    )
                    ? 'Не отслеживать'
                    : 'Отслеживать',
                onPressed: () => controller.toggleTracked(
                  TrackedStatisticsType.merchant,
                  merchant,
                  merchant,
                ),
                icon: Icon(
                  controller.isTracked(TrackedStatisticsType.merchant, merchant)
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  color: context.qestoColors.primary,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: stat == null
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: EmptyState(
                    message: 'Нет подтверждённых операций продавца',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                  children: [
                    StatisticsMetricStrip(
                      items: [
                        StatisticsMetricItem(
                          label: 'Сумма',
                          value: formatMoney(stat.amount, 'RUB'),
                          caption:
                              '${(stat.share * 100).toStringAsFixed(0)}% расходов',
                          icon: Icons.storefront_outlined,
                        ),
                        StatisticsMetricItem(
                          label: 'Покупки',
                          value: '${stat.count}',
                          caption: 'за выбранный период',
                          icon: Icons.shopping_bag_outlined,
                        ),
                        StatisticsMetricItem(
                          label: 'Обычный чек',
                          value: formatMoney(stat.medianCheck.round(), 'RUB'),
                          caption:
                              'средний ${formatMoney(stat.averageCheck.round(), 'RUB')}',
                          icon: Icons.receipt_long_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    StatisticsLineChartCard(
                      title: 'Динамика у продавца',
                      points: points,
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StatisticsOperationsScreen(
                            controller: controller,
                            title: merchant,
                            transactions: transactions,
                            transactionSelector: (statistics) =>
                                statistics.transactionsForMerchant(merchant),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.receipt_long_rounded),
                      label: const Text('Открыть операции'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Правило категоризации будет применяться к новым операциям',
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.rule_rounded),
                      label: const Text('Создать правило'),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
