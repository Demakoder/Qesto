import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/budget/services/cash_flow_calculation_service.dart';
import '../desktop_financial_helpers.dart';
import '../widgets/desktop_charts.dart';
import '../widgets/desktop_components.dart';
import '../widgets/money_flow_river.dart';

class DesktopCashFlowPage extends StatefulWidget {
  const DesktopCashFlowPage({required this.controller, super.key});
  final BudgetController controller;

  @override
  State<DesktopCashFlowPage> createState() => _DesktopCashFlowPageState();
}

class _DesktopCashFlowPageState extends State<DesktopCashFlowPage> {
  int _monthCount = 6;
  var _hideAmounts = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final periods = _selectedPeriods();
        final transactions = _transactionsFor(periods);
        final points = _points(periods);
        final summary = periods.isEmpty
            ? null
            : widget.controller.cashFlowForRange(
                from: periods.first.startDate,
                toExclusive: periods.last.endDate.add(const Duration(days: 1)),
                currency: periods.first.currency,
              );
        final totalIncome = summary?.externalInflows ?? 0;
        final totalOutflow = summary?.externalOutflows ?? 0;
        final totalExpenses = totalOutflow;
        final net = summary?.netCashFlow ?? 0;
        final savingsRate = totalIncome <= 0 ? 0.0 : net / totalIncome;
        final currency =
            periods.firstOrNull?.currency ??
            widget.controller.accounts.firstOrNull?.currency ??
            'RUB';
        final previousExpenses = _previousExpenses(periods);
        final expenseChange = previousExpenses <= 0
            ? null
            : (totalExpenses - previousExpenses) / previousExpenses;
        final river = _riverCategories(
          transactions,
          income: totalIncome,
          outflow: totalOutflow,
        );
        return SingleChildScrollView(
          key: const Key('desktop-cash-flow-page'),
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CashFlowToolbar(
                monthCount: _monthCount,
                hideAmounts: _hideAmounts,
                onMonthCountChanged: (value) =>
                    setState(() => _monthCount = value),
                onPrivacyChanged: () =>
                    setState(() => _hideAmounts = !_hideAmounts),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 940
                      ? 4
                      : constraints.maxWidth >= 500
                      ? 2
                      : 1;
                  const gap = 14.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  final cards = [
                    DesktopKpiCard(
                      label: 'Чистый поток',
                      value: _money(net, currency, showSign: true),
                      detail: net >= 0
                          ? 'Деньги остались в системе'
                          : 'Расходы потребовали резерв',
                      detailColor: net >= 0
                          ? context.qestoColors.positive
                          : context.qestoColors.negative,
                      icon: Icons.waterfall_chart_rounded,
                      accent: net >= 0
                          ? context.qestoColors.positive
                          : context.qestoColors.negative,
                    ),
                    DesktopKpiCard(
                      label: 'Доходы',
                      value: _money(totalIncome, currency),
                      detail: '${periods.length} мес. наблюдения',
                      icon: Icons.south_west_rounded,
                      accent: context.qestoColors.positive,
                    ),
                    DesktopKpiCard(
                      label: 'Расходы',
                      value: _money(totalExpenses, currency),
                      detail: expenseChange == null
                          ? 'Нет прошлого периода для сравнения'
                          : '${expenseChange <= 0 ? '↓' : '↑'} ${(expenseChange.abs() * 100).toStringAsFixed(0)}% к прошлому периоду',
                      detailColor: expenseChange == null
                          ? null
                          : expenseChange <= 0
                          ? context.qestoColors.positive
                          : context.qestoColors.negative,
                      icon: Icons.north_east_rounded,
                      accent: context.qestoColors.orange,
                    ),
                    DesktopKpiCard(
                      label: 'Норма накопления',
                      value: totalIncome <= 0
                          ? '—'
                          : '${(savingsRate * 100).toStringAsFixed(1)}%',
                      detail: totalIncome <= 0
                          ? 'Добавьте операции дохода'
                          : savingsRate >= 0.2
                          ? 'Выше ориентира 20%'
                          : savingsRate >= 0
                          ? 'Есть положительный остаток'
                          : 'Поток отрицательный',
                      detailColor: savingsRate >= 0
                          ? context.qestoColors.positive
                          : context.qestoColors.negative,
                      icon: Icons.savings_outlined,
                      accent: context.qestoColors.purple,
                    ),
                  ];
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final card in cards)
                        SizedBox(width: width, height: 142, child: card),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              DesktopCard(
                key: const Key('money-flow-river-card'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DesktopSectionHeader(
                      title: 'Река денег',
                      subtitle:
                          'Доход → категории → крупнейшие операции. Наведите курсор на любой поток.',
                      trailing: DesktopPill(
                        label: 'Тестовый режим',
                        icon: Icons.science_outlined,
                        color: context.qestoColors.purple,
                        background: Color(0xFFF1EDFF),
                      ),
                    ),
                    const SizedBox(height: 10),
                    MoneyFlowRiver(
                      income: totalIncome,
                      expenses: totalOutflow,
                      categories: river,
                      currency: currency,
                      hideAmounts: _hideAmounts,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DesktopCard(
                child: Column(
                  children: [
                    const DesktopSectionHeader(
                      title: 'Чистый денежный поток',
                      subtitle:
                          'Положительные столбцы — свободный остаток, отрицательные — дефицит месяца',
                    ),
                    const SizedBox(height: 14),
                    CashFlowBarChart(points: points, currency: currency),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 760;
                  final income = _FlowBreakdownCard(
                    title: 'Источники дохода',
                    color: context.qestoColors.positive,
                    values: _groupedIncome(transactions),
                    currency: currency,
                    hideAmounts: _hideAmounts,
                  );
                  final expenses = _FlowBreakdownCard(
                    title: 'Категории расходов',
                    color: context.qestoColors.primary,
                    values: _groupedExpenses(transactions),
                    currency: currency,
                    hideAmounts: _hideAmounts,
                  );
                  if (stacked) {
                    return Column(
                      children: [income, const SizedBox(height: 16), expenses],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: income),
                      const SizedBox(width: 16),
                      Expanded(child: expenses),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _money(int value, String currency, {bool showSign = false}) =>
      _hideAmounts ? '••••' : formatMoney(value, currency, showSign: showSign);

  List<BudgetPeriod> _selectedPeriods() => widget.controller.periods.reversed
      .take(_monthCount)
      .toList()
      .reversed
      .toList(growable: false);

  List<BudgetTransaction> _transactionsFor(List<BudgetPeriod> periods) {
    if (periods.isEmpty) return const [];
    final start = periods.first.startDate;
    final end = periods.last.endDate;
    return widget.controller.transactions
        .where((item) => !item.date.isBefore(start) && !item.date.isAfter(end))
        .toList(growable: false);
  }

  List<DesktopCashFlowPoint> _points(List<BudgetPeriod> periods) => periods
      .map((period) {
        final transactions = widget.controller.transactionsFor(period);
        return DesktopCashFlowPoint(
          label: capitalize(
            formatBudgetPeriod(period.month, period.year),
          ).substring(0, 3),
          income: _income(transactions),
          expenses: _outflow(transactions),
        );
      })
      .toList(growable: false);

  int _income(Iterable<BudgetTransaction> transactions) => transactions
      .where(
        (item) =>
            widget.controller.cashFlowTreatment(item) ==
            CashFlowTreatment.externalInflow,
      )
      .fold<int>(0, (sum, item) => sum + item.amount);

  int _outflow(Iterable<BudgetTransaction> transactions) => transactions
      .where(
        (item) =>
            widget.controller.cashFlowTreatment(item) ==
            CashFlowTreatment.externalOutflow,
      )
      .fold<int>(0, (sum, item) => sum + item.amount);

  int _previousExpenses(List<BudgetPeriod> selected) {
    if (selected.isEmpty) return 0;
    final firstIndex = widget.controller.periods.indexWhere(
      (item) => item.id == selected.first.id,
    );
    if (firstIndex <= 0) return 0;
    final start = math.max(0, firstIndex - selected.length);
    final previous = widget.controller.periods.sublist(start, firstIndex);
    return _outflow(_transactionsFor(previous));
  }

  Map<String, int> _groupedIncome(Iterable<BudgetTransaction> transactions) {
    final result = <String, int>{};
    for (final transaction in transactions.where(
      (item) =>
          widget.controller.cashFlowTreatment(item) ==
          CashFlowTreatment.externalInflow,
    )) {
      final title = desktopTransactionTitle(transaction);
      result.update(
        title,
        (value) => value + transaction.amount,
        ifAbsent: () => transaction.amount,
      );
    }
    return result;
  }

  Map<String, int> _groupedExpenses(Iterable<BudgetTransaction> transactions) {
    final result = <String, int>{};
    for (final transaction in transactions.where(
      (item) =>
          widget.controller.cashFlowTreatment(item) ==
          CashFlowTreatment.externalOutflow,
    )) {
      final title = desktopCategoryName(widget.controller, transaction);
      result.update(
        title,
        (value) => value + transaction.amount,
        ifAbsent: () => transaction.amount,
      );
    }
    return result;
  }

  List<MoneyFlowCategory> _riverCategories(
    List<BudgetTransaction> transactions, {
    required int income,
    required int outflow,
  }) {
    final groups = <String, List<BudgetTransaction>>{};
    for (final transaction in transactions.where(
      (item) =>
          widget.controller.cashFlowTreatment(item) ==
          CashFlowTreatment.externalOutflow,
    )) {
      final id = switch (transaction.type) {
        TransactionType.savingsTransfer => '__savings',
        TransactionType.investment => '__investment',
        _ => transaction.categoryId ?? 'other',
      };
      groups.putIfAbsent(id, () => []).add(transaction);
    }
    final sorted = groups.entries.toList()
      ..sort((a, b) => _sum(b.value).compareTo(_sum(a.value)));
    final visible = sorted.take(5).toList();
    if (sorted.length > 5) {
      visible.add(
        MapEntry(
          '__other_categories',
          sorted.skip(5).expand((item) => item.value).toList(),
        ),
      );
    }

    final result = <MoneyFlowCategory>[];
    for (final entry in visible) {
      final amount = _sum(entry.value);
      final category = widget.controller.categories
          .where((item) => item.id == entry.key)
          .firstOrNull;
      final (label, color, icon) = switch (entry.key) {
        '__savings' => ('Накопления', context.qestoColors.purple, 'savings'),
        '__investment' => ('Инвестиции', const Color(0xFF2EC4B6), 'investment'),
        '__other_categories' => (
          'Остальные категории',
          context.qestoColors.secondaryText,
          'other',
        ),
        _ => (
          category?.name ?? 'Другое',
          Color(category?.colorValue ?? 0xFF8A8F9C),
          category?.iconKey ?? 'other',
        ),
      };
      result.add(
        MoneyFlowCategory(
          id: entry.key,
          label: label,
          amount: amount,
          color: color,
          iconKey: icon,
          purchases: _topPurchases(entry.value, amount),
        ),
      );
    }

    final remainder = income - outflow;
    if (remainder > 0) {
      result.add(
        MoneyFlowCategory(
          id: '__remainder',
          label: 'Свободный остаток',
          amount: remainder,
          color: context.qestoColors.positive,
          iconKey: 'savings',
          isRemainder: true,
          purchases: [
            MoneyFlowPurchase(label: 'Осталось в резерве', amount: remainder),
          ],
        ),
      );
    }
    return result;
  }

  List<MoneyFlowPurchase> _topPurchases(
    List<BudgetTransaction> transactions,
    int total,
  ) {
    final grouped = <String, int>{};
    for (final transaction in transactions) {
      final title = desktopTransactionTitle(transaction);
      grouped.update(
        title,
        (value) => value + transaction.amount,
        ifAbsent: () => transaction.amount,
      );
    }
    final sorted = grouped.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final visible = [
      for (final entry in sorted.take(2))
        MoneyFlowPurchase(label: entry.key, amount: entry.value),
    ];
    final shown = visible.fold<int>(0, (sum, item) => sum + item.amount);
    if (shown < total) {
      visible.add(
        MoneyFlowPurchase(label: 'Остальные операции', amount: total - shown),
      );
    }
    return visible.isEmpty
        ? [MoneyFlowPurchase(label: 'Операции', amount: total)]
        : visible;
  }

  int _sum(Iterable<BudgetTransaction> items) =>
      items.fold<int>(0, (sum, item) => sum + item.amount);
}

class _CashFlowToolbar extends StatelessWidget {
  const _CashFlowToolbar({
    required this.monthCount,
    required this.hideAmounts,
    required this.onMonthCountChanged,
    required this.onPrivacyChanged,
  });

  final int monthCount;
  final bool hideAmounts;
  final ValueChanged<int> onMonthCountChanged;
  final VoidCallback onPrivacyChanged;

  @override
  Widget build(BuildContext context) => DesktopAdaptiveRow(
    children: [
      SegmentedButton<int>(
        key: const Key('cash-flow-period-selector'),
        segments: const [
          ButtonSegment(value: 1, label: Text('1M')),
          ButtonSegment(value: 3, label: Text('3M')),
          ButtonSegment(value: 6, label: Text('6M')),
          ButtonSegment(value: 12, label: Text('1Y')),
        ],
        selected: {monthCount},
        onSelectionChanged: (value) => onMonthCountChanged(value.first),
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
      ),
      const Spacer(),
      DesktopPill(
        label: 'Сравнение: предыдущий период',
        icon: Icons.compare_arrows_rounded,
        color: context.qestoColors.secondaryText,
        background: context.qestoColors.surfaceSecondary,
      ),
      const SizedBox(width: 8),
      IconButton.outlined(
        key: const Key('cash-flow-privacy'),
        tooltip: hideAmounts ? 'Показать суммы' : 'Скрыть суммы',
        onPressed: onPrivacyChanged,
        icon: Icon(
          hideAmounts
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 19,
        ),
        style: IconButton.styleFrom(
          foregroundColor: context.qestoColors.secondaryText,
          side: BorderSide(color: context.qestoColors.border),
        ),
      ),
    ],
  );
}

class _FlowBreakdownCard extends StatelessWidget {
  const _FlowBreakdownCard({
    required this.title,
    required this.color,
    required this.values,
    required this.currency,
    required this.hideAmounts,
  });
  final String title;
  final Color color;
  final Map<String, int> values;
  final String currency;
  final bool hideAmounts;

  @override
  Widget build(BuildContext context) {
    final sorted = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxValue = sorted.isEmpty ? 1 : sorted.first.value;
    return DesktopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesktopSectionHeader(
            title: title,
            subtitle: 'Крупнейшие составляющие выбранного периода',
          ),
          const SizedBox(height: 16),
          if (sorted.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'Нет данных',
                  style: TextStyle(color: context.qestoColors.secondaryText),
                ),
              ),
            ),
          for (final entry in sorted.take(5)) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  hideAmounts ? '••••' : formatMoney(entry.value, currency),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            DesktopProgressBar(
              value: entry.value / maxValue,
              color: color,
              height: 5,
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
