import 'package:flutter/material.dart';

import '../../../../core/formatters/qesto_formatters.dart';
import '../../../../core/theme/qesto_theme.dart';
import '../../../../core/widgets/nested_screen_header.dart';
import '../../../../core/widgets/qesto_card.dart';
import '../../../../core/widgets/states.dart';
import '../../../../data/models/qesto_models.dart';
import '../../../budget/state/budget_controller.dart';
import '../../domain/models/statistics_models.dart';
import '../state/statistics_controller.dart';
import '../widgets/statistics_charts.dart';
import '../widgets/statistics_components.dart';
import '../widgets/transaction_drilldown_list.dart';

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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
        children: [
          QestoCard(
            child: Text(
              '${currentTransactions.length} операций · '
              '${formatMoney(currentTransactions.fold<int>(0, (sum, item) => sum + (item.type == TransactionType.refund ? -item.amount : item.amount)), currentTransactions.firstOrNull?.currency ?? 'RUB')}'
              ' · ${statisticsRangeLabel(controller.query.period)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 14),
          TransactionDrilldownList(
            controller: controller.budgetController,
            transactions: currentTransactions,
            title: title,
            keyPrefix: 'statistics',
            counterpartyName: controller.calculationService.merchantName,
          ),
        ],
      ),
    );
  }
}

class StatisticsCategoryScreen extends StatefulWidget {
  const StatisticsCategoryScreen({
    required this.controller,
    required this.categoryId,
    this.budgetPeriod,
    this.transactionSelector,
    super.key,
  });

  final StatisticsController controller;
  final String categoryId;
  final BudgetPeriod? budgetPeriod;
  final List<BudgetTransaction> Function(BudgetController)? transactionSelector;

  @override
  State<StatisticsCategoryScreen> createState() =>
      _StatisticsCategoryScreenState();
}

class _StatisticsCategoryScreenState extends State<StatisticsCategoryScreen> {
  StatisticsController get controller => widget.controller;
  String get categoryId => widget.categoryId;

  DateTime? _selectedDay;
  String? _selectedMerchant;
  bool _allMerchants = false;
  final _operationsKey = GlobalKey();

