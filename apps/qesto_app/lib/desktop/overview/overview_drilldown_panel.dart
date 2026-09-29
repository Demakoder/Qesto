import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../desktop_financial_helpers.dart';
import 'desktop_overview_data.dart';
import 'overview_expense_map.dart';
import 'overview_expense_trend_chart.dart';

enum OverviewDrilldownSort {
  dateDescending('Сначала новые'),
  dateAscending('Сначала старые'),
  amountDescending('Сначала дорогие'),
  amountAscending('Сначала дешёвые'),
  merchant('По продавцу');

  const OverviewDrilldownSort(this.label);
  final String label;
}

/// Reuses the identity already prepared by the import/enrichment pipeline.
/// Fallback only folds case and whitespace; it does not guess merchant aliases.
String overviewMerchantKey(BudgetTransaction transaction) {
  final name = transaction.normalizedMerchant?.trim().isNotEmpty == true
      ? transaction.normalizedMerchant!
      : desktopTransactionTitle(transaction);
  return name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

String overviewMerchantLabel(BudgetTransaction transaction) {
  final display = desktopTransactionTitle(transaction).trim();
  final normalized = transaction.normalizedMerchant?.trim().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  if (normalized != null &&
      normalized.isNotEmpty &&
      normalized.toLowerCase() != display.toLowerCase()) {
    return normalized;
  }
  return display;
}

List<BudgetTransaction> sortOverviewDrilldownTransactions(
  Iterable<BudgetTransaction> transactions,
  OverviewDrilldownSort sort,
) {
  final result = transactions.toList(growable: false);
  result.sort((left, right) {
    final order = switch (sort) {
      OverviewDrilldownSort.dateDescending => right.date.compareTo(left.date),
      OverviewDrilldownSort.dateAscending => left.date.compareTo(right.date),
      OverviewDrilldownSort.amountDescending => right.amount.compareTo(
        left.amount,
      ),
      OverviewDrilldownSort.amountAscending => left.amount.compareTo(
        right.amount,
      ),
      OverviewDrilldownSort.merchant => overviewMerchantKey(
        left,
      ).compareTo(overviewMerchantKey(right)),
    };
    return order != 0 ? order : left.id.compareTo(right.id);
  });
  return result;
}

class OverviewMerchantSlice {
  const OverviewMerchantSlice({
    required this.key,
    required this.label,
    required this.amount,
    required this.count,
    required this.transactionIds,
  });
  final String key;
  final String label;
  final int amount;
  final int count;
  final List<String> transactionIds;
}

class OverviewMerchantSummary {
  const OverviewMerchantSummary({required this.total, required this.groups});
  final int total;
  final List<OverviewMerchantSlice> groups;
  int get uniqueCount => groups.length;
  OverviewMerchantSlice? get top => groups.firstOrNull;

  List<OverviewMerchantSlice> get visualGroups {
    if (groups.length <= 5) return groups;
    final remaining = groups.skip(5).toList(growable: false);
    return [
      ...groups.take(5),
      OverviewMerchantSlice(
        key: 'other-merchants',
        label: 'Прочие продавцы',
        amount: remaining.fold(0, (sum, item) => sum + item.amount),
        count: remaining.fold(0, (sum, item) => sum + item.count),
        transactionIds: [for (final item in remaining) ...item.transactionIds],
      ),
    ];
  }

  factory OverviewMerchantSummary.fromTransactions(
    BudgetController controller,
    Iterable<BudgetTransaction> transactions,
  ) {
    final amounts = <String, int>{};
    final ids = <String, List<String>>{};
    final labels = <String, String>{};
    for (final transaction in transactions) {
      if (!controller.calculationService.isConsumerTransaction(transaction)) {
        continue;
      }
      final amount = controller.calculationService.signedExpense(transaction);
      if (amount <= 0) continue;
      final key = overviewMerchantKey(transaction);
      amounts.update(
        key,
        (current) => current + amount,
        ifAbsent: () => amount,
      );
      ids.putIfAbsent(key, () => []).add(transaction.id);
      labels.putIfAbsent(key, () => overviewMerchantLabel(transaction));
    }
    final groups =
        [
          for (final entry in amounts.entries)
            OverviewMerchantSlice(
              key: entry.key,
              label: labels[entry.key] ?? 'Неизвестный продавец',
              amount: entry.value,
              count: ids[entry.key]!.length,
              transactionIds: List.unmodifiable(ids[entry.key]!),
            ),
        ]..sort((left, right) {
          final byAmount = right.amount.compareTo(left.amount);
          return byAmount != 0 ? byAmount : left.label.compareTo(right.label);
        });
    return OverviewMerchantSummary(
      total: groups.fold(0, (sum, item) => sum + item.amount),
      groups: List.unmodifiable(groups),
    );
  }
}

/// A read-only selection of existing operations. The chart never owns a
/// separate financial ledger or derives operations from rendered labels.
class OverviewDrilldownData {
  const OverviewDrilldownData({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.amountLabel,
    required this.currency,
    required this.transactions,
    required this.periodExpenseTotal,
    required this.expenseAnalysis,
    this.showMerchantAnalysis = false,
    this.showDateAnalysis = false,
    this.budgetAmount,
    this.explanation,
  });

  final String title;
  final String subtitle;
  final int amount;
  final String amountLabel;
  final String currency;
  final List<BudgetTransaction> transactions;
  final int periodExpenseTotal;
  final bool expenseAnalysis;
  final bool showMerchantAnalysis;
  final bool showDateAnalysis;
  final int? budgetAmount;
  final String? explanation;

  static OverviewDrilldownData forTrend({
    required BudgetController controller,
    required BudgetPeriod period,
    required OverviewTrendSelection selection,
  }) {
    final from = selection.from.isBefore(period.startDate)
        ? period.startDate
        : selection.from;
    final through = selection.through.isAfter(period.endDate)
        ? period.endDate
        : selection.through;
    final transactions =
        controller
            .transactionsFor(period)
            .where((item) {
              final day = DateTime(
                item.date.year,
                item.date.month,
                item.date.day,
              );
              return !day.isBefore(from) &&
                  !day.isAfter(through) &&
                  controller.calculationService.isConsumerTransaction(item) &&
                  controller.calculationService.signedExpense(item) != 0;
            })
            .toList(growable: false)
          ..sort((a, b) => b.date.compareTo(a.date));
    final amount = transactions.fold<int>(
      0,
      (sum, item) => sum + controller.calculationService.signedExpense(item),
    );
    final oneDay = DateUtils.isSameDay(from, through);
    return OverviewDrilldownData(
      title: oneDay
          ? formatDate(from, includeYear: true)
          : '${formatDate(from)} — ${formatDate(through, includeYear: true)}',
      subtitle: oneDay ? 'Расходы за день' : 'Расходы за выбранную неделю',
      amount: amount,
      amountLabel: 'Расходы',
      currency: period.currency,
      transactions: transactions,
      periodExpenseTotal: math.max(
        0,
        controller.summaryFor(period).currentExpense,
      ),
      expenseAnalysis: true,
      showMerchantAnalysis: true,
    );
  }

  static OverviewDrilldownData forFlow({
    required BudgetController controller,
    required BudgetPeriod period,
    required OverviewFlowSelection selection,
  }) {
    final ids = selection.transactionIds.toSet();
    final transactions =
        controller
            .transactionsFor(period)
            .where((item) => ids.contains(item.id))
            .toList(growable: false)
          ..sort((a, b) => b.date.compareTo(a.date));
    final expense =
        transactions.isNotEmpty &&
        transactions.every(
          (item) =>
              controller.calculationService.isConsumerTransaction(item) &&
              controller.calculationService.signedExpense(item) != 0,
        );
    final explanation = transactions.isNotEmpty
        ? null
        : switch (selection.id) {
            'source-reserve' =>
              'Это часть расходов, покрытая остатком на начало периода, а не отдельная операция.',
            'remaining-income' || 'remaining-on-accounts' =>
              'Это разница между доходами и расходами за период, а не текущий баланс счёта.',
            _ => 'Для этого расчётного потока нет отдельных операций.',
          };
    return OverviewDrilldownData(
      title: selection.label,
      subtitle: switch (selection.kind) {
        OverviewFlowSelectionKind.source => 'Источник денег',
        OverviewFlowSelectionKind.total => 'Движение денег за период',
        OverviewFlowSelectionKind.category => 'Направление расходов',
        OverviewFlowSelectionKind.destination => 'Операции этого потока',
      },
      amount: selection.amount,
      amountLabel: expense ? 'В потоке' : 'Сумма потока',
      currency: period.currency,
      transactions: transactions,
      periodExpenseTotal: math.max(
        0,
        controller.summaryFor(period).currentExpense,
      ),
      expenseAnalysis: expense,
      showMerchantAnalysis:
          expense && selection.kind == OverviewFlowSelectionKind.category,
      explanation: explanation,
    );
  }

  static OverviewDrilldownData forMerchant({
    required BudgetController controller,
    required BudgetPeriod period,
    required BudgetTransaction selected,
  }) {
    final key = overviewMerchantKey(selected);
    final transactions = controller
        .transactionsFor(period)
        .where(
          (item) =>
              overviewMerchantKey(item) == key &&
              controller.calculationService.isConsumerTransaction(item) &&
              controller.calculationService.signedExpense(item) != 0,
        )
        .toList(growable: false);
    final amount = transactions.fold<int>(
      0,
      (sum, item) => sum + controller.calculationService.signedExpense(item),
    );
    return OverviewDrilldownData(
      title: overviewMerchantLabel(selected),
      subtitle: 'Продавец за выбранный период',
      amount: amount,
      amountLabel: 'Потрачено у продавца',
      currency: period.currency,
      transactions: transactions,
      periodExpenseTotal: math.max(
        0,
        controller.summaryFor(period).currentExpense,
      ),
      expenseAnalysis: true,
      showDateAnalysis: true,
    );
  }

  static OverviewDrilldownData forCategory({
    required BudgetController controller,
    required BudgetPeriod period,
    required OverviewCategoryBudgetRow category,
  }) {
    final transactions = controller
        .transactionsFor(period)
        .where(
          (item) =>
              (item.categoryId ?? 'uncategorized') == category.id &&
              controller.calculationService.isConsumerTransaction(item) &&
              controller.calculationService.signedExpense(item) != 0,
        )
        .toList(growable: false);
    final plan = controller
        .categoryPlansFor(period)
        .where(
          (item) => item.category.id == category.id && item.hasAssignedBudget,
        )
        .firstOrNull;
    return OverviewDrilldownData(
      title: category.name,
      subtitle: 'Категория за выбранный период',
      amount: category.spent,
      amountLabel: 'Потрачено в категории',
      currency: period.currency,
      transactions: transactions,
      periodExpenseTotal: math.max(
        0,
        controller.summaryFor(period).currentExpense,
      ),
      expenseAnalysis: true,
      showMerchantAnalysis: true,
      budgetAmount: plan?.plannedAmount,
    );
  }
}

Future<void> showOverviewDrilldownPanel(
  BuildContext context, {
  required BudgetController controller,
  required OverviewDrilldownData data,
  required ValueChanged<String> onOpenTransaction,
  required ValueChanged<List<String>> onOpenTransactions,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Закрыть детали графика',
  barrierColor: Colors.black.withValues(alpha: .36),
  pageBuilder: (dialogContext, _, _) => Align(
    alignment: Alignment.centerRight,
    child: SizedBox(
      width: math.min(510, MediaQuery.sizeOf(dialogContext).width).toDouble(),
      height: double.infinity,
      child: Material(
        color: dialogContext.qestoColors.surface,
        child: SafeArea(
          child: _OverviewDrilldownContent(
            controller: controller,
            data: data,
            onOpenTransaction: (id) {
              Navigator.of(dialogContext).pop();
              onOpenTransaction(id);
            },
            onOpenTransactions: (ids) {
              Navigator.of(dialogContext).pop();
              onOpenTransactions(ids);
            },
          ),
        ),
      ),
    ),
  ),
);

class _OverviewDrilldownContent extends StatefulWidget {
  const _OverviewDrilldownContent({
    required this.controller,
    required this.data,
    required this.onOpenTransaction,
    required this.onOpenTransactions,
  });

  final BudgetController controller;
  final OverviewDrilldownData data;
  final ValueChanged<String> onOpenTransaction;
  final ValueChanged<List<String>> onOpenTransactions;

  @override
  State<_OverviewDrilldownContent> createState() =>
      _OverviewDrilldownContentState();
}

class _OverviewDrilldownContentState extends State<_OverviewDrilldownContent> {
  OverviewDrilldownSort _sort = OverviewDrilldownSort.dateDescending;
  bool _grouped = false;
  late OverviewMerchantSummary _merchants;
  late List<_DailySpend> _dailySpending;

  @override
  void initState() {
    super.initState();
    _merchants = OverviewMerchantSummary.fromTransactions(
      widget.controller,
      widget.data.transactions,
    );
    _dailySpending = _dailySpend(widget.controller, widget.data.transactions);
  }

  @override
  void didUpdateWidget(covariant _OverviewDrilldownContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.controller != widget.controller) {
      _merchants = OverviewMerchantSummary.fromTransactions(
        widget.controller,
        widget.data.transactions,
      );
      _dailySpending = _dailySpend(widget.controller, widget.data.transactions);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final transactions = sortOverviewDrilldownTransactions(
      data.transactions,
      _sort,
    );
    final purchases = transactions
        .where(
          (item) =>
              widget.controller.calculationService.signedExpense(item) > 0,
        )
        .toList(growable: false);
    final largestCandidates = purchases.isEmpty ? transactions : purchases;
    final largest = largestCandidates.isEmpty
        ? null
        : largestCandidates.reduce((a, b) => a.amount >= b.amount ? a : b);
    final expenseGroups = <String, int>{};
    for (final item in transactions) {
      if (!widget.controller.calculationService.isConsumerTransaction(item)) {
        continue;
      }
      final amount = widget.controller.calculationService.signedExpense(item);
      if (amount <= 0) continue;
      final category = desktopCategoryName(widget.controller, item);
      expenseGroups.update(
        category,
        (value) => value + amount,
        ifAbsent: () => amount,
      );
    }
    final topCategory = expenseGroups.entries.isEmpty
        ? null
        : (expenseGroups.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first;
    final groupedTransactions = <String, List<BudgetTransaction>>{};
    final merchantLabels = {
      for (final group in _merchants.groups) group.key: group.label,
    };
    if (_grouped) {
      for (final item in transactions) {
        groupedTransactions
            .putIfAbsent(overviewMerchantKey(item), () => [])
            .add(item);
      }
    }
    return Column(
      key: const Key('overview-drilldown-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(data.subtitle, style: QestoTypography.sectionTitle),
              ),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              Text(data.title, style: QestoTypography.sectionTitle),
              const SizedBox(height: 8),
              Text(
                formatMoney(data.amount, data.currency),
                style: QestoTypography.moneyLarge,
              ),
              Text(data.amountLabel, style: QestoTypography.metadata),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Fact(label: 'Операций', value: '${transactions.length}'),
                  if (data.expenseAnalysis && purchases.isNotEmpty)
                    _Fact(
                      label: 'Средний чек',
                      value: formatMoney(
                        _merchants.total ~/ purchases.length,
                        data.currency,
                      ),
                    ),
                  if (data.expenseAnalysis && data.periodExpenseTotal > 0)
                    _Fact(
                      label: 'Доля расходов периода',
                      value: formatPercent(
                        data.amount / data.periodExpenseTotal,
                        decimals: 1,
                      ),
                    ),
                  if (topCategory != null)
                    _Fact(label: 'Главная категория', value: topCategory.key),
                  if (data.expenseAnalysis && transactions.isNotEmpty) ...[
                    _Fact(
                      label: 'Уникальных продавцов',
                      value: '${_merchants.uniqueCount}',
                    ),
                    if (_merchants.top case final top?)
                      _Fact(label: 'Топ-продавец', value: top.label),
                  ],
                  if (data.budgetAmount case final budget?) ...[
                    _Fact(
                      label: 'Бюджет категории',
                      value: formatMoney(budget, data.currency),
                    ),
                    _Fact(
                      label: 'Использовано',
                      value: formatPercent(
                        budget <= 0 ? 0 : data.amount / budget,
                        decimals: 1,
                      ),
                    ),
                  ],
                  if (largest != null)
                    _Fact(
                      label: 'Крупнейшая операция',
                      value: desktopTransactionTitle(largest),
                    ),
                ],
              ),
              if (data.explanation != null) ...[
                const SizedBox(height: 20),
                Text(data.explanation!, style: QestoTypography.caption),
              ],
              if (data.showMerchantAnalysis && _merchants.total > 0) ...[
                const SizedBox(height: 22),
                _MerchantAnalysis(summary: _merchants, currency: data.currency),
                if (_merchants.total != data.amount) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Диаграмма показывает покупки до возвратов; итоговая сумма учитывает возвраты.',
                    style: QestoTypography.metadata,
                  ),
                ],
              ],
              if (data.showDateAnalysis && _dailySpending.isNotEmpty) ...[
                const SizedBox(height: 22),
                _MerchantDateAnalysis(
                  days: _dailySpending,
                  currency: data.currency,
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Операции',
                      style: QestoTypography.sectionTitle,
                    ),
                  ),
                  Text(
                    '${transactions.length}',
                    style: QestoTypography.metadata,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (transactions.length > 1) ...[
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButton<OverviewDrilldownSort>(
                      key: const Key('overview-drilldown-sort'),
                      value: _sort,
                      onChanged: (value) {
                        if (value != null) setState(() => _sort = value);
                      },
                      items: [
                        for (final sort in OverviewDrilldownSort.values)
                          DropdownMenuItem(
                            value: sort,
                            child: Text(sort.label),
                          ),
                      ],
                    ),
                    if (data.expenseAnalysis)
                      FilterChip(
                        key: const Key('overview-drilldown-group-merchants'),
                        label: const Text('Группировать по продавцу'),
                        selected: _grouped,
                        onSelected: (value) => setState(() => _grouped = value),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              if (transactions.isEmpty)
                const Text('Нет отдельных операций для этого узла.')
              else if (_grouped)
                for (final entry in groupedTransactions.entries) ...[
                  Padding(
                    key: Key('overview-merchant-group-${entry.key}'),
                    padding: const EdgeInsets.fromLTRB(2, 12, 2, 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            merchantLabels[entry.key] ??
                                overviewMerchantLabel(entry.value.first),
                            style: QestoTypography.uiStrong,
                          ),
                        ),
                        Text(
                          formatMoney(
                            entry.value.fold<int>(
                              0,
                              (sum, item) =>
                                  sum +
                                  widget.controller.calculationService
                                      .signedExpense(item),
                            ),
                            data.currency,
                          ),
                          style: QestoTypography.metadata,
                        ),
                      ],
                    ),
                  ),
                  for (final transaction in entry.value)
                    _transactionTile(transaction),
                ]
              else
                for (final transaction in transactions)
                  _transactionTile(transaction),
            ],
          ),
        ),
        if (transactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('overview-drilldown-open-all'),
                onPressed: () => widget.onOpenTransactions(
                  data.transactions
                      .map((item) => item.id)
                      .toList(growable: false),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Показать в операциях'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _transactionTile(BudgetTransaction transaction) => Card(
    child: ListTile(
      key: Key('overview-drilldown-transaction-${transaction.id}'),
      onTap: () => widget.onOpenTransaction(transaction.id),
      title: Text(desktopTransactionTitle(transaction)),
      subtitle: Text(
        '${formatDate(transaction.date, includeYear: true)} · '
        '${transaction.date.hour == 0 && transaction.date.minute == 0 ? '' : '${transaction.date.hour.toString().padLeft(2, '0')}:${transaction.date.minute.toString().padLeft(2, '0')} · '}'
        '${desktopCategoryName(widget.controller, transaction)} · '
        '${desktopAccountName(widget.controller, transaction)}'
        '${transaction.comment?.trim().isNotEmpty == true ? ' · ${transaction.comment!.trim()}' : ''}'
        '${desktopNeedsReview(transaction) ? ' · Требует проверки' : ''}',
      ),
      trailing: Text(
        formatMoney(
          desktopSignedAmount(transaction),
          transaction.currency,
          showSign: true,
        ),
        style: QestoTypography.uiStrong,
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 130, maxWidth: 215),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.qestoColors.surfaceSecondary,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: QestoTypography.metadata),
        const SizedBox(height: 5),
        Text(value, style: QestoTypography.uiStrong),
      ],
    ),
  );
}

