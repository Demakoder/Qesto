import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../design_system/qesto_window.dart';
import '../../design_system/qesto_expandable_tool.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/category_details_screen.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/budget/widgets/budget_category_icon.dart';
import '../desktop_financial_helpers.dart';
import '../overview/desktop_overview_data.dart';
import '../overview/overview_drilldown_panel.dart';
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
    required this.onOpenFilteredTransactions,
    super.key,
  });

  final BudgetController controller;
  final BudgetPeriod period;
  final VoidCallback onOpenTransactions;
  final VoidCallback onOpenBudget;
  final VoidCallback onOpenRecurring;
  final ValueChanged<String> onOpenTransaction;
  final ValueChanged<List<String>> onOpenFilteredTransactions;

  @override
  State<DesktopDashboardPage> createState() => _DesktopDashboardPageState();
}

class _DesktopDashboardPageState extends State<DesktopDashboardPage> {
  late DesktopOverviewData _data;
  var _primaryMetric = OverviewPrimaryMetric.expenses;
  var _capitalMetric = OverviewCapitalMetric.capital;
  var _granularity = OverviewTrendGranularity.days;
  var _transactionSort = OverviewTransactionSort.dateDescending;
  var _compactFlow = true;
  var _refreshing = false;

  DesktopOverviewData _buildOverviewData() => DesktopOverviewData.build(
    widget.controller,
    widget.period,
    flowCategoryLimit: _compactFlow ? 4 : null,
  );