  @override
  void didUpdateWidget(covariant StatisticsCategoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoryId != widget.categoryId) {
      _selectedDay = null;
      _selectedMerchant = null;
      _allMerchants = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final category = controller.budgetController.categories
            .where((item) => item.id == categoryId)
            .firstOrNull;
        final transactions =
            widget.transactionSelector?.call(controller.budgetController) ??
            controller.transactionsForCategory(categoryId);
        final income =
            transactions.isNotEmpty &&
            transactions.every((item) => item.type == TransactionType.income);
        final amounts = transactions
            .map(
              (item) => income
                  ? item.amount
                  : controller.calculationService.signedExpense(item),
            )
            .toList();
        final total = amounts.fold<int>(0, (sum, value) => sum + value);
        final average = controller.calculationService.average(amounts).round();
        final median = controller.calculationService.median(amounts).round();
        final points = income
            ? _incomePoints(transactions)
            : controller.calculationService.dailyPoints(
                controller.query.period,
                transactions,
              );
        final sources = _sourceStats(transactions, income: income);
        final filtered = _filteredTransactions(transactions);
        final currency =
            widget.budgetPeriod?.currency ??
            transactions.firstOrNull?.currency ??
            'RUB';
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
          body: transactions.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: EmptyState(
                    message: 'В выбранном периоде нет операций этой категории',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                  children: [
                    StatisticsMetricStrip(
                      items: [
                        StatisticsMetricItem(
                          label: income ? 'Доходы' : 'Расходы',
                          value: formatMoney(total, currency),
                          caption: statisticsRangeLabel(
                            controller.query.period,
                          ),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                        StatisticsMetricItem(
                          label: income ? 'Поступления' : 'Покупки',
                          value: transactions.length.toString(),
                          caption: 'за выбранный период',
                          icon: Icons.receipt_long_outlined,
                        ),
                        StatisticsMetricItem(
                          label: 'Средний чек',
                          value: formatMoney(average, currency),
                          caption: 'обычный ${formatMoney(median, currency)}',
                          icon: Icons.calculate_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (widget.budgetPeriod case final period?) ...[
                      _budgetSummary(period, categoryId),
                      const SizedBox(height: 14),
                    ],
                    StatisticsLineChartCard(
                      key: const Key('category-chart'),
                      title: 'Динамика категории',
                      points: points,
                      currency: currency,
                      selectedDate: _selectedDay,
                      onDaySelected: _selectDay,
                    ),
                    const SizedBox(height: 14),
                    QestoCard(
                      child: Column(
                        children: [
                          StatisticsSectionHeader(
                            title: income
                                ? 'Источники категории'
                                : 'Продавцы категории',
                          ),
                          const SizedBox(height: 8),
                          for (final merchant
                              in (_allMerchants ? sources : sources.take(5)))
                            ListTile(
                              key: Key('category-source-${merchant.name}'),
                              contentPadding: EdgeInsets.zero,
                              selected: _selectedMerchant == merchant.name,
                              onTap: () => _selectMerchant(merchant.name),
                              title: Text(
                                merchant.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                merchant.count.toString() +
                                    (income ? ' поступлений' : ' покупок'),
                              ),
                              trailing: Text(
                                formatMoney(merchant.amount, currency),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          if (sources.length > 5)
                            TextButton(
                              onPressed: () => setState(
                                () => _allMerchants = !_allMerchants,
                              ),
                              child: Text(
                                _allMerchants ? 'Свернуть' : 'Показать всех',
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TransactionDrilldownList(
                      key: _operationsKey,
                      keyPrefix: 'category',
                      controller: controller.budgetController,
                      transactions: filtered,
                      title: 'Операции',
                      counterpartyName: (item) =>
                          _sourceName(item, income: income),
                      selectedDay: _selectedDay,
                      selectedCounterparty: _selectedMerchant,
                      onClearDay: _selectedDay == null
                          ? null
                          : () => setState(() => _selectedDay = null),
                      onClearCounterparty: _selectedMerchant == null
                          ? null
                          : () => setState(() => _selectedMerchant = null),
                    ),
                  ],
                ),
        );
      },
    );
  }

  List<StatisticsDailyPoint> _incomePoints(
    List<BudgetTransaction> transactions,
  ) {
    final byDay = <DateTime, List<BudgetTransaction>>{};
    for (final transaction in transactions) {
      final day = DateUtils.dateOnly(transaction.date);
      byDay.putIfAbsent(day, () => []).add(transaction);
    }
    var running = 0;
    return [
      for (
        var day = controller.query.period.start;
        !day.isAfter(controller.query.period.end);
        day = day.add(const Duration(days: 1))
      )
        StatisticsDailyPoint(
          date: day,
          amount: _incomeForDay(byDay[day] ?? const []),
          cumulative: running += _incomeForDay(byDay[day] ?? const []),
          count: (byDay[day] ?? const []).length,
        ),
    ];
  }

  int _incomeForDay(List<BudgetTransaction> rows) =>
      rows.fold(0, (sum, item) => sum + item.amount);

  String _sourceName(BudgetTransaction item, {required bool income}) {
    final name = controller.calculationService.merchantName(item).trim();
    if (income && name == 'Неизвестный продавец') {
      return 'Неизвестный источник';
    }
    return name;
  }

  List<_CategorySource> _sourceStats(
    List<BudgetTransaction> transactions, {
    required bool income,
  }) {
    final amounts = <String, int>{};
    final counts = <String, int>{};
    for (final item in transactions) {
      final name = _sourceName(item, income: income);
      final amount = income
          ? item.amount
          : controller.calculationService.signedExpense(item);
      amounts.update(name, (value) => value + amount, ifAbsent: () => amount);
      counts.update(name, (value) => value + 1, ifAbsent: () => 1);
    }
    return [
      for (final entry in amounts.entries)
        _CategorySource(
          name: entry.key,
          amount: entry.value,
          count: counts[entry.key] ?? 0,
        ),
    ]..sort((left, right) {
      final amount = right.amount.compareTo(left.amount);
      return amount != 0 ? amount : left.name.compareTo(right.name);
    });
  }

  void _scrollToOperations() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _operationsKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 260),
          alignment: 0.1,
        );
      }
    });
  }

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = DateUtils.isSameDay(_selectedDay, day) ? null : day;
    });
    _scrollToOperations();
  }

  void _selectMerchant(String name) {
    setState(() {
      _selectedMerchant = _selectedMerchant == name ? null : name;
    });
    _scrollToOperations();
  }

  List<BudgetTransaction> _filteredTransactions(
    List<BudgetTransaction> transactions,
  ) {
    final income =
        transactions.isNotEmpty &&
        transactions.every((item) => item.type == TransactionType.income);
    final rows = transactions.where((item) {
      if (_selectedDay != null &&
          !DateUtils.isSameDay(item.date, _selectedDay)) {
        return false;
      }
      if (_selectedMerchant != null &&
          _sourceName(item, income: income) != _selectedMerchant) {
        return false;
      }
      return true;
    }).toList();
    return rows;
  }

  Widget _budgetSummary(BudgetPeriod period, String id) {
    final status = controller.budgetController
        .categoryPlansFor(period)
        .where((item) => item.category.id == id)
        .firstOrNull;
    if (status == null) return const SizedBox.shrink();
    final progress = status.plannedAmount <= 0
        ? 0.0
        : status.progress.clamp(0.0, 1.0).toDouble();
    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'План категории',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            status.plannedAmount == 0
                ? 'План не задан'
                : 'План ${formatMoney(status.plannedAmount, period.currency)}'
                      ' · Осталось ${formatMoney(status.remaining, period.currency)}',
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress,
            color: status.isExceeded
                ? context.qestoColors.orange
                : Color(status.category.colorValue),
          ),
        ],
      ),
    );
  }
}

