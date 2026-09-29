import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/formatters/qesto_formatters.dart';
import '../../../../core/theme/qesto_theme.dart';
import '../../../../core/widgets/qesto_card.dart';
import '../../../../core/widgets/states.dart';
import '../../../../data/models/qesto_models.dart';
import '../../../../desktop/widgets/desktop_components.dart';
import '../../../profile/services/cbr_currency_service.dart';
import '../../domain/models/statistics_models.dart';
import '../screens/statistics_drilldown_screens.dart';
import '../state/statistics_controller.dart';
import '../widgets/statistics_charts.dart';
import '../widgets/statistics_components.dart';

class OverviewStatisticsSection extends StatelessWidget {
  const OverviewStatisticsSection({
    required this.controller,
    required this.scrollController,
    super.key,
  });

  final StatisticsController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    if (snapshot.transactions.isEmpty) {
      return _empty(scrollController);
    }
    return ListView(
      controller: scrollController,
      key: const PageStorageKey('statistics-overview'),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        StatisticsMetricStrip(
          items: [
            StatisticsMetricItem(
              label: 'Расходы',
              value: formatMoney(snapshot.summary.expenses, 'RUB'),
              caption: statisticsRangeLabel(controller.query.period),
              icon: Icons.account_balance_wallet_outlined,
            ),
            StatisticsMetricItem(
              label: 'Доходы',
              value: formatMoney(snapshot.summary.income, 'RUB'),
              caption: 'без возвратов',
              icon: Icons.trending_up_rounded,
              valueColor: context.qestoColors.positive,
            ),
            StatisticsMetricItem(
              label: 'Остаток',
              value: formatMoney(snapshot.summary.balance, 'RUB'),
              caption: 'доходы − расходы − накопления',
              icon: Icons.savings_outlined,
            ),
            StatisticsMetricItem(
              label: 'Обычный чек',
              value: formatMoney(snapshot.summary.medianCheck.round(), 'RUB'),
              caption: 'половина покупок дешевле',
              icon: Icons.receipt_long_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        StatisticsPeriodBarsCard(
          title: 'Финансовая динамика',
          points: snapshot.periods,
        ),
        const SizedBox(height: 16),
        _ChangeReasonsCard(controller: controller),
        const SizedBox(height: 16),
        StatisticsGroupList(
          title: 'Крупнейшие категории',
          items: snapshot.categories,
          onTap: (item) => _openCategory(context, item.id),
          onShowAll: () =>
              controller.selectSection(StatisticsSection.categories),
        ),
        const SizedBox(height: 16),
        StatisticsGroupList(
          title: 'Крупнейшие продавцы',
          items: snapshot.merchants,
          onTap: (item) => _openMerchant(context, item.id),
          onShowAll: () =>
              controller.selectSection(StatisticsSection.merchants),
        ),
        const SizedBox(height: 16),
        StatisticsInsightsCard(
          insights: snapshot.insights,
          onDetails: (insight) => showInsightCalculation(context, insight),
        ),
      ],
    );
  }

  Widget _empty(ScrollController scrollController) => ListView(
    controller: scrollController,
    padding: const EdgeInsets.all(18),
    children: const [
      EmptyState(message: 'В выбранном периоде пока нет операций'),
    ],
  );

  void _openCategory(BuildContext context, String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            StatisticsCategoryScreen(controller: controller, categoryId: id),
      ),
    );
  }

  void _openMerchant(BuildContext context, String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            StatisticsMerchantScreen(controller: controller, merchant: id),
      ),
    );
  }
}

class ExpensesStatisticsSection extends StatefulWidget {
  const ExpensesStatisticsSection({
    required this.controller,
    required this.scrollController,
    this.showCurrencySelector = false,
    super.key,
  });

  final StatisticsController controller;
  final ScrollController scrollController;
  final bool showCurrencySelector;

  @override
  State<ExpensesStatisticsSection> createState() =>
      _ExpensesStatisticsSectionState();
}

class _ExpensesStatisticsSectionState extends State<ExpensesStatisticsSection> {
  late String _currency;