class _MerchantAnalysis extends StatelessWidget {
  const _MerchantAnalysis({required this.summary, required this.currency});

  final OverviewMerchantSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.qestoColors;
    final groups = summary.visualGroups;
    final palette = [
      colors.primary,
      colors.positive,
      colors.warning,
      colors.negative,
      colors.secondaryText,
      colors.controlEdge,
    ];
    final donut = SizedBox(
      key: const Key('overview-merchant-donut'),
      width: 112,
      height: 112,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(112, 112),
            painter: _MerchantDonutPainter(
              groups: groups,
              total: summary.total,
              palette: palette,
              trackColor: colors.surfaceSecondary,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${summary.uniqueCount}', style: QestoTypography.uiStrong),
              Text('продавцов', style: QestoTypography.metadata),
            ],
          ),
        ],
      ),
    );
    final bars = Column(
      key: const Key('overview-merchant-bars'),
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          if (index > 0) const SizedBox(height: 9),
          _MerchantBar(
            group: groups[index],
            total: summary.total,
            currency: currency,
            color: palette[index % palette.length],
          ),
        ],
      ],
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Структура по продавцам', style: QestoTypography.uiStrong),
          const SizedBox(height: 15),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 330
                ? Column(children: [donut, const SizedBox(height: 16), bars])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      donut,
                      const SizedBox(width: 16),
                      Expanded(child: bars),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _MerchantBar extends StatelessWidget {
  const _MerchantBar({
    required this.group,
    required this.total,
    required this.currency,
    required this.color,
  });

  final OverviewMerchantSlice group;
  final int total;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = total <= 0 ? 0.0 : group.amount / total;
    return Column(
      key: Key('overview-merchant-bar-${group.key}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                group.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QestoTypography.metadata,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              formatPercent(fraction, decimals: 0),
              style: QestoTypography.metadata,
            ),
          ],
        ),
        const SizedBox(height: 3),
        LinearProgressIndicator(
          value: fraction.clamp(0.0, 1.0),
          minHeight: 5,
          borderRadius: BorderRadius.circular(4),
          color: color,
          backgroundColor: context.qestoColors.border,
        ),
        const SizedBox(height: 3),
        Text(
          formatMoney(group.amount, currency),
          style: QestoTypography.metadata,
        ),
      ],
    );
  }
}