class _CategorySource {
  const _CategorySource({
    required this.name,
    required this.amount,
    required this.count,
  });
  final String name;
  final int amount;
  final int count;
}

class StatisticsMerchantScreen extends StatefulWidget {
  const StatisticsMerchantScreen({
    required this.controller,
    required this.merchant,
    super.key,
  });

  final StatisticsController controller;
  final String merchant;

  @override
  State<StatisticsMerchantScreen> createState() =>
      _StatisticsMerchantScreenState();
}

class _StatisticsMerchantScreenState extends State<StatisticsMerchantScreen> {
  DateTime? _selectedDay;
  final _operationsKey = GlobalKey();

  void _selectDay(DateTime day) {
    setState(
      () => _selectedDay = DateUtils.isSameDay(_selectedDay, day) ? null : day,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _operationsKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 260),
          alignment: 0.1,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final merchant = widget.merchant;
        final stat = controller.snapshot.merchants
            .where((item) => item.id == merchant)
            .firstOrNull;
        final transactions = controller.transactionsForMerchant(merchant);
        final selectedTransactions = _selectedDay == null
            ? transactions
            : transactions
                  .where((item) => DateUtils.isSameDay(item.date, _selectedDay))
                  .toList();
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
                      key: const Key('merchant-chart'),
                      title: 'Динамика у продавца',
                      points: points,
                      selectedDate: _selectedDay,
                      onDaySelected: _selectDay,
                    ),
                    const SizedBox(height: 14),
                    TransactionDrilldownList(
                      key: _operationsKey,
                      keyPrefix: 'merchant',
                      controller: controller.budgetController,
                      transactions: selectedTransactions,
                      title: 'Все операции этого продавца',
                      counterpartyName:
                          controller.calculationService.merchantName,
                      selectedDay: _selectedDay,
                      onClearDay: _selectedDay == null
                          ? null
                          : () => setState(() => _selectedDay = null),
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