  @override
  void initState() {
    super.initState();
    _data = _buildOverviewData();
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
      _data = _buildOverviewData();
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
      _data = _buildOverviewData();
    });
  }

  Future<void> _refreshLocalData() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      widget.controller.refreshLocalReadModel();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось обновить данные обзора')),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _openTrendSelection(OverviewTrendSelection selection) {
    showOverviewDrilldownPanel(
      context,
      controller: widget.controller,
      data: OverviewDrilldownData.forTrend(
        controller: widget.controller,
        period: widget.period,
        selection: selection,
      ),
      onOpenTransaction: widget.onOpenTransaction,
      onOpenTransactions: widget.onOpenFilteredTransactions,
    );
  }

  void _openFlowSelection(OverviewFlowSelection selection) {
    if (selection.kind == OverviewFlowSelectionKind.category &&
        widget.controller.categories.any((item) => item.id == selection.id)) {
      _openCategoryDetails(selection.id);
      return;
    }
    showOverviewDrilldownPanel(
      context,
      controller: widget.controller,
      data: OverviewDrilldownData.forFlow(
        controller: widget.controller,
        period: widget.period,
        selection: selection,
      ),
      onOpenTransaction: widget.onOpenTransaction,
      onOpenTransactions: widget.onOpenFilteredTransactions,
    );
  }

  void _openMerchant(BudgetTransaction transaction) {
    showOverviewDrilldownPanel(
      context,
      controller: widget.controller,
      data: OverviewDrilldownData.forMerchant(
        controller: widget.controller,
        period: widget.period,
        selected: transaction,
      ),
      onOpenTransaction: widget.onOpenTransaction,
      onOpenTransactions: widget.onOpenFilteredTransactions,
    );
  }

  void _openCategory(OverviewCategoryBudgetRow category) {
    if (widget.controller.categories.any((item) => item.id == category.id)) {
      _openCategoryDetails(category.id);
      return;
    }
    showOverviewDrilldownPanel(
      context,
      controller: widget.controller,
      data: OverviewDrilldownData.forCategory(
        controller: widget.controller,
        period: widget.period,
        category: category,
      ),
      onOpenTransaction: widget.onOpenTransaction,
      onOpenTransactions: widget.onOpenFilteredTransactions,
    );
  }

  void _openCategoryDetails(String id) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CategoryDetailsScreen(
          controller: widget.controller,
          period: widget.period,
          categoryId: id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('desktop-overview-scroll'),
      padding: QestoSpacing.workspace(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Добрый день',
                  style: TextStyle(
                    color: context.qestoColors.text,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('overview-refresh'),
                onPressed: _refreshing ? null : _refreshLocalData,
                icon: _refreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(_refreshing ? 'Обновляется…' : 'Обновить'),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Вот, что происходит с вашими деньгами',
            style: TextStyle(
              color: context.qestoColors.secondaryText,
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
          const SizedBox(height: 20),
          _OverviewVisuals(
            data: _data,
            granularity: _granularity,
            compactFlow: _compactFlow,
            onGranularityChanged: (value) => setState(() {
              _granularity = value;
            }),
            onCompactFlowChanged: (value) => setState(() {
              _compactFlow = value;
              _data = _buildOverviewData();
            }),
            onTrendSelection: _openTrendSelection,
            onFlowSelection: _openFlowSelection,
          ),
          const SizedBox(height: 20),
          _OverviewPlanningRow(
            controller: widget.controller,
            data: _data,
            onOpenTransactions: widget.onOpenTransactions,
            onOpenBudget: widget.onOpenBudget,
            onOpenRecurring: widget.onOpenRecurring,
            onOpenMerchant: _openMerchant,
            onOpenCategory: _openCategory,
          ),
          const SizedBox(height: 20),
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

    final capital = QestoWindow(
      key: const Key('overview-capital-metric'),
      title: 'Финансовая позиция',
      actions: _MetricMenu<OverviewCapitalMetric>(
        value: capitalMetric,
        tooltip: 'Выбрать показатель капитала',
        onSelected: onCapitalMetricChanged,
        items: const {
          OverviewCapitalMetric.capital: 'Капитал',
          OverviewCapitalMetric.investments: 'Инвестиции',
          OverviewCapitalMetric.savings: 'Накопления',
        },
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(capitalLabel, style: QestoTypography.sectionTitle),
          const SizedBox(height: 12),
          QestoHeroMoney(formatMoney(capitalValue, data.currency)),
          const SizedBox(height: 12),
          Text(capitalDetail, style: QestoTypography.caption),
        ],
      ),
    );
    final primary = _MetricReadout(
      key: const Key('overview-primary-metric'),
      label: primaryLabel,
      value: formatMoney(primaryValue, data.currency),
      detail:
          '$primaryLabel за ${formatBudgetPeriod(data.period.month, data.period.year)}',
      color: primaryIsExpense
          ? context.qestoColors.negative
          : context.qestoColors.positive,
      hero: true,
      control: _MetricMenu<OverviewPrimaryMetric>(
        value: primaryMetric,
        tooltip: 'Выбрать доходы или расходы',
        onSelected: onPrimaryMetricChanged,
        items: const {
          OverviewPrimaryMetric.expenses: 'Расходы',
          OverviewPrimaryMetric.income: 'Доходы',
        },
      ),
    );
    final cashFlow = _MetricReadout(
      key: const Key('overview-cash-flow'),
      label: 'Кэшфлоу',
      value: formatMoney(data.cashFlow, data.currency, showSign: true),
      detail: 'Доходы − расходы',
      color: data.cashFlow == 0
          ? context.qestoColors.text
          : data.cashFlow > 0
          ? context.qestoColors.positive
          : context.qestoColors.negative,
    );
    final free = _MetricReadout(
      key: const Key('desktop-free-to-spend'),
      label: 'Свободные деньги',
      value: data.freeToSpend == null
          ? 'Не рассчитаны'
          : formatMoney(data.freeToSpend!, data.currency),
      detail: data.freeToSpend == null
          ? 'Назначьте бюджет'
          : 'Доступно к тратам',
      numeric: data.freeToSpend != null,
      color: data.freeToSpend == null
          ? context.qestoColors.secondaryText
          : data.freeToSpend! >= 0
          ? context.qestoColors.positive
          : context.qestoColors.negative,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        final period = QestoWindow(
          title: 'Результат периода',
          padding: const EdgeInsets.all(20),
          child: constraints.maxWidth < 480
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    primary,
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 16),
                    cashFlow,
                    const SizedBox(height: 16),
                    free,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: primary),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          cashFlow,
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                          free,
                        ],
                      ),
                    ),
                  ],
                ),
        );
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [capital, const SizedBox(height: 20), period],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: SizedBox(
                height:
                    320 *
                    math.max(
                      1,
                      MediaQuery.textScalerOf(context).scale(14) / 14,
                    ),
                child: capital,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              flex: 7,
              child: SizedBox(
                height:
                    320 *
                    math.max(
                      1,
                      MediaQuery.textScalerOf(context).scale(14) / 14,
                    ),
                child: period,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MetricReadout extends StatelessWidget {
  const _MetricReadout({
    required this.label,
    required this.value,
    required this.detail,
    this.color,
    this.hero = false,
    this.numeric = true,
    this.control,
    super.key,
  });
  final String label, value, detail;
  final Color? color;
  final bool hero, numeric;
  final Widget? control;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: hero
                  ? QestoTypography.sectionTitle
                  : QestoTypography.uiMedium,
            ),
          ),
          ?control,
        ],
      ),
      SizedBox(height: hero ? 14 : 6),
      if (numeric)
        QestoHeroMoney(
          value,
          color: color ?? context.qestoColors.text,
          large: hero,
        )
      else
        Text(
          value,
          style: QestoTypography.ui.copyWith(
            fontSize: 17,
            color: color ?? context.qestoColors.text,
          ),
        ),
      const SizedBox(height: 7),
      Text(detail, style: QestoTypography.metadata),
    ],
  );
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
                      ? Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: context.qestoColors.primary,
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
        border: Border.all(color: context.qestoColors.border),
        borderRadius: QestoGeometry.control,
      ),
      child: Icon(
        Icons.keyboard_arrow_down_rounded,
        size: 18,
        color: context.qestoColors.text,
      ),
    );
  }
}

