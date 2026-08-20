import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/budget/widgets/budget_category_icon.dart';
import '../desktop_financial_helpers.dart';
import '../overview/desktop_overview_data.dart';
import '../overview/overview_expense_map.dart';
import '../overview/overview_expense_trend_chart.dart';
import '../widgets/desktop_components.dart';

class DesktopDashboardPage extends StatefulWidget {
  const DesktopDashboardPage({
    required this.controller,
    required this.period,
    required this.onOpenTransactions,
    required this.onOpenBudget,
    required this.onOpenRecurring,
    required this.onOpenTransaction,
    super.key,
  });

  final BudgetController controller;
  final BudgetPeriod period;
  final VoidCallback onOpenTransactions;
  final VoidCallback onOpenBudget;
  final VoidCallback onOpenRecurring;
  final ValueChanged<String> onOpenTransaction;

  @override
  State<DesktopDashboardPage> createState() => _DesktopDashboardPageState();
}

class _DesktopDashboardPageState extends State<DesktopDashboardPage> {
  late DesktopOverviewData _data;
  var _primaryMetric = OverviewPrimaryMetric.expenses;
  var _capitalMetric = OverviewCapitalMetric.capital;
  var _granularity = OverviewTrendGranularity.days;
  var _transactionSort = OverviewTransactionSort.dateDescending;

  @override
  void initState() {
    super.initState();
    _data = DesktopOverviewData.build(widget.controller, widget.period);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant DesktopDashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.period.id != widget.period.id) {
      _data = DesktopOverviewData.build(widget.controller, widget.period);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    setState(() {
      _data = DesktopOverviewData.build(widget.controller, widget.period);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('desktop-overview-scroll'),
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Добрый день',
            style: TextStyle(
              color: QestoColors.text,
              fontSize: 23,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Вот, что происходит с вашими деньгами',
            style: TextStyle(
              color: QestoColors.secondaryText,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          _OverviewMetricGrid(
            data: _data,
            primaryMetric: _primaryMetric,
            capitalMetric: _capitalMetric,
            onPrimaryMetricChanged: (value) => setState(() {
              _primaryMetric = value;
            }),
            onCapitalMetricChanged: (value) => setState(() {
              _capitalMetric = value;
            }),
          ),
          const SizedBox(height: 16),
          _OverviewVisuals(
            data: _data,
            granularity: _granularity,
            onGranularityChanged: (value) => setState(() {
              _granularity = value;
            }),
          ),
          const SizedBox(height: 16),
          _OverviewPlanningRow(
            controller: widget.controller,
            data: _data,
            onOpenTransactions: widget.onOpenTransactions,
            onOpenBudget: widget.onOpenBudget,
            onOpenRecurring: widget.onOpenRecurring,
          ),
          const SizedBox(height: 16),
          _RecentTransactionsCard(
            controller: widget.controller,
            data: _data,
            sort: _transactionSort,
            onSortChanged: (value) => setState(() {
              _transactionSort = value;
            }),
            onOpenAll: widget.onOpenTransactions,
            onOpenTransaction: widget.onOpenTransaction,
          ),
        ],
      ),
    );
  }
}

class _OverviewMetricGrid extends StatelessWidget {
  const _OverviewMetricGrid({
    required this.data,
    required this.primaryMetric,
    required this.capitalMetric,
    required this.onPrimaryMetricChanged,
    required this.onCapitalMetricChanged,
  });

  final DesktopOverviewData data;
  final OverviewPrimaryMetric primaryMetric;
  final OverviewCapitalMetric capitalMetric;
  final ValueChanged<OverviewPrimaryMetric> onPrimaryMetricChanged;
  final ValueChanged<OverviewCapitalMetric> onCapitalMetricChanged;