  @override
  void initState() {
    super.initState();
    final preferred =
        widget.controller.budgetController.user.expenseDisplayCurrency;
    _currency = CbrCurrencyService.expenseDisplayCurrencies.contains(preferred)
        ? preferred
        : 'RUB';
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final snapshot = controller.snapshot;
    if (snapshot.summary.purchaseCount == 0) {
      return ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.all(18),
        children: const [
          EmptyState(message: 'В выбранном периоде пока нет расходов'),
        ],
      );
    }
    final change = snapshot.summary.changePercent;
    final avgChange = snapshot.summary.averageCheckChange;
    return ListView(
      controller: widget.scrollController,
      key: const PageStorageKey('statistics-expenses'),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        if (widget.showCurrencySelector) ...[
          _ExpenseCurrencySelector(
            selected: _currency,
            onSelected: _selectCurrency,
          ),
          const SizedBox(height: 16),
        ],
        StatisticsMetricStrip(
          items: [
            StatisticsMetricItem(
              label: 'Расходы',
              value: _money(snapshot.summary.expenses),
              caption: 'за выбранный период',
              icon: Icons.account_balance_wallet_outlined,
            ),
            StatisticsMetricItem(
              label: 'Изменение',
              value: change == null
                  ? '—'
                  : '${change >= 0 ? '↑' : '↓'} ${change.abs().toStringAsFixed(1)}%',
              caption: 'к периоду такой же длины',
              icon: Icons.trending_up_rounded,
              valueColor: change == null
                  ? context.qestoColors.secondaryText
                  : context.qestoColors.positive,
            ),
            StatisticsMetricItem(
              label: 'Средний чек',
              value: _money(snapshot.summary.averageCheck.round()),
              caption: avgChange == null
                  ? 'нет сравнения'
                  : '${avgChange >= 0 ? '↑' : '↓'} ${avgChange.abs().toStringAsFixed(1)}% к периоду',
              icon: Icons.receipt_long_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        StatisticsLineChartCard(
          title: 'Динамика расходов',
          points: snapshot.daily,
          comparison: snapshot.comparisonDaily,
          currency: _currency,
          amountConverter: _convert,
        ),
        const SizedBox(height: 16),
        QestoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatisticsSectionHeader(title: 'Структура расходов'),
              StatisticsDonut(items: snapshot.categories),
            ],
          ),
        ),
        const SizedBox(height: 16),
        StatisticsGroupList(
          title: 'Категории расходов',
          items: snapshot.categories,
          limit: snapshot.categories.length,
          currency: _currency,
          amountConverter: _convert,
          onTap: (item) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StatisticsCategoryScreen(
                controller: controller,
                categoryId: item.id,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        StatisticsGroupList(
          title: 'Магазины и сервисы',
          items: snapshot.merchants,
          limit: math.min(5, snapshot.merchants.length),
          currency: _currency,
          amountConverter: _convert,
          onTap: (item) => _openMerchant(context, item.id),
        ),
        if (snapshot.merchants.isNotEmpty) ...[
          const SizedBox(height: 16),
          _MerchantPatternsCard(
            controller: controller,
            currency: _currency,
            amountConverter: _convert,
          ),
        ],
        const SizedBox(height: 16),
        _ChangeReasonsCard(
          controller: widget.controller,
          currency: _currency,
          amountConverter: _convert,
        ),
        const SizedBox(height: 16),
        _LargePurchasesCard(
          controller: controller,
          currency: _currency,
          amountConverter: _convert,
        ),
        const SizedBox(height: 16),
        _AmountBucketsCard(
          snapshot: snapshot,
          currency: _currency,
          amountConverter: _convert,
        ),
        const SizedBox(height: 16),
        _LargestTransactionsCard(
          controller: controller,
          currency: _currency,
          amountConverter: _convert,
        ),
      ],
    );
  }

  void _openMerchant(BuildContext context, String merchant) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatisticsMerchantScreen(
          controller: widget.controller,
          merchant: merchant,
        ),
      ),
    );
  }

  int _convert(int amount) =>
      CbrCurrencyService.convertRubles(amount, _currency);

  String _money(int amount) => formatMoney(_convert(amount), _currency);

  Future<void> _selectCurrency(String currency) async {
    if (_currency == currency) return;
    setState(() => _currency = currency);
    await widget.controller.budgetController.updateExpenseDisplayCurrency(
      currency,
    );
  }
}