class _OverviewVisuals extends StatelessWidget {
  const _OverviewVisuals({
    required this.data,
    required this.granularity,
    required this.compactFlow,
    required this.onGranularityChanged,
    required this.onCompactFlowChanged,
    required this.onTrendSelection,
    required this.onFlowSelection,
  });

  final DesktopOverviewData data;
  final OverviewTrendGranularity granularity;
  final bool compactFlow;
  final ValueChanged<OverviewTrendGranularity> onGranularityChanged;
  final ValueChanged<bool> onCompactFlowChanged;
  final ValueChanged<OverviewTrendSelection> onTrendSelection;
  final ValueChanged<OverviewFlowSelection> onFlowSelection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 900;
        final flowHeight = math
            .max(350.0, (data.flow?.branches.length ?? 1) * 62 + 92)
            .toDouble();
        final chart = QestoExpandableTool(
          key: const Key('overview-expense-trend'),
          title: 'Динамика расходов',
          actions: _CompactMenu<OverviewTrendGranularity>(
            value: granularity,
            onSelected: onGranularityChanged,
            items: const {
              OverviewTrendGranularity.days: 'По дням',
              OverviewTrendGranularity.weeks: 'По неделям',
            },
          ),
          builder: (context, expanded) => LayoutBuilder(
            builder: (context, constraints) {
              final chart = OverviewExpenseTrendChart(
                points: data.trend,
                currency: data.currency,
                granularity: granularity,
                onSelection: onTrendSelection,
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Расходы', style: QestoTypography.sectionTitle),
                  const SizedBox(height: 16),
                  Flexible(
                    fit: expanded && constraints.hasBoundedHeight
                        ? FlexFit.tight
                        : FlexFit.loose,
                    child: chart,
                  ),
                ],
              );
            },
          ),
        );
        final map = QestoExpandableTool(
          key: const Key('overview-expense-map'),
          title: 'Карта расходов',
          actions: TextButton(
            key: const Key('overview-flow-category-mode'),
            onPressed: () => onCompactFlowChanged(!compactFlow),
            child: Text(compactFlow ? 'Все категории' : 'Топ-4'),
          ),
          builder: (context, expanded) => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Движение денег',
                  style: QestoTypography.sectionTitle,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Доходы → направления → операции',
                  style: QestoTypography.metadata,
                ),
                const SizedBox(height: 12),
                if (data.flow case final flow?)
                  OverviewExpenseMap(data: flow, onSelection: onFlowSelection)
                else
                  SizedBox(
                    height: stacked ? 285 : flowHeight,
                    child: const _BlockEmptyState(
                      icon: Icons.account_tree_outlined,
                      message:
                          'Добавьте доходы за выбранный период, чтобы увидеть движение денег.',
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Оставшаяся часть дохода за период — не текущий остаток на счетах.',
                  style: QestoTypography.metadata,
                ),
              ],
            ),
          ),
        );
        if (stacked) {
          return Column(children: [chart, const SizedBox(height: 20), map]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: chart),
            const SizedBox(width: 16),
            Expanded(flex: 7, child: map),
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
          color: context.qestoColors.surface,
          border: Border.all(color: context.qestoColors.border),
          borderRadius: QestoGeometry.control,
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
    required this.onOpenMerchant,
    required this.onOpenCategory,
  });

  final BudgetController controller;
  final DesktopOverviewData data;
  final VoidCallback onOpenTransactions;
  final VoidCallback onOpenBudget;
  final VoidCallback onOpenRecurring;
  final ValueChanged<BudgetTransaction> onOpenMerchant;
  final ValueChanged<OverviewCategoryBudgetRow> onOpenCategory;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _TopExpensesCard(
        data: data,
        onOpenAll: onOpenTransactions,
        onOpenMerchant: onOpenMerchant,
      ),
      _CategoryBudgetsCard(
        data: data,
        onOpenAll: onOpenBudget,
        onOpenCategory: onOpenCategory,
      ),
      _PlannedExpensesCard(
        controller: controller,
        data: data,
        onOpenAll: onOpenRecurring,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 20.0;
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
              SizedBox(width: width, height: 370, child: card),
          ],
        );
      },
    );
  }
}