  @override
  Widget build(BuildContext context) {
    final primaryIsExpense = primaryMetric == OverviewPrimaryMetric.expenses;
    final primaryValue = primaryIsExpense ? data.expenses : data.income;
    final primaryLabel = primaryIsExpense ? 'Расходы' : 'Доходы';
    final capitalValue = switch (capitalMetric) {
      OverviewCapitalMetric.capital => data.capital,
      OverviewCapitalMetric.investments => data.investments,
      OverviewCapitalMetric.savings => data.savings,
    };
    final capitalLabel = switch (capitalMetric) {
      OverviewCapitalMetric.capital => 'Капитал',
      OverviewCapitalMetric.investments => 'Инвестиции',
      OverviewCapitalMetric.savings => 'Накопления',
    };
    final capitalDetail = switch (capitalMetric) {
      OverviewCapitalMetric.capital => 'Общий капитал',
      OverviewCapitalMetric.investments => 'Инвестиционные активы',
      OverviewCapitalMetric.savings => 'Накопительные счета',
    };

    final cards = <Widget>[
      _MetricCard(
        key: const Key('overview-primary-metric'),
        label: primaryLabel,
        value: formatMoney(primaryValue, data.currency),
        detail:
            '$primaryLabel за ${formatBudgetPeriod(data.period.month, data.period.year)}',
        valueColor: primaryIsExpense
            ? QestoColors.negative
            : QestoColors.positive,
        control: _MetricMenu<OverviewPrimaryMetric>(
          value: primaryMetric,
          tooltip: 'Выбрать доходы или расходы',
          onSelected: onPrimaryMetricChanged,
          items: const {
            OverviewPrimaryMetric.expenses: 'Расходы',
            OverviewPrimaryMetric.income: 'Доходы',
          },
        ),
      ),
      _MetricCard(
        key: const Key('overview-cash-flow'),
        label: 'Кэшфлоу',
        value: formatMoney(data.cashFlow, data.currency, showSign: true),
        detail: 'Доходы − расходы',
        valueColor: data.cashFlow == 0
            ? QestoColors.text
            : data.cashFlow > 0
            ? QestoColors.positive
            : QestoColors.negative,
      ),
      _MetricCard(
        key: const Key('overview-capital-metric'),
        label: capitalLabel,
        value: formatMoney(capitalValue, data.currency),
        detail: capitalDetail,
        control: _MetricMenu<OverviewCapitalMetric>(
          value: capitalMetric,
          tooltip: 'Выбрать показатель капитала',
          onSelected: onCapitalMetricChanged,
          items: const {
            OverviewCapitalMetric.capital: 'Капитал',
            OverviewCapitalMetric.investments: 'Инвестиции',
            OverviewCapitalMetric.savings: 'Накопления',
          },
        ),
      ),
      _MetricCard(
        key: const Key('desktop-free-to-spend'),
        label: 'Свободные деньги',
        value: data.freeToSpend == null
            ? 'Не рассчитаны'
            : formatMoney(data.freeToSpend!, data.currency),
        detail: data.freeToSpend == null
            ? 'Назначьте бюджет'
            : 'Доступно к тратам',
        valueColor: data.freeToSpend == null
            ? QestoColors.secondaryText
            : data.freeToSpend! >= 0
            ? QestoColors.positive
            : QestoColors.negative,
        control: const Tooltip(
          message: 'Дополнительные показатели появятся позже',
          child: _MetricControlIcon(),
        ),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 4
            : constraints.maxWidth >= 640
            ? 2
            : 1;
        const gap = 14.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(width: width, height: 136, child: card),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    this.valueColor = QestoColors.text,
    this.control,
    super.key,
  });

  final String label;
  final String value;
  final String detail;
  final Color valueColor;
  final Widget? control;

  @override
  Widget build(BuildContext context) {
    return DesktopCard(
      padding: const EdgeInsets.fromLTRB(18, 15, 14, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: QestoColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ?control,
            ],
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.qestoTypography.display(
              TextStyle(
                color: valueColor,
                fontSize: value.length > 16 ? 20 : 25,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.65,
              ),
              numeric: true,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: QestoColors.secondaryText,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricMenu<T> extends StatelessWidget {
  const _MetricMenu({
    required this.value,
    required this.tooltip,
    required this.onSelected,
    required this.items,
  });

  final T value;
  final String tooltip;
  final ValueChanged<T> onSelected;
  final Map<T, String> items;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      initialValue: value,
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final entry in items.entries)
          PopupMenuItem<T>(
            value: entry.key,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: entry.key == value
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: QestoColors.primary,
                        )
                      : null,
                ),
                Text(entry.value),
              ],
            ),
          ),
      ],
      child: const _MetricControlIcon(),
    );
  }
}

class _MetricControlIcon extends StatelessWidget {
  const _MetricControlIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        border: Border.all(color: QestoColors.border),
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 18,
        color: QestoColors.text,
      ),
    );
  }
}

class _OverviewVisuals extends StatelessWidget {
  const _OverviewVisuals({
    required this.data,
    required this.granularity,
    required this.onGranularityChanged,
  });

