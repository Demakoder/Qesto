import 'package:flutter/material.dart';
import '../../data/models/qesto_models.dart';
import '../../core/formatters/qesto_formatters.dart';
import '../../features/statistics/domain/models/statistics_models.dart';
import '../../features/statistics/presentation/state/statistics_controller.dart';
import '../../features/statistics/presentation/widgets/statistics_components.dart';

const mobilePeriodLabels = {
  StatisticsPeriodPreset.currentWeek: 'Текущая неделя',
  StatisticsPeriodPreset.currentBudget: 'Текущий бюджет',
  StatisticsPeriodPreset.last30Days: 'Последние 30 дней',
  StatisticsPeriodPreset.threeMonths: '3 месяца',
  StatisticsPeriodPreset.sixMonths: '6 месяцев',
  StatisticsPeriodPreset.currentYear: 'Текущий год',
  StatisticsPeriodPreset.last12Months: 'Последние 12 месяцев',
  StatisticsPeriodPreset.allTime: 'Всё время',
  StatisticsPeriodPreset.custom: 'Выбрать даты',
};
const mobileComparisonLabels = {
  StatisticsComparison.none: 'Без сравнения',
  StatisticsComparison.previousSameLength: 'Предыдущий период такой же длины',
  StatisticsComparison.previousYear: 'Период прошлого года',
  StatisticsComparison.average3: 'Среднее за 3 периода',
  StatisticsComparison.average6: 'Среднее за 6 периодов',
  StatisticsComparison.average12: 'Среднее за 12 периодов',
};

String mobileBudgetPeriodLabel(BudgetPeriod p) =>
    p.type == BudgetPeriodType.calendarMonth
    ? formatBudgetPeriod(p.startDate.month, p.startDate.year, includeYear: true)
    : '${formatDate(p.startDate)} — ${formatDate(p.endDate)}';

Future<T?> mobileChoice<T>(
  BuildContext context,
  String title,
  Map<T, String> labels,
  T selected,
) => showModalBottomSheet<T>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .68,
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        for (final e in labels.entries)
          ListTile(
            key: Key('mobile-choice-${e.key}'),
            title: Text(e.value),
            trailing: selected == e.key ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, e.key),
          ),
      ],
    ),
  ),
);

Future<void> chooseMobileStatisticsPeriod(
  BuildContext context,
  StatisticsController statistics,
) async {
  final preset = await mobileChoice(
    context,
    'Период',
    mobilePeriodLabels,
    statistics.query.preset,
  );
  if (preset == null || !context.mounted) return;
  if (preset != StatisticsPeriodPreset.custom) {
    statistics.setPeriodPreset(preset);
  } else {
    final q = statistics.query.period;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: q.start, end: q.end),
    );
    if (range != null && context.mounted) {
      statistics.setCustomPeriod(range.start, range.end);
    }
  }
}

void applyMobileFilters(StatisticsController controller, StatisticsQuery q) =>
    controller.applyFilters(
      accountIds: q.accountIds,
      categoryIds: q.categoryIds,
      subcategoryIds: q.subcategoryIds,
      merchantNames: q.merchantNames,
      tagIds: q.tagIds,
      transactionTypes: q.transactionTypes,
      includeCash: q.includeCash,
      includeLargePurchases: q.includeLargePurchases,
      includeRecurring: q.includeRecurring,
      includeRefunds: q.includeRefunds,
      includeUncategorized: q.includeUncategorized,
      onlyConfirmed: q.onlyConfirmed,
    );

class MobileActiveFilters extends StatelessWidget {
  const MobileActiveFilters({required this.controller, super.key});
  final StatisticsController controller;
  @override
  Widget build(BuildContext context) {
    final q = controller.query;
    if (q.activeFilterCount == 0) return const SizedBox.shrink();
    final chips = <Widget>[];
    void add(String id, String label, StatisticsQuery next) => chips.add(
      InputChip(
        key: Key('mobile-filter-$id'),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 175),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        onDeleted: () => applyMobileFilters(controller, next),
      ),
    );
    for (final id in q.accountIds) {
      final account = controller.budgetController.accounts
          .where((a) => a.id == id)
          .firstOrNull;
      add(
        'account-$id',
        account?.title ?? id,
        q.copyWith(accountIds: {...q.accountIds}..remove(id)),
      );
    }
    for (final id in q.categoryIds) {
      final category = controller.budgetController.categories
          .where((a) => a.id == id)
          .firstOrNull;
      add(
        'category-$id',
        category?.name ?? id,
        q.copyWith(categoryIds: {...q.categoryIds}..remove(id)),
      );
    }
    for (final id in q.subcategoryIds) {
      add(
        'subcategory-$id',
        id,
        q.copyWith(subcategoryIds: {...q.subcategoryIds}..remove(id)),
      );
    }
    for (final id in q.merchantNames) {
      add(
        'merchant-$id',
        id,
        q.copyWith(merchantNames: {...q.merchantNames}..remove(id)),
      );
    }
    for (final id in q.tagIds) {
      add('tag-$id', id, q.copyWith(tagIds: {...q.tagIds}..remove(id)));
    }
    for (final type in q.transactionTypes) {
      add(
        'type-${type.name}',
        switch (type) {
          TransactionType.expense => 'Расходы',
          TransactionType.income => 'Доходы',
          TransactionType.refund => 'Возвраты',
          TransactionType.transfer => 'Переводы',
          TransactionType.savingsTransfer => 'Накопления',
          TransactionType.investment => 'Инвестиции',
        },
        q.copyWith(transactionTypes: {...q.transactionTypes}..remove(type)),
      );
    }
    if (!q.includeCash) {
      add('cash', 'Без наличных', q.copyWith(includeCash: true));
    }
    if (!q.includeLargePurchases) {
      add(
        'large',
        'Без крупных покупок',
        q.copyWith(includeLargePurchases: true),
      );
    }
    if (!q.includeRecurring) {
      add('recurring', 'Без регулярных', q.copyWith(includeRecurring: true));
    }
    if (!q.includeRefunds) {
      add('refunds', 'Без возвратов', q.copyWith(includeRefunds: true));
    }
    if (!q.includeUncategorized) {
      add(
        'uncategorized',
        'Только с категорией',
        q.copyWith(includeUncategorized: true),
      );
    }
    if (q.onlyConfirmed) {
      add('confirmed', 'Только проверенные', q.copyWith(onlyConfirmed: false));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Показана отфильтрованная выборка',
          style: TextStyle(fontSize: 12),
        ),
        Wrap(spacing: 6, runSpacing: 4, children: chips),
        TextButton(
          key: const Key('mobile-reset-filters'),
          onPressed: controller.resetFilters,
          child: const Text('Сбросить все фильтры'),
        ),
      ],
    );
  }
}

class MobilePeriodControl extends StatelessWidget {
  const MobilePeriodControl({
    required this.controller,
    required this.onFilter,
    super.key,
  });
  final StatisticsController controller;
  final VoidCallback onFilter;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextButton.icon(
          key: const Key('mobile-analysis-period'),
          onPressed: () => chooseMobileStatisticsPeriod(context, controller),
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          label: Text(
            statisticsRangeLabel(controller.query.period),
            maxLines: 2,
          ),
        ),
      ),
      Badge(
        isLabelVisible: controller.query.activeFilterCount > 0,
        label: Text('${controller.query.activeFilterCount}'),
        child: IconButton(
          key: const Key('mobile-analysis-filters'),
          tooltip: 'Фильтры',
          onPressed: onFilter,
          icon: const Icon(Icons.tune),
        ),
      ),
    ],
  );
}
