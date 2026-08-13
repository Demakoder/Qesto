import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/statistics/domain/models/statistics_models.dart';
import '../../features/statistics/presentation/sections/overview_expenses_sections.dart';
import '../../features/statistics/presentation/sections/secondary_statistics_sections.dart';
import '../../features/statistics/presentation/state/statistics_controller.dart';
import '../../features/statistics/presentation/widgets/statistics_components.dart';
import '../widgets/desktop_components.dart';

class DesktopStatisticsPage extends StatefulWidget {
  const DesktopStatisticsPage({required this.controller, super.key});

  final BudgetController controller;

  @override
  State<DesktopStatisticsPage> createState() => _DesktopStatisticsPageState();
}

class _DesktopStatisticsPageState extends State<DesktopStatisticsPage> {
  late final StatisticsController _statistics;
  late final Map<StatisticsSection, ScrollController> _scrollControllers;

  @override
  void initState() {
    super.initState();
    _statistics = StatisticsController(budgetController: widget.controller);
    _scrollControllers = {
      for (final section in StatisticsSection.values)
        section: ScrollController(),
    };
  }

  @override
  void dispose() {
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    _statistics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _statistics,
      builder: (context, _) {
        final hasTransactions = widget.controller.transactions.isNotEmpty;
        return Column(
          key: const Key('desktop-statistics-page'),
          children: [
            _StatisticsToolbar(
              controller: _statistics,
              onSelectPeriod: _selectPeriod,
              onOpenFilters: _openFilters,
            ),
            if (hasTransactions) ...[
              _StatisticsTabs(controller: _statistics),
              if (_statistics.snapshot.dataQuality.issues.isNotEmpty)
                _DataQualityNotice(snapshot: _statistics.snapshot),
            ],
            Expanded(
              child: hasTransactions
                  ? LayoutBuilder(
                      builder: (context, constraints) => Center(
                        child: SizedBox(
                          width: math.min(1320, constraints.maxWidth),
                          height: constraints.maxHeight,
                          child: _sectionFor(_statistics.section),
                        ),
                      ),
                    )
                  : const DesktopEmptyState(
                      key: Key('desktop-statistics-empty'),
                      title: 'Статистика появится после операций',
                      message:
                          'Загрузите выписку, чек или добавьте операцию — графики будут рассчитаны только из реальных данных.',
                      icon: Icons.query_stats_rounded,
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionFor(StatisticsSection section) {
    final scrollController = _scrollControllers[section]!;
    return switch (section) {
      StatisticsSection.overview => OverviewStatisticsSection(
        controller: _statistics,
        scrollController: scrollController,
      ),
      StatisticsSection.expenses => ExpensesStatisticsSection(
        controller: _statistics,
        scrollController: scrollController,
      ),
      StatisticsSection.rhythm => RhythmStatisticsSection(
        controller: _statistics,
        scrollController: scrollController,
      ),
      StatisticsSection.merchants => MerchantsStatisticsSection(
        controller: _statistics,
        scrollController: scrollController,
      ),
      StatisticsSection.categories => CategoriesStatisticsSection(
        controller: _statistics,
        scrollController: scrollController,
      ),
      StatisticsSection.cashFlow => CashFlowStatisticsSection(
        controller: _statistics,
        scrollController: scrollController,
      ),
      StatisticsSection.budget => BudgetQualityStatisticsSection(
        controller: _statistics,
        scrollController: scrollController,
      ),
      StatisticsSection.recurring => RecurringStatisticsSection(
        controller: _statistics,
        scrollController: scrollController,
      ),
    };
  }

  Future<void> _selectPeriod(StatisticsPeriodPreset preset) async {
    if (preset != StatisticsPeriodPreset.custom) {
      _statistics.setPeriodPreset(preset);
      return;
    }
    final current = _statistics.query.period;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: current.start, end: current.end),
      helpText: 'Период статистики',
      cancelText: 'Отмена',
      confirmText: 'Применить',
    );
    if (selected != null) {
      _statistics.setCustomPeriod(selected.start, selected.end);
    }
  }

  Future<void> _openFilters() async {
    final selection = await showDialog<_StatisticsFilterSelection>(
      context: context,
      builder: (context) =>
          _DesktopStatisticsFilterDialog(controller: _statistics),
    );
    if (selection == null) return;
    _statistics.applyFilters(
      accountIds: selection.accountIds,
      categoryIds: selection.categoryIds,
      subcategoryIds: _statistics.query.subcategoryIds,
      merchantNames: _statistics.query.merchantNames,
      tagIds: _statistics.query.tagIds,
      transactionTypes: selection.transactionTypes,
      includeCash: selection.includeCash,
      includeLargePurchases: selection.includeLargePurchases,
      includeRecurring: selection.includeRecurring,
      includeRefunds: selection.includeRefunds,
      includeUncategorized: selection.includeUncategorized,
      onlyConfirmed: selection.onlyConfirmed,
    );
  }
}

class _StatisticsToolbar extends StatelessWidget {
  const _StatisticsToolbar({
    required this.controller,
    required this.onSelectPeriod,
    required this.onOpenFilters,
  });

  final StatisticsController controller;
  final ValueChanged<StatisticsPeriodPreset> onSelectPeriod;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Финансовая аналитика',
          style: TextStyle(
            color: QestoColors.text,
            fontSize: 21,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.35,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          statisticsRangeLabel(controller.query.period),
          style: const TextStyle(
            color: QestoColors.secondaryText,
            fontSize: 11,
          ),
        ),
      ],
    );
    final controls = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatisticsPopupButton<StatisticsPeriodPreset>(
          key: const Key('desktop-statistics-period'),
          label: _periodLabel(controller.query.preset),
          icon: Icons.calendar_month_outlined,
          values: StatisticsPeriodPreset.values,
          itemLabel: _periodLabel,
          onSelected: onSelectPeriod,
        ),
        _StatisticsPopupButton<StatisticsComparison>(
          key: const Key('desktop-statistics-comparison'),
          label: _comparisonLabel(controller.query.comparison),
          icon: Icons.compare_arrows_rounded,
          values: StatisticsComparison.values,
          itemLabel: _comparisonLabel,
          onSelected: controller.setComparison,
        ),
        OutlinedButton.icon(
          key: const Key('desktop-statistics-filters'),
          onPressed: onOpenFilters,
          icon: const Icon(Icons.tune_rounded, size: 17),
          label: Text(
            controller.query.activeFilterCount == 0
                ? 'Фильтры'
                : 'Фильтры · ${controller.query.activeFilterCount}',
          ),
          style: _toolbarButtonStyle(),
        ),
        if (controller.query.activeFilterCount > 0)
          TextButton(
            key: const Key('desktop-statistics-reset-filters'),
            onPressed: controller.resetFilters,
            child: const Text('Сбросить'),
          ),
        DesktopPill(
          label: 'Качество ${controller.snapshot.dataQuality.score}%',
          icon: Icons.verified_user_outlined,
          color: controller.snapshot.dataQuality.score >= 80
              ? QestoColors.positive
              : QestoColors.warning,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(26, 18, 26, 12),
          decoration: const BoxDecoration(
            color: QestoColors.background,
            border: Border(bottom: BorderSide(color: QestoColors.border)),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 12), controls],
                )
              : Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 20),
                    controls,
                  ],
                ),
        );
      },
    );
  }
}