  final DesktopOverviewData data;
  final OverviewTrendGranularity granularity;
  final ValueChanged<OverviewTrendGranularity> onGranularityChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 1050;
        final flowHeight = math
            .max(430.0, (data.flow?.branches.length ?? 1) * 62 + 92)
            .toDouble();
        final chart = DesktopCard(
          key: const Key('overview-expense-trend'),
          child: Column(
            children: [
              DesktopSectionHeader(
                title: 'Расходы',
                trailing: _CompactMenu<OverviewTrendGranularity>(
                  value: granularity,
                  onSelected: onGranularityChanged,
                  items: const {
                    OverviewTrendGranularity.days: 'По дням',
                    OverviewTrendGranularity.weeks: 'По неделям',
                  },
                ),
              ),
              const SizedBox(height: 10),
              OverviewExpenseTrendChart(
                points: data.trend,
                currency: data.currency,
                granularity: granularity,
                height: stacked ? 310 : flowHeight,
              ),
            ],
          ),
        );
        final map = DesktopCard(
          key: const Key('overview-expense-map'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DesktopSectionHeader(
                title: 'Карта расходов',
                subtitle: 'Источники → общий поток → направления → операции',
              ),
              const SizedBox(height: 8),
              if (data.flow case final flow?)
                OverviewExpenseMap(data: flow)
              else
                SizedBox(
                  height: stacked ? 310 : flowHeight,
                  child: const _BlockEmptyState(
                    icon: Icons.account_tree_outlined,
                    message:
                        'Добавьте доходы за выбранный период, чтобы увидеть движение денег.',
                  ),
                ),
            ],
          ),
        );
        if (stacked) {
          return Column(children: [chart, const SizedBox(height: 16), map]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: chart),
            const SizedBox(width: 16),
            Expanded(flex: 8, child: map),
          ],
        );
      },
    );
  }
}

class _CompactMenu<T> extends StatelessWidget {
  const _CompactMenu({
    required this.value,
    required this.onSelected,
    required this.items,
  });

  final T value;
  final ValueChanged<T> onSelected;
  final Map<T, String> items;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final entry in items.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: QestoColors.surface,
          border: Border.all(color: QestoColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              items[value]!,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 5),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 17),
          ],
        ),
      ),
    );
  }
}

class _OverviewPlanningRow extends StatelessWidget {
  const _OverviewPlanningRow({
    required this.controller,
    required this.data,
    required this.onOpenTransactions,
    required this.onOpenBudget,
    required this.onOpenRecurring,
  });

  final BudgetController controller;
  final DesktopOverviewData data;
  final VoidCallback onOpenTransactions;
  final VoidCallback onOpenBudget;
  final VoidCallback onOpenRecurring;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _TopExpensesCard(data: data, onOpenAll: onOpenTransactions),
      _CategoryBudgetsCard(data: data, onOpenAll: onOpenBudget),
      _PlannedExpensesCard(
        controller: controller,
        data: data,
        onOpenAll: onOpenRecurring,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 16.0;
        final columns = constraints.maxWidth >= 960
            ? 3
            : constraints.maxWidth >= 720
            ? 2
            : 1;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(width: width, height: 390, child: card),
          ],
        );
      },
    );
  }
}

class _TopExpensesCard extends StatelessWidget {
  const _TopExpensesCard({required this.data, required this.onOpenAll});

  final DesktopOverviewData data;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    return DesktopCard(
      key: const Key('overview-top-expenses'),
      child: Column(
        children: [
          DesktopSectionHeader(
            title: 'Топ расходов',
            trailing: _CircleArrowButton(
              tooltip: 'Показать все расходы',
              onPressed: onOpenAll,
            ),
          ),
          const SizedBox(height: 11),
          if (data.topExpenses.isEmpty)
            const Expanded(
              child: _BlockEmptyState(
                icon: Icons.receipt_long_outlined,
                message: 'Расходов за выбранный период пока нет.',
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  for (var index = 0; index < data.topExpenses.length; index++)
                    Expanded(
                      child: _TopExpenseRow(
                        rank: index + 1,
                        transaction: data.topExpenses[index],
                        total: data.expenses,
                        currency: data.currency,
                      ),
                    ),
                ],
              ),
            ),
          _ShowAllButton(onPressed: onOpenAll),
        ],
      ),
    );
  }
}

class _TopExpenseRow extends StatelessWidget {
  const _TopExpenseRow({
    required this.rank,
    required this.transaction,
    required this.total,
    required this.currency,
  });