class _ExpenseCurrencySelector extends StatelessWidget {
  const _ExpenseCurrencySelector({
    required this.selected,
    required this.onSelected,
  });

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final rates = CbrCurrencyService.embeddedSnapshot;
    return QestoCard(
      child: DesktopAdaptiveRow(
        children: [
          Icon(
            Icons.currency_exchange_rounded,
            color: context.qestoColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Валюта расходов',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 3),
                Text(
                  'Курс ЦБ РФ на 22.08.2026: 1 USD = 82,9211 ₽ · 1 EUR = 96,8601 ₽ · 1 CNY = 12,3343 ₽',
                  style: TextStyle(
                    color: context.qestoColors.secondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Wrap(
            spacing: 7,
            children: [
              for (final code in rates.rates.keys)
                ChoiceChip(
                  key: Key('expenses-currency-$code'),
                  label: Text(code),
                  selected: selected == code,
                  onSelected: (_) => onSelected(code),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MerchantPatternsCard extends StatelessWidget {
  const _MerchantPatternsCard({
    required this.controller,
    required this.currency,
    required this.amountConverter,
  });

  final StatisticsController controller;
  final String currency;
  final int Function(int amount) amountConverter;

  @override
  Widget build(BuildContext context) {
    final merchants = controller.snapshot.merchants;
    final concentration = merchants
        .take(5)
        .fold<double>(0, (sum, item) => sum + item.share);
    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatisticsSectionHeader(title: 'Покупательские привычки'),
          const SizedBox(height: 5),
          Text(
            'Частота покупок и средний чек по магазинам и сервисам',
            style: TextStyle(
              fontSize: 12,
              color: context.qestoColors.secondaryText,
            ),
          ),
          const SizedBox(height: 12),
          StatisticsScatter(
            items: merchants,
            currency: currency,
            amountConverter: amountConverter,
            onTap: (item) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StatisticsMerchantScreen(
                  controller: controller,
                  merchant: item.id,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: concentration.clamp(0, 1),
            minHeight: 10,
            borderRadius: QestoGeometry.control,
            backgroundColor: context.qestoColors.border,
          ),
          const SizedBox(height: 8),
          Text(
            'На ${math.min(5, merchants.length)} крупнейших мест приходится ${(concentration * 100).toStringAsFixed(0)}% расходов.',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ChangeReasonsCard extends StatelessWidget {
  const _ChangeReasonsCard({
    required this.controller,
    this.currency = 'RUB',
    this.amountConverter,
  });

  final StatisticsController controller;
  final String currency;
  final int Function(int amount)? amountConverter;

  @override
  Widget build(BuildContext context) {
    final categories =
        controller.snapshot.categories
            .where((item) => item.changePercent != null)
            .toList()
          ..sort(
            (a, b) => _difference(b).abs().compareTo(_difference(a).abs()),
          );
    final totalChange = controller.snapshot.summary.changePercent;
    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatisticsSectionHeader(title: 'Почему показатель изменился'),
          const SizedBox(height: 5),
          Text(
            totalChange == null
                ? 'Для сравнения недостаточно данных'
                : 'Расходы ${totalChange >= 0 ? 'выросли' : 'снизились'} на ${totalChange.abs().toStringAsFixed(1)}%',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (categories.isEmpty)
            const StatisticsInfoBanner(
              message:
                  'Добавьте данные предыдущего периода, чтобы увидеть причины',
            )
          else
            for (final category in categories.take(4))
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StatisticsCategoryScreen(
                      controller: controller,
                      categoryId: category.id,
                    ),
                  ),
                ),
                borderRadius: QestoGeometry.control,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: Color(
                            category.colorValue ??
                                context.qestoColors.primary.toARGB32(),
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          category.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        formatMoney(
                          amountConverter?.call(_difference(category)) ??
                              _difference(category),
                          currency,
                          showSign: true,
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _difference(category) >= 0
                              ? context.qestoColors.positive
                              : context.qestoColors.danger,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: context.qestoColors.secondaryText,
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  int _difference(StatisticsGroupStat item) {
    final change = item.changePercent;
    if (change == null || change <= -100) return 0;
    final previous = item.amount / (1 + change / 100);
    return (item.amount - previous).round();
  }
}

class _LargePurchasesCard extends StatelessWidget {
  const _LargePurchasesCard({
    required this.controller,
    this.currency = 'RUB',
    this.amountConverter,
  });
  final StatisticsController controller;
  final String currency;
  final int Function(int amount)? amountConverter;

  @override
  Widget build(BuildContext context) {
    final all = controller.snapshot.transactions;
    final large = all
        .where(
          (item) =>
              item.type == TransactionType.expense &&
              controller.calculationService.isLargePurchase(item, all),
        )
        .toList();
    final largeAmount = large.fold<int>(0, (sum, item) => sum + item.amount);
    final ordinary = math.max(
      controller.snapshot.summary.expenses - largeAmount,
      0,
    );
    final total = math.max(largeAmount + ordinary, 1);
    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatisticsSectionHeader(title: 'Крупные и обычные покупки'),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: QestoGeometry.control,
            child: Row(
              children: [
                Expanded(
                  flex: math.max(ordinary, 1),
                  child: Container(
                    height: 15,
                    color: context.qestoColors.primary,
                  ),
                ),
                Expanded(
                  flex: math.max(largeAmount, 1),
                  child: Container(
                    height: 15,
                    color: context.qestoColors.orange,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _LegendAmount(
            color: context.qestoColors.primary,
            label: 'Обычные',
            amount: ordinary,
            share: ordinary / total,
            currency: currency,
            amountConverter: amountConverter,
          ),
          const SizedBox(height: 8),
          _LegendAmount(
            color: context.qestoColors.orange,
            label: 'Крупные',
            amount: largeAmount,
            share: largeAmount / total,
            currency: currency,
            amountConverter: amountConverter,
          ),
          const SizedBox(height: 12),
          Text(
            'Автоматическая отметка крупной покупки используется только для подтверждённых операций.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LegendAmount extends StatelessWidget {
  const _LegendAmount({
    required this.color,
    required this.label,
    required this.amount,
    required this.share,
    this.currency = 'RUB',
    this.amountConverter,
  });
  final Color color;
  final String label;
  final int amount;
  final double share;
  final String currency;
  final int Function(int amount)? amountConverter;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(label)),
      Text(
        '${formatMoney(amountConverter?.call(amount) ?? amount, currency)} · ${(share * 100).round()}%',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _AmountBucketsCard extends StatelessWidget {
  const _AmountBucketsCard({
    required this.snapshot,
    this.currency = 'RUB',
    this.amountConverter,
  });
  final StatisticsSnapshot snapshot;
  final String currency;
  final int Function(int amount)? amountConverter;

  @override
  Widget build(BuildContext context) {
    final maxCount = snapshot.buckets.fold<int>(
      1,
      (value, item) => math.max(value, item.count),
    );
    return QestoCard(
      child: Column(
        children: [
          const StatisticsSectionHeader(title: 'Покупки по сумме'),
          const SizedBox(height: 10),
          for (final bucket in snapshot.buckets)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 108,
                    child: Text(
                      bucket.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: bucket.count / maxCount,
                        minHeight: 8,
                        backgroundColor: context.qestoColors.border,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${bucket.count}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          StatisticsInfoBanner(
            message: snapshot.buckets.isEmpty
                ? 'Недостаточно данных'
                : '${snapshot.buckets.first.count} покупок дешевле ${formatMoney(amountConverter?.call(300) ?? 300, currency)} составили ${formatMoney(amountConverter?.call(snapshot.buckets.first.amount) ?? snapshot.buckets.first.amount, currency)}',
          ),
        ],
      ),
    );
  }
}

class _LargestTransactionsCard extends StatelessWidget {
  const _LargestTransactionsCard({
    required this.controller,
    this.currency = 'RUB',
    this.amountConverter,
  });
  final StatisticsController controller;
  final String currency;
  final int Function(int amount)? amountConverter;

  @override
  Widget build(BuildContext context) {
    final items = controller.snapshot.largestTransactions;
    return QestoCard(
      child: Column(
        children: [
          StatisticsSectionHeader(
            title: 'Крупнейшие операции',
            actionLabel: 'Все',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StatisticsOperationsScreen(
                  controller: controller,
                  title: 'Все расходы',
                  transactions: controller.snapshot.transactions
                      .where((item) => item.type == TransactionType.expense)
                      .toList(),
                  transactionSelector: (statistics) => statistics
                      .snapshot
                      .transactions
                      .where((item) => item.type == TransactionType.expense)
                      .toList(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final transaction in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StatisticsOperationsScreen(
                    controller: controller,
                    title: transaction.title ?? 'Операция',
                    transactions: [transaction],
                  ),
                ),
              ),
              leading: CircleAvatar(
                backgroundColor: context.qestoColors.primarySoft,
                child: Icon(
                  Icons.shopping_bag_outlined,
                  color: context.qestoColors.primary,
                ),
              ),
              title: Text(
                controller.calculationService.merchantName(transaction),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(formatDate(transaction.date)),
              trailing: Text(
                formatMoney(
                  amountConverter?.call(transaction.amount) ??
                      transaction.amount,
                  currency,
                ),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> showInsightCalculation(
  BuildContext context,
  StatisticsInsight insight,
) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(insight.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        Text(insight.explanation, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 16),
        const Text(
          'Как рассчитано',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          insight.calculation,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.qestoColors.secondaryText,
          ),
        ),
      ],
    ),
  ),
);