class _StatisticsPopupButton<T> extends StatelessWidget {
  const _StatisticsPopupButton({
    required this.label,
    required this.icon,
    required this.values,
    required this.itemLabel,
    required this.onSelected,
    super.key,
  });

  final String label;
  final IconData icon;
  final List<T> values;
  final String Function(T value) itemLabel;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    onSelected: onSelected,
    itemBuilder: (context) => [
      for (final value in values)
        PopupMenuItem<T>(value: value, child: Text(itemLabel(value))),
    ],
    child: IgnorePointer(
      child: OutlinedButton.icon(
        onPressed: () {},
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: _toolbarButtonStyle(),
      ),
    ),
  );
}

ButtonStyle _toolbarButtonStyle() => OutlinedButton.styleFrom(
  foregroundColor: QestoColors.text,
  side: const BorderSide(color: QestoColors.border),
  backgroundColor: QestoColors.surface,
  visualDensity: VisualDensity.compact,
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
);

class _StatisticsTabs extends StatelessWidget {
  const _StatisticsTabs({required this.controller});

  final StatisticsController controller;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: QestoColors.background,
    padding: const EdgeInsets.fromLTRB(26, 11, 26, 9),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final section in StatisticsSection.values) ...[
            ChoiceChip(
              key: Key('desktop-statistics-tab-${section.name}'),
              label: Text(section.label),
              selected: controller.section == section,
              onSelected: (_) => controller.selectSection(section),
              showCheckmark: false,
              side: BorderSide(
                color: controller.section == section
                    ? QestoColors.primary
                    : QestoColors.border,
              ),
              selectedColor: QestoColors.primarySoft,
              backgroundColor: QestoColors.surface,
              labelStyle: TextStyle(
                color: controller.section == section
                    ? QestoColors.primary
                    : QestoColors.secondaryText,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 7),
          ],
        ],
      ),
    ),
  );
}