  final int rank;
  final BudgetTransaction transaction;
  final int total;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final title = desktopTransactionTitle(transaction);
    final percent = total <= 0 ? 0.0 : transaction.amount / total;
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: QestoColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: QestoColors.primarySoft,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '$rank',
              style: const TextStyle(
                color: QestoColors.primary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 9),
          _MerchantMark(title: title),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDate(transaction.date, includeYear: true),
                  style: const TextStyle(
                    color: QestoColors.secondaryText,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatMoney(transaction.amount, currency),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                formatPercent(percent, decimals: 1),
                style: const TextStyle(
                  color: QestoColors.secondaryText,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryBudgetsCard extends StatelessWidget {
  const _CategoryBudgetsCard({required this.data, required this.onOpenAll});

  final DesktopOverviewData data;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final relative = data.categoryBudgets.firstOrNull?.isRelative ?? false;
    return DesktopCard(
      key: const Key('overview-category-budgets'),
      child: Column(
        children: [
          DesktopSectionHeader(
            title: 'Бюджет по категориям',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (relative)
                  const Tooltip(
                    message:
                        'Бюджеты не заданы — шкала сравнивает объём расходов по категориям.',
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: QestoColors.secondaryText,
                    ),
                  ),
                const SizedBox(width: 7),
                _CircleArrowButton(
                  tooltip: 'Открыть бюджет',
                  onPressed: onOpenAll,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (data.categoryBudgets.isEmpty)
            const Expanded(
              child: _BlockEmptyState(
                icon: Icons.donut_large_outlined,
                message: 'Категории расходов появятся после первых операций.',
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  for (final row in data.categoryBudgets)
                    Expanded(
                      child: _CategoryBudgetRow(row: row, data: data),
                    ),
                ],
              ),
            ),
          _ShowAllButton(onPressed: onOpenAll),
        ],
      ),
    );
  }
}

class _CategoryBudgetRow extends StatelessWidget {
  const _CategoryBudgetRow({required this.row, required this.data});

  final OverviewCategoryBudgetRow row;
  final DesktopOverviewData data;

  @override
  Widget build(BuildContext context) {
    final progressColor = row.isRelative
        ? row.color
        : row.progress > 1
        ? QestoColors.negative
        : row.progress >= 0.85
        ? QestoColors.warning
        : row.color;
    return Row(
      children: [
        BudgetCategoryIcon(iconKey: row.iconKey, color: row.color, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${(row.progress * 100).round()}%',
                    style: const TextStyle(
                      color: QestoColors.secondaryText,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              DesktopProgressBar(
                value: row.progress,
                color: progressColor,
                height: 6,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 70,
          child: Text(
            formatMoney(row.spent, data.currency),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _PlannedExpensesCard extends StatelessWidget {
  const _PlannedExpensesCard({
    required this.controller,
    required this.data,
    required this.onOpenAll,
  });

  final BudgetController controller;
  final DesktopOverviewData data;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    return DesktopCard(
      key: const Key('overview-planned-expenses'),
      child: Column(
        children: [
          DesktopSectionHeader(
            title: 'Планируемые траты',
            trailing: _CircleArrowButton(
              tooltip: 'Открыть регулярные платежи',
              onPressed: onOpenAll,
            ),
          ),
          const SizedBox(height: 10),
          if (data.plannedExpenses.isEmpty)
            const Expanded(
              child: _BlockEmptyState(
                icon: Icons.event_available_outlined,
                message: 'Ближайших запланированных платежей пока нет.',
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  for (final expense in data.plannedExpenses)
                    Expanded(
                      child: _PlannedExpenseRow(
                        controller: controller,
                        expense: expense,
                      ),
                    ),
                ],
              ),
            ),
          _ShowAllButton(onPressed: onOpenAll),
        ],
      ),
    );
  }
}

class _PlannedExpenseRow extends StatelessWidget {
  const _PlannedExpenseRow({required this.controller, required this.expense});

  final BudgetController controller;
  final UpcomingExpense expense;

  @override
  Widget build(BuildContext context) {
    final category = controller.categories
        .where((item) => item.id == expense.categoryId)
        .firstOrNull;
    final color = category == null
        ? QestoColors.purple
        : Color(category.colorValue);
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: QestoColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 35,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${expense.plannedDate.day}'.padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _shortMonth(expense.plannedDate.month),
                  style: const TextStyle(
                    color: QestoColors.secondaryText,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          BudgetCategoryIcon(
            iconKey: category?.iconKey ?? 'subscriptions',
            color: color,
            size: 32,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _upcomingType(expense),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: QestoColors.secondaryText,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatMoney(expense.amount, expense.currency),
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  static String _upcomingType(UpcomingExpense expense) =>
      switch (expense.source) {
        UpcomingExpenseSource.subscription => 'Подписка',
        UpcomingExpenseSource.detectedRecurring => 'Регулярный платёж',
        UpcomingExpenseSource.manual =>
          expense.isRecurring ? 'Регулярный платёж' : 'Платёж',
      };
}

class _RecentTransactionsCard extends StatelessWidget {
  const _RecentTransactionsCard({
    required this.controller,
    required this.data,
    required this.sort,
    required this.onSortChanged,
    required this.onOpenAll,
    required this.onOpenTransaction,
  });

  final BudgetController controller;
  final DesktopOverviewData data;
  final OverviewTransactionSort sort;
  final ValueChanged<OverviewTransactionSort> onSortChanged;
  final VoidCallback onOpenAll;
  final ValueChanged<String> onOpenTransaction;

  @override
  Widget build(BuildContext context) {
    final transactions = _sorted(data.periodTransactions).take(7).toList();
    return DesktopCard(
      key: const Key('overview-recent-transactions'),
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 12),
      child: Column(
        children: [
          DesktopSectionHeader(
            title: 'Последние операции',
            trailing: _ShowAllButton(onPressed: onOpenAll),
          ),
          const SizedBox(height: 12),
          if (transactions.isEmpty)
            const SizedBox(
              height: 180,
              child: _BlockEmptyState(
                icon: Icons.swap_horiz_rounded,
                message: 'Операций за выбранный период пока нет.',
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 880;
                return Column(
                  children: [
                    _TransactionsHeader(
                      compact: compact,
                      sort: sort,
                      onDatePressed: () => onSortChanged(
                        sort == OverviewTransactionSort.dateDescending
                            ? OverviewTransactionSort.dateAscending
                            : OverviewTransactionSort.dateDescending,
                      ),
                      onAmountPressed: () => onSortChanged(
                        sort == OverviewTransactionSort.amountDescending
                            ? OverviewTransactionSort.amountAscending
                            : OverviewTransactionSort.amountDescending,
                      ),
                    ),
                    for (final transaction in transactions)
                      _TransactionRow(
                        controller: controller,
                        transaction: transaction,
                        compact: compact,
                        onTap: () => onOpenTransaction(transaction.id),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  List<BudgetTransaction> _sorted(List<BudgetTransaction> source) {
    final values = source.toList(growable: false);
    values.sort(
      (left, right) => switch (sort) {
        OverviewTransactionSort.dateDescending => right.date.compareTo(
          left.date,
        ),
        OverviewTransactionSort.dateAscending => left.date.compareTo(
          right.date,
        ),
        OverviewTransactionSort.amountDescending => desktopSignedAmount(
          right,
        ).compareTo(desktopSignedAmount(left)),
        OverviewTransactionSort.amountAscending => desktopSignedAmount(
          left,
        ).compareTo(desktopSignedAmount(right)),
      },
    );
    return values;
  }
}

class _TransactionsHeader extends StatelessWidget {
  const _TransactionsHeader({
    required this.compact,
    required this.sort,
    required this.onDatePressed,
    required this.onAmountPressed,
  });

  final bool compact;
  final OverviewTransactionSort sort;
  final VoidCallback onDatePressed;
  final VoidCallback onAmountPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 35,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: QestoColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 15,
            child: _SortHeader(
              label: 'Дата',
              active:
                  sort == OverviewTransactionSort.dateDescending ||
                  sort == OverviewTransactionSort.dateAscending,
              ascending: sort == OverviewTransactionSort.dateAscending,
              onPressed: onDatePressed,
            ),
          ),
          const Expanded(flex: 34, child: _TableHeader('Операция / описание')),
          const Expanded(flex: 20, child: _TableHeader('Категория')),
          Expanded(
            flex: 18,
            child: _SortHeader(
              label: 'Сумма',
              active:
                  sort == OverviewTransactionSort.amountDescending ||
                  sort == OverviewTransactionSort.amountAscending,
              ascending: sort == OverviewTransactionSort.amountAscending,
              onPressed: onAmountPressed,
              alignRight: true,
            ),
          ),
          if (!compact) const Expanded(flex: 22, child: _TableHeader('Счёт')),
          const Expanded(flex: 16, child: _TableHeader('Тип / статус')),
          const SizedBox(width: 32),
        ],
      ),
    );
  }
}

class _SortHeader extends StatelessWidget {
  const _SortHeader({
    required this.label,
    required this.active,
    required this.ascending,
    required this.onPressed,
    this.alignRight = false,
  });

  final String label;
  final bool active;
  final bool ascending;
  final VoidCallback onPressed;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Row(
        mainAxisAlignment: alignRight
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? QestoColors.primary : QestoColors.secondaryText,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            !active
                ? Icons.unfold_more_rounded
                : ascending
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 13,
            color: active ? QestoColors.primary : QestoColors.secondaryText,
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: QestoColors.secondaryText,
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.controller,
    required this.transaction,
    required this.compact,
    required this.onTap,
  });

  final BudgetController controller;
  final BudgetTransaction transaction;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = desktopTransactionTitle(transaction);
    final amount = desktopSignedAmount(transaction);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: QestoColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 15,
              child: Text(
                formatDate(transaction.date, includeYear: true),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              flex: 34,
              child: Row(
                children: [
                  _MerchantMark(title: title, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (transaction.description case final description?)
                          Text(
                            description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: QestoColors.secondaryText,
                              fontSize: 8.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 20,
              child: Text(
                desktopCategoryName(controller, transaction),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: QestoColors.secondaryText,
                  fontSize: 9.5,
                ),
              ),
            ),
            Expanded(
              flex: 18,
              child: Text(
                formatMoney(amount, transaction.currency, showSign: amount > 0),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: amount > 0 ? QestoColors.positive : QestoColors.text,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (!compact)
              Expanded(
                flex: 22,
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Text(
                    desktopAccountName(controller, transaction),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: QestoColors.secondaryText,
                      fontSize: 9.5,
                    ),
                  ),
                ),
              ),
            Expanded(
              flex: 16,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _TransactionTypePill(transaction: transaction),
              ),
            ),
            SizedBox(
              width: 32,
              child: IconButton(
                tooltip: 'Открыть операцию',
                onPressed: onTap,
                icon: const Icon(Icons.more_horiz_rounded, size: 17),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionTypePill extends StatelessWidget {
  const _TransactionTypePill({required this.transaction});

  final BudgetTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (transaction.type) {
      TransactionType.income || TransactionType.refund => (
        'Доход',
        QestoColors.positive,
        Icons.arrow_upward_rounded,
      ),
      TransactionType.transfer => (
        'Перевод',
        QestoColors.primary,
        Icons.swap_horiz_rounded,
      ),
      TransactionType.savingsTransfer => (
        'Накопление',
        QestoColors.purple,
        Icons.savings_outlined,
      ),
      TransactionType.investment => (
        'Инвестиция',
        QestoColors.purple,
        Icons.trending_up_rounded,
      ),
      TransactionType.expense => (
        'Расход',
        QestoColors.negative,
        Icons.arrow_downward_rounded,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MerchantMark extends StatelessWidget {
  const _MerchantMark({required this.title, this.size = 32});

  final String title;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = _merchantColor(title);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        title.trim().isEmpty
            ? '•'
            : title.trim().characters.first.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  static Color _merchantColor(String value) {
    const palette = [
      QestoColors.primary,
      QestoColors.purple,
      QestoColors.orange,
      QestoColors.positive,
      Color(0xFF3FA7A0),
    ];
    return palette[value.hashCode.abs() % palette.length];
  }
}

class _CircleArrowButton extends StatelessWidget {
  const _CircleArrowButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: const Icon(Icons.chevron_right_rounded, size: 18),
      style: IconButton.styleFrom(
        minimumSize: const Size(31, 31),
        maximumSize: const Size(31, 31),
        padding: EdgeInsets.zero,
        side: const BorderSide(color: QestoColors.border),
        foregroundColor: QestoColors.secondaryText,
      ),
    );
  }
}

class _ShowAllButton extends StatelessWidget {
  const _ShowAllButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.arrow_forward_rounded, size: 14),
        label: const Text('Показать все'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
          visualDensity: VisualDensity.compact,
          foregroundColor: QestoColors.primary,
          textStyle: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _BlockEmptyState extends StatelessWidget {
  const _BlockEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 290),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: QestoColors.primarySoft,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 21, color: QestoColors.primary),
            ),
            const SizedBox(height: 11),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: QestoColors.secondaryText,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _shortMonth(int month) => const [
  'янв',
  'фев',
  'мар',
  'апр',
  'май',
  'июн',
  'июл',
  'авг',
  'сен',
  'окт',
  'ноя',
  'дек',
][(month - 1).clamp(0, 11)];

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