class _TopExpensesCard extends StatelessWidget {
  const _TopExpensesCard({
    required this.data,
    required this.onOpenAll,
    required this.onOpenMerchant,
  });

  final DesktopOverviewData data;
  final VoidCallback onOpenAll;
  final ValueChanged<BudgetTransaction> onOpenMerchant;

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
                        onTap: () => onOpenMerchant(data.topExpenses[index]),
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
    required this.onTap,
  });

  final int rank;
  final BudgetTransaction transaction;
  final int total;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = desktopTransactionTitle(transaction);
    final percent = total <= 0 ? 0.0 : transaction.amount / total;
    return InkWell(
      key: Key('overview-top-expense-${transaction.id}'),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.qestoColors.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.qestoColors.primarySoft,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  color: context.qestoColors.primary,
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
                    style: TextStyle(
                      color: context.qestoColors.secondaryText,
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
                  style: TextStyle(
                    color: context.qestoColors.secondaryText,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBudgetsCard extends StatelessWidget {
  const _CategoryBudgetsCard({
    required this.data,
    required this.onOpenAll,
    required this.onOpenCategory,
  });

  final DesktopOverviewData data;
  final VoidCallback onOpenAll;
  final ValueChanged<OverviewCategoryBudgetRow> onOpenCategory;

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
                  Tooltip(
                    message:
                        'Бюджеты не заданы — шкала сравнивает объём расходов по категориям.',
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: context.qestoColors.secondaryText,
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
                      child: _CategoryBudgetRow(
                        row: row,
                        data: data,
                        onTap: () => onOpenCategory(row),
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

class _CategoryBudgetRow extends StatelessWidget {
  const _CategoryBudgetRow({
    required this.row,
    required this.data,
    required this.onTap,
  });

  final OverviewCategoryBudgetRow row;
  final DesktopOverviewData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progressColor = row.isRelative
        ? row.color
        : row.progress > 1
        ? context.qestoColors.negative
        : row.progress >= 0.85
        ? context.qestoColors.warning
        : row.color;
    return InkWell(
      key: Key('overview-category-budget-${row.id}'),
      onTap: onTap,
      child: Row(
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
                      style: TextStyle(
                        color: context.qestoColors.secondaryText,
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
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
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
        ? context.qestoColors.purple
        : Color(category.colorValue);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.qestoColors.border)),
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
                  style: TextStyle(
                    color: context.qestoColors.secondaryText,
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
                  style: TextStyle(
                    color: context.qestoColors.secondaryText,
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
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.qestoColors.border)),
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
                color: active
                    ? context.qestoColors.primary
                    : context.qestoColors.secondaryText,
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
            color: active
                ? context.qestoColors.primary
                : context.qestoColors.secondaryText,
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
      style: TextStyle(
        color: context.qestoColors.secondaryText,
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
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.qestoColors.border)),
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
                            style: TextStyle(
                              color: context.qestoColors.secondaryText,
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
                style: TextStyle(
                  color: context.qestoColors.secondaryText,
                  fontSize: 9.5,
                ),
              ),
            ),
            Expanded(
              flex: 18,
              child: QestoMoneyCell(
                formatMoney(amount, transaction.currency, showSign: amount > 0),
                color: amount > 0
                    ? context.qestoColors.positive
                    : context.qestoColors.text,
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
                    style: TextStyle(
                      color: context.qestoColors.secondaryText,
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
        context.qestoColors.positive,
        Icons.arrow_upward_rounded,
      ),
      TransactionType.transfer => (
        'Перевод',
        context.qestoColors.primary,
        Icons.swap_horiz_rounded,
      ),
      TransactionType.savingsTransfer => (
        'Накопление',
        context.qestoColors.purple,
        Icons.savings_outlined,
      ),
      TransactionType.investment => (
        'Инвестиция',
        context.qestoColors.purple,
        Icons.trending_up_rounded,
      ),
      TransactionType.expense => (
        'Расход',
        context.qestoColors.negative,
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
        side: BorderSide(color: context.qestoColors.border),
        foregroundColor: context.qestoColors.secondaryText,
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
          foregroundColor: context.qestoColors.primary,
          textStyle: const TextStyle(
            fontFamily: QestoTypography.uiFamily,
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
                color: context.qestoColors.primarySoft,
                borderRadius: QestoGeometry.control,
              ),
              child: Icon(icon, size: 21, color: context.qestoColors.primary),
            ),
            const SizedBox(height: 11),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.qestoColors.secondaryText,
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