class _DataQualityNotice extends StatelessWidget {
  const _DataQualityNotice({required this.snapshot});

  final StatisticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('desktop-statistics-quality-notice'),
    margin: const EdgeInsets.fromLTRB(26, 3, 26, 0),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7E8),
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: const Color(0xFFFFE0A8)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 17,
          color: QestoColors.warning,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'Качество данных ${snapshot.dataQuality.score}% · требуют внимания: ${snapshot.dataQuality.issues.length}',
            style: const TextStyle(
              color: QestoColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DesktopStatisticsFilterDialog extends StatefulWidget {
  const _DesktopStatisticsFilterDialog({required this.controller});

  final StatisticsController controller;

  @override
  State<_DesktopStatisticsFilterDialog> createState() =>
      _DesktopStatisticsFilterDialogState();
}

class _DesktopStatisticsFilterDialogState
    extends State<_DesktopStatisticsFilterDialog> {
  late Set<String> accountIds;
  late Set<String> categoryIds;
  late Set<TransactionType> transactionTypes;
  late bool includeCash;
  late bool includeLargePurchases;
  late bool includeRecurring;
  late bool includeRefunds;
  late bool includeUncategorized;
  late bool onlyConfirmed;

  @override
  void initState() {
    super.initState();
    final query = widget.controller.query;
    accountIds = {...query.accountIds};
    categoryIds = {...query.categoryIds};
    transactionTypes = {...query.transactionTypes};
    includeCash = query.includeCash;
    includeLargePurchases = query.includeLargePurchases;
    includeRecurring = query.includeRecurring;
    includeRefunds = query.includeRefunds;
    includeUncategorized = query.includeUncategorized;
    onlyConfirmed = query.onlyConfirmed;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('desktop-statistics-filter-dialog'),
    title: const Text('Фильтры статистики'),
    content: SizedBox(
      width: 700,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FilterHeading(label: 'Счета', count: accountIds.length),
            Wrap(
              spacing: 8,
              runSpacing: 7,
              children: [
                for (final account
                    in widget.controller.budgetController.accounts)
                  FilterChip(
                    label: Text(account.title),
                    selected: accountIds.contains(account.id),
                    onSelected: (selected) => setState(
                      () => selected
                          ? accountIds.add(account.id)
                          : accountIds.remove(account.id),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _FilterHeading(label: 'Категории', count: categoryIds.length),
            Wrap(
              spacing: 8,
              runSpacing: 7,
              children: [
                for (final category
                    in widget.controller.budgetController.categories)
                  FilterChip(
                    label: Text(category.shortName ?? category.name),
                    selected: categoryIds.contains(category.id),
                    onSelected: (selected) => setState(
                      () => selected
                          ? categoryIds.add(category.id)
                          : categoryIds.remove(category.id),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            _FilterHeading(
              label: 'Типы операций',
              count: transactionTypes.length,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 7,
              children: [
                for (final type in TransactionType.values)
                  FilterChip(
                    label: Text(_transactionTypeLabel(type)),
                    selected: transactionTypes.contains(type),
                    onSelected: (selected) => setState(
                      () => selected
                          ? transactionTypes.add(type)
                          : transactionTypes.remove(type),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 17),
            _FilterSwitch(
              label: 'Наличные операции',
              value: includeCash,
              onChanged: (value) => setState(() => includeCash = value),
            ),
            _FilterSwitch(
              label: 'Крупные покупки',
              value: includeLargePurchases,
              onChanged: (value) =>
                  setState(() => includeLargePurchases = value),
            ),
            _FilterSwitch(
              label: 'Регулярные расходы',
              value: includeRecurring,
              onChanged: (value) => setState(() => includeRecurring = value),
            ),
            _FilterSwitch(
              label: 'Возвраты',
              value: includeRefunds,
              onChanged: (value) => setState(() => includeRefunds = value),
            ),
            _FilterSwitch(
              label: 'Без категории',
              value: includeUncategorized,
              onChanged: (value) =>
                  setState(() => includeUncategorized = value),
            ),
            _FilterSwitch(
              label: 'Только подтверждённые',
              value: onlyConfirmed,
              onChanged: (value) => setState(() => onlyConfirmed = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Отмена'),
      ),
      FilledButton(
        key: const Key('desktop-statistics-apply-filters'),
        onPressed: () => Navigator.of(context).pop(
          _StatisticsFilterSelection(
            accountIds: accountIds,
            categoryIds: categoryIds,
            transactionTypes: transactionTypes,
            includeCash: includeCash,
            includeLargePurchases: includeLargePurchases,
            includeRecurring: includeRecurring,
            includeRefunds: includeRefunds,
            includeUncategorized: includeUncategorized,
            onlyConfirmed: onlyConfirmed,
          ),
        ),
        child: const Text('Применить'),
      ),
    ],
  );
}

class _FilterHeading extends StatelessWidget {
  const _FilterHeading({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Text(
      count == 0 ? label : '$label · $count',
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
    ),
  );
}

class _FilterSwitch extends StatelessWidget {
  const _FilterSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: value,
    onChanged: onChanged,
  );
}

class _StatisticsFilterSelection {
  const _StatisticsFilterSelection({
    required this.accountIds,
    required this.categoryIds,
    required this.transactionTypes,
    required this.includeCash,
    required this.includeLargePurchases,
    required this.includeRecurring,
    required this.includeRefunds,
    required this.includeUncategorized,
    required this.onlyConfirmed,
  });

  final Set<String> accountIds;
  final Set<String> categoryIds;
  final Set<TransactionType> transactionTypes;
  final bool includeCash;
  final bool includeLargePurchases;
  final bool includeRecurring;
  final bool includeRefunds;
  final bool includeUncategorized;
  final bool onlyConfirmed;
}

String _periodLabel(StatisticsPeriodPreset preset) => switch (preset) {
  StatisticsPeriodPreset.currentWeek => 'Текущая неделя',
  StatisticsPeriodPreset.currentBudget => 'Текущий бюджет',
  StatisticsPeriodPreset.last30Days => 'Последние 30 дней',
  StatisticsPeriodPreset.threeMonths => '3 месяца',
  StatisticsPeriodPreset.sixMonths => '6 месяцев',
  StatisticsPeriodPreset.currentYear => 'Текущий год',
  StatisticsPeriodPreset.last12Months => '12 месяцев',
  StatisticsPeriodPreset.allTime => 'Всё время',
  StatisticsPeriodPreset.custom => 'Свой период',
};

String _comparisonLabel(StatisticsComparison comparison) =>
    switch (comparison) {
      StatisticsComparison.none => 'Без сравнения',
      StatisticsComparison.previousSameLength => 'С прошлым периодом',
      StatisticsComparison.previousYear => 'С прошлым годом',
      StatisticsComparison.average3 => 'Со средним за 3',
      StatisticsComparison.average6 => 'Со средним за 6',
      StatisticsComparison.average12 => 'Со средним за 12',
    };

String _transactionTypeLabel(TransactionType type) => switch (type) {
  TransactionType.expense => 'Расход',
  TransactionType.income => 'Доход',
  TransactionType.transfer => 'Перевод',
  TransactionType.refund => 'Возврат',
  TransactionType.savingsTransfer => 'Накопления',
  TransactionType.investment => 'Инвестиции',
};