class _MerchantDonutPainter extends CustomPainter {
  const _MerchantDonutPainter({
    required this.groups,
    required this.total,
    required this.palette,
    required this.trackColor,
  });

  final List<OverviewMerchantSlice> groups;
  final int total;
  final List<Color> palette;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: math.min(size.width, size.height) / 2 - 8,
    );
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13;
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (var index = 0; index < groups.length; index++) {
      final sweep = math.pi * 2 * groups[index].amount / total;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = palette[index % palette.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = 13,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _MerchantDonutPainter old) =>
      old.groups != groups ||
      old.total != total ||
      old.palette != palette ||
      old.trackColor != trackColor;
}

class _DailySpend {
  const _DailySpend(this.label, this.amount);
  final String label;
  final int amount;
}

List<_DailySpend> _dailySpend(
  BudgetController controller,
  Iterable<BudgetTransaction> transactions,
) {
  final byDate = <DateTime, int>{};
  for (final item in transactions) {
    final amount = controller.calculationService.signedExpense(item);
    if (!controller.calculationService.isConsumerTransaction(item) ||
        amount <= 0) {
      continue;
    }
    final day = DateTime(item.date.year, item.date.month, item.date.day);
    byDate.update(day, (previous) => previous + amount, ifAbsent: () => amount);
  }
  final ordered = byDate.entries.toList()
    ..sort((left, right) => right.key.compareTo(left.key));
  if (ordered.length <= 6) {
    return List.unmodifiable([
      for (final entry in ordered)
        _DailySpend(formatDate(entry.key), entry.value),
    ]);
  }
  return List.unmodifiable([
    for (final entry in ordered.take(5))
      _DailySpend(formatDate(entry.key), entry.value),
    _DailySpend(
      'Более ранние',
      ordered.skip(5).fold(0, (sum, entry) => sum + entry.value),
    ),
  ]);
}

class _MerchantDateAnalysis extends StatelessWidget {
  const _MerchantDateAnalysis({required this.days, required this.currency});

  final List<_DailySpend> days;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final maximum = days.fold<int>(
      1,
      (value, day) => math.max(value, day.amount),
    );
    final colors = context.qestoColors;
    return Container(
      key: const Key('overview-merchant-timeline'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Покупки по дням', style: QestoTypography.uiStrong),
          const SizedBox(height: 12),
          for (final day in days) ...[
            Row(
              children: [
                Expanded(
                  child: Text(day.label, style: QestoTypography.metadata),
                ),
                Text(
                  formatMoney(day.amount, currency),
                  style: QestoTypography.metadata,
                ),
              ],
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: day.amount / maximum,
              minHeight: 5,
              borderRadius: BorderRadius.circular(4),
              color: colors.primary,
              backgroundColor: colors.border,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
