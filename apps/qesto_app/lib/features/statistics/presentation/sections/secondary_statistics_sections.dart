import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/formatters/qesto_formatters.dart';
import '../../../../core/theme/qesto_theme.dart';
import '../../../../core/widgets/qesto_card.dart';
import '../../../../core/widgets/states.dart';
import '../../../../data/models/qesto_models.dart';
import '../../../budget/services/category_budget_calculation_service.dart';
import '../../domain/models/statistics_models.dart';
import '../screens/statistics_drilldown_screens.dart';
import '../state/statistics_controller.dart';
import '../widgets/statistics_charts.dart';
import '../widgets/statistics_components.dart';

class RhythmStatisticsSection extends StatelessWidget {
  const RhythmStatisticsSection({
    required this.controller,
    required this.scrollController,
    super.key,
  });
  final StatisticsController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final maxWeekday = snapshot.weekdays.fold<int>(
      1,
      (value, item) => math.max(value, item.amount),
    );
    return ListView(
      controller: scrollController,
      key: const PageStorageKey('statistics-rhythm'),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        QestoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatisticsSectionHeader(title: 'Календарь расходов'),
              const SizedBox(height: 12),
              StatisticsHeatmap(
                points: snapshot.daily,
                onDayTap: (point) {
                  final transactions = snapshot.transactions
                      .where((item) => _sameDay(item.date, point.date))
                      .toList();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StatisticsOperationsScreen(
                        controller: controller,
                        title: formatDate(point.date, includeYear: true),
                        transactions: transactions,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'Чем насыщеннее синий цвет, тем выше сумма расходов. Пустая ячейка — день без расходов.',
                style: TextStyle(
                  fontSize: 12,
                  color: QestoColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        QestoCard(
          child: Column(
            children: [
              const StatisticsSectionHeader(title: 'Дни недели'),
              const SizedBox(height: 10),
              for (final item in snapshot.weekdays)
                _HorizontalValueRow(
                  label: _weekdayName(item.weekday),
                  value: item.amount,
                  maxValue: maxWeekday,
                  caption:
                      '${item.count} оп. · чек ${formatMoney(item.averageCheck.round(), 'RUB')}',
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _WeeksCard(controller: controller),
        const SizedBox(height: 16),
        _SalaryCycleCard(controller: controller),
        const SizedBox(height: 16),
        const EmptyState(
          message:
              'Для расчёта времени суток нужно больше операций с точным временем',
          icon: Icons.schedule_rounded,
        ),
      ],
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  String _weekdayName(int day) => const [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ][day - 1];
}

class MerchantsStatisticsSection extends StatelessWidget {
  const MerchantsStatisticsSection({
    required this.controller,
    required this.scrollController,
    super.key,
  });
  final StatisticsController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final merchants = controller.snapshot.merchants;
    if (merchants.isEmpty) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(18),
        children: const [EmptyState(message: 'Нет подтверждённых продавцов')],
      );
    }
    final concentration = merchants
        .take(5)
        .fold<double>(0, (sum, item) => sum + item.share);
    return ListView(
      controller: scrollController,
      key: const PageStorageKey('statistics-merchants'),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        StatisticsGroupList(
          title: 'Топ продавцов',
          items: merchants,
          limit: merchants.length,
          onTap: (item) => _open(context, item.id),
        ),
        const SizedBox(height: 16),
        QestoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatisticsSectionHeader(title: 'Частота и средний чек'),
              const SizedBox(height: 10),
              StatisticsScatter(
                items: merchants,
                onTap: (item) => _open(context, item.id),
              ),
              const SizedBox(height: 12),
              const Text(
                'Число в круге — количество покупок. В подписи указан средний чек.',
                style: TextStyle(
                  fontSize: 12,
                  color: QestoColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        QestoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatisticsSectionHeader(title: 'Концентрация расходов'),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: concentration.clamp(0, 1),
                minHeight: 14,
                borderRadius: BorderRadius.circular(10),
                backgroundColor: QestoColors.border,
              ),
              const SizedBox(height: 12),
              Text(
                'На ${math.min(5, merchants.length)} продавцов приходится ${(concentration * 100).toStringAsFixed(0)}% всех расходов.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, String merchant) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatisticsMerchantScreen(
          controller: controller,
          merchant: merchant,
        ),
      ),
    );
  }
}

class CategoriesStatisticsSection extends StatelessWidget {
  const CategoriesStatisticsSection({
    required this.controller,
    required this.scrollController,
    super.key,
  });
  final StatisticsController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    if (snapshot.categories.isEmpty) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(18),
        children: const [
          EmptyState(
            message: 'В выбранном периоде пока нет расходов по категориям',
          ),
        ],
      );
    }
    return ListView(
      controller: scrollController,
      key: const PageStorageKey('statistics-categories'),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
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
          title: 'Все категории',
          items: snapshot.categories,
          limit: snapshot.categories.length,
          onTap: (item) => _open(context, item.id),
        ),
        const SizedBox(height: 16),
        _CategoryPlanCard(controller: controller),
        const SizedBox(height: 16),
        _CategoryStabilityCard(controller: controller),
        const SizedBox(height: 16),
        _CategoriesWithoutPlanCard(controller: controller),
      ],
    );
  }

  void _open(BuildContext context, String categoryId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatisticsCategoryScreen(
          controller: controller,
          categoryId: categoryId,
        ),
      ),
    );
  }
}

class CashFlowStatisticsSection extends StatelessWidget {
  const CashFlowStatisticsSection({
    required this.controller,
    required this.scrollController,
    super.key,
  });
  final StatisticsController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final liquid = controller.budgetController.accounts
        .where(
          (account) => {
            AccountType.bankCard,
            AccountType.cash,
            AccountType.savings,
          }.contains(account.type),
        )
        .fold<int>(0, (sum, account) => sum + account.balance);
    final ordinaryMonthly = snapshot.periods.isEmpty
        ? 0
        : snapshot.periods.fold<int>(0, (sum, item) => sum + item.expenses) /
              snapshot.periods.length;
    final upcoming = _upcoming(controller);
    return ListView(
      controller: scrollController,
      key: const PageStorageKey('statistics-cashflow'),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        StatisticsMetricStrip(
          items: [
            StatisticsMetricItem(
              label: 'Доходы',
              value: formatMoney(snapshot.summary.income, 'RUB'),
              caption: 'за выбранный период',
              icon: Icons.south_west_rounded,
              valueColor: const Color(0xFF168C4A),
            ),
            StatisticsMetricItem(
              label: 'Расходы',
              value: formatMoney(snapshot.summary.expenses, 'RUB'),
              caption: 'с учётом возвратов',
              icon: Icons.north_east_rounded,
            ),
            StatisticsMetricItem(
              label: 'Остаток',
              value: formatMoney(snapshot.summary.balance, 'RUB'),
              caption: 'после накоплений',
              icon: Icons.account_balance_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _IncomeExpensePeriodsCard(points: snapshot.periods),
        const SizedBox(height: 16),
        _CashFlowWaterfall(controller: controller),
        const SizedBox(height: 16),
        _IncomeSourcesCard(controller: controller),
        const SizedBox(height: 16),
        QestoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatisticsSectionHeader(title: 'Запас ликвидности'),
              const SizedBox(height: 10),
              Text(
                formatMoney(liquid, 'RUB'),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ordinaryMonthly <= 0
                    ? 'Недостаточно данных для оценки'
                    : 'Доступные средства покрывают ${(liquid / ordinaryMonthly).toStringAsFixed(1)} обычного месяца расходов.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        QestoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatisticsSectionHeader(title: 'Прогноз на 30 дней'),
              const SizedBox(height: 10),
              if (upcoming.isEmpty)
                const StatisticsInfoBanner(
                  message: 'Предстоящих расходов пока нет',
                )
              else ...[
                for (final item in upcoming.take(4))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.event_rounded,
                      color: QestoColors.primary,
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(formatDate(item.plannedDate)),
                    trailing: Text(
                      formatMoney(item.amount, item.currency),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                StatisticsInfoBanner(
                  message:
                      'После ближайших списаний прогнозируемый запас: ${formatMoney(liquid - upcoming.fold<int>(0, (sum, item) => sum + item.amount), 'RUB')}',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  List<UpcomingExpense> _upcoming(StatisticsController controller) =>
      controller.budgetController.upcomingExpenses
          .where(
            (item) =>
                !item.isCancelled &&
                !item.plannedDate.isBefore(
                  controller.budgetController.referenceDate,
                ),
          )
          .toList()
        ..sort((a, b) => a.plannedDate.compareTo(b.plannedDate));
}

class BudgetQualityStatisticsSection extends StatelessWidget {
  const BudgetQualityStatisticsSection({
    required this.controller,
    required this.scrollController,
    super.key,
  });
  final StatisticsController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final periods = controller.snapshot.periods;
    final within = periods.where((item) => item.expenses <= item.plan).length;
    final averageError = periods.isEmpty
        ? 0.0
        : periods.fold<double>(
                0,
                (sum, item) =>
                    sum +
                    (item.expenses - item.plan).abs() / math.max(item.plan, 1),
              ) /
              periods.length;
    final recommended = periods.isEmpty
        ? 0
        : (periods
                      .map((item) => item.expenses - item.largePurchases)
                      .reduce((a, b) => a + b) /
                  periods.length *
                  1.08)
              .round();
    return ListView(
      controller: scrollController,
      key: const PageStorageKey('statistics-budget-quality'),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        StatisticsMetricStrip(
          items: [
            StatisticsMetricItem(
              label: 'В пределах',
              value: '$within из ${periods.length}',
              caption: 'завершённых периодов',
              icon: Icons.verified_outlined,
            ),
            StatisticsMetricItem(
              label: 'Ошибка плана',
              value: '${(averageError * 100).toStringAsFixed(0)}%',
              caption: 'среднее отклонение',
              icon: Icons.track_changes_rounded,
            ),
            StatisticsMetricItem(
              label: 'План далее',
              value: formatMoney(recommended, 'RUB'),
              caption: 'рекомендация, не изменение',
              icon: Icons.auto_graph_rounded,
            ),
          ],
        ),
        const SizedBox(height: 16),
        QestoCard(
          child: Column(
            children: [
              const StatisticsSectionHeader(title: 'План и факт по периодам'),
              const SizedBox(height: 10),
              for (final item in periods.reversed.take(8).toList().reversed)
                _BudgetPeriodRow(point: item),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _CategoryOverrunsCard(controller: controller),
        const SizedBox(height: 16),
        const StatisticsInfoBanner(
          message:
              'Рекомендованный план учитывает обычные расходы без крупных покупок и запас 8%. Ничего не меняется автоматически.',
        ),
      ],
    );
  }
}

class RecurringStatisticsSection extends StatelessWidget {
  const RecurringStatisticsSection({
    required this.controller,
    required this.scrollController,
    super.key,
  });
  final StatisticsController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final recurring = controller.snapshot.recurringTransactions;
    final upcoming = controller.budgetController.upcomingExpenses
        .where((item) => item.isRecurring && !item.isCancelled)
        .toList();
    final currentAmount = recurring
        .where((item) => item.type == TransactionType.expense)
        .fold<int>(0, (sum, item) => sum + item.amount);
    final expectedMonthly = upcoming.fold<int>(
      0,
      (sum, item) => sum + item.amount,
    );
    final base = currentAmount > 0 ? currentAmount : expectedMonthly;
    return ListView(
      controller: scrollController,
      key: const PageStorageKey('statistics-recurring'),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
      children: [
        StatisticsMetricStrip(
          items: [
            StatisticsMetricItem(
              label: 'В месяц',
              value: formatMoney(base, 'RUB'),
              caption: 'подтверждённые и ожидаемые',
              icon: Icons.autorenew_rounded,
            ),
            StatisticsMetricItem(
              label: 'В год',
              value: formatMoney(base * 12, 'RUB'),
              caption: 'при текущей стоимости',
              icon: Icons.calendar_month_outlined,
            ),
            StatisticsMetricItem(
              label: 'Платежи',
              value: '${math.max(recurring.length, upcoming.length)}',
              caption: 'регулярных списаний',
              icon: Icons.receipt_long_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _RecurringDynamicsCard(controller: controller),
        const SizedBox(height: 16),
        QestoCard(
          child: Column(
            children: [
              const StatisticsSectionHeader(title: 'Ближайшие списания'),
              const SizedBox(height: 8),
              if (upcoming.isEmpty)
                const StatisticsInfoBanner(
                  message: 'Регулярные платежи пока не найдены',
                )
              else
                for (final item in upcoming)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: QestoColors.primarySoft,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.autorenew_rounded,
                        color: QestoColors.primary,
                      ),
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${formatDate(item.plannedDate)} · ${_status(item.source)}',
                    ),
                    trailing: Text(
                      formatMoney(item.amount, item.currency),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  String _status(UpcomingExpenseSource source) => switch (source) {
    UpcomingExpenseSource.manual => 'подтверждено',
    UpcomingExpenseSource.detectedRecurring => 'требует проверки',
    UpcomingExpenseSource.subscription => 'найдено автоматически',
  };
}

class _HorizontalValueRow extends StatelessWidget {
  const _HorizontalValueRow({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.caption,
  });
  final String label;
  final int value;
  final int maxValue;
  final String caption;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              formatMoney(value, 'RUB'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: value / math.max(maxValue, 1),
          minHeight: 7,
          borderRadius: BorderRadius.circular(6),
          backgroundColor: QestoColors.border,
        ),
        const SizedBox(height: 4),
        Text(caption, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _WeeksCard extends StatelessWidget {
  const _WeeksCard({required this.controller});
  final StatisticsController controller;

  @override
  Widget build(BuildContext context) {
    final totals = <int, int>{};
    for (final point in controller.snapshot.daily) {
      final week =
          point.date.difference(controller.query.period.start).inDays ~/ 7 + 1;
      totals.update(
        week,
        (value) => value + point.amount,
        ifAbsent: () => point.amount,
      );
    }
    final maxValue = totals.values.fold<int>(1, math.max);
    return QestoCard(
      child: Column(
        children: [
          const StatisticsSectionHeader(title: 'Недели периода'),
          const SizedBox(height: 8),
          for (final entry in totals.entries)
            _HorizontalValueRow(
              label: '${entry.key}-я неделя',
              value: entry.value,
              maxValue: maxValue,
              caption:
                  '${(entry.value / math.max(controller.snapshot.summary.expenses, 1) * 100).toStringAsFixed(0)}% расходов периода',
            ),
        ],
      ),
    );
  }
}

class _SalaryCycleCard extends StatelessWidget {
  const _SalaryCycleCard({required this.controller});
  final StatisticsController controller;

  @override
  Widget build(BuildContext context) {
    final income = controller.snapshot.transactions
        .where((item) => item.type == TransactionType.income)
        .toList();
    if (income.isEmpty) {
      return const EmptyState(
        message: 'Зарплатный цикл не настроен',
        icon: Icons.payments_outlined,
      );
    }
    final salaryDay = income.first.date;
    final firstFive = controller.snapshot.transactions
        .where(controller.calculationService.isConsumerExpense)
        .where(
          (item) =>
              !item.date.isBefore(salaryDay) &&
              item.date.difference(salaryDay).inDays < 5,
        )
        .fold<int>(
          0,
          (sum, item) =>
              sum + controller.calculationService.signedExpense(item),
        );
    final share = firstFive / math.max(controller.snapshot.summary.expenses, 1);
    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatisticsSectionHeader(title: 'Зарплатный цикл'),
          const SizedBox(height: 10),
          Text(
            'Первые 5 дней после поступления',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 5),
          Text(
            '${(share * 100).toStringAsFixed(0)}% расходов',
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          StatisticsInfoBanner(
            message:
                'С ${formatDate(salaryDay)} потрачено ${formatMoney(firstFive, 'RUB')}. Это наблюдение, а не оценка привычек.',
          ),
        ],
      ),
    );
  }
}

class _CategoryPlanCard extends StatelessWidget {
  const _CategoryPlanCard({required this.controller});
  final StatisticsController controller;

  @override
  Widget build(BuildContext context) {
    final activePeriod = controller.budgetController.periods
        .where((item) => item.contains(controller.query.period.end))
        .firstOrNull;
    final plans = activePeriod == null
        ? const <CategoryPlanStatus>[]
        : controller.budgetController.categoryPlansFor(activePeriod);
    return QestoCard(
      child: Column(
        children: [
          const StatisticsSectionHeader(title: 'План против факта'),
          const SizedBox(height: 8),
          if (plans.isEmpty)
            const StatisticsInfoBanner(
              message: 'Для выбранного периода планы категорий не настроены',
            )
          else
            for (final item in plans.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.category.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          item.hasAssignedBudget
                              ? '${formatMoney(item.spentAmount, 'RUB')} из ${formatMoney(item.plannedAmount, 'RUB')}'
                              : '${formatMoney(item.spentAmount, 'RUB')} · бюджет не назначен',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: item.progress.clamp(0, 1),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(7),
                      backgroundColor: QestoColors.border,
                      valueColor: AlwaysStoppedAnimation(
                        !item.hasAssignedBudget
                            ? QestoColors.secondaryText
                            : item.isExceeded
                            ? QestoColors.orange
                            : QestoColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _CategoryStabilityCard extends StatelessWidget {
  const _CategoryStabilityCard({required this.controller});
  final StatisticsController controller;

  @override
  Widget build(BuildContext context) {
    final top = controller.snapshot.categories.first;
    final values = controller.snapshot.periods.map((period) {
      final transactions = controller.budgetController.transactions
          .where((item) => period.period.contains(item.date))
          .where((item) => item.categoryId == top.id);
      return controller.calculationService.expenses(transactions);
    }).toList();
    final average = values.isEmpty
        ? 0
        : values.reduce((a, b) => a + b) / values.length;
    final minValue = values.isEmpty ? 0 : values.reduce(math.min);
    final maxValue = values.isEmpty ? 0 : values.reduce(math.max);
    final variation = average <= 0 ? 0 : (maxValue - minValue) / average;
    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatisticsSectionHeader(title: 'Стабильность: ${top.label}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              _SmallMetric(
                label: 'Среднее',
                value: formatMoney(average.round(), 'RUB'),
              ),
              _SmallMetric(
                label: 'Минимум',
                value: formatMoney(minValue, 'RUB'),
              ),
              _SmallMetric(
                label: 'Максимум',
                value: formatMoney(maxValue, 'RUB'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StatisticsInfoBanner(
            message: variation < 0.25
                ? 'Расходы относительно стабильны'
                : variation < 0.7
                ? 'Расходы меняются от периода к периоду'
                : 'Наблюдаются редкие крупные изменения',
          ),
        ],
      ),
    );
  }
}

class _CategoriesWithoutPlanCard extends StatelessWidget {
  const _CategoriesWithoutPlanCard({required this.controller});
  final StatisticsController controller;

  @override
  Widget build(BuildContext context) {
    final activePeriod = controller.budgetController.periods
        .where((item) => item.contains(controller.query.period.end))
        .firstOrNull;
    final plannedIds = activePeriod == null
        ? <String>{}
        : controller.budgetController.categoryBudgets
              .where((item) => item.budgetPeriodId == activePeriod.id)
              .map((item) => item.categoryId)
              .toSet();
    final withoutPlan = controller.snapshot.categories
        .where((item) => !plannedIds.contains(item.id))
        .toList();
    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatisticsSectionHeader(title: 'Категории без плана'),
          const SizedBox(height: 8),
          if (withoutPlan.isEmpty)
            const StatisticsInfoBanner(
              message: 'У всех активных категорий есть план',
            )
          else
            for (final item in withoutPlan.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.label),
                trailing: Text(
                  formatMoney(item.amount, 'RUB'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
        ],
      ),
    );
  }
}

class _IncomeExpensePeriodsCard extends StatelessWidget {
  const _IncomeExpensePeriodsCard({required this.points});
  final List<StatisticsPeriodPoint> points;

  @override
  Widget build(BuildContext context) {
    final visible = points.reversed.take(6).toList().reversed.toList();
    final maxValue = visible.fold<int>(
      1,
      (value, item) => math.max(value, math.max(item.income, item.expenses)),
    );
    return QestoCard(
      child: Column(
        children: [
          const StatisticsSectionHeader(title: 'Доходы и расходы'),
          const SizedBox(height: 12),
          for (final item in visible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 68,
                        child: Text(
                          capitalize(
                            formatBudgetPeriod(
                              item.period.month,
                              item.period.year,
                            ),
                          ),
                        ),
                      ),
                      const Text(
                        'Доход',
                        style: TextStyle(
                          fontSize: 12,
                          color: QestoColors.secondaryText,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatMoney(item.income, 'RUB'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: item.income / maxValue,
                    minHeight: 7,
                    borderRadius: BorderRadius.circular(6),
                    backgroundColor: QestoColors.border,
                    valueColor: const AlwaysStoppedAnimation(QestoColors.green),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const SizedBox(width: 68),
                      const Text(
                        'Расход',
                        style: TextStyle(
                          fontSize: 12,
                          color: QestoColors.secondaryText,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatMoney(item.expenses, 'RUB'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: item.expenses / maxValue,
                    minHeight: 7,
                    borderRadius: BorderRadius.circular(6),
                    backgroundColor: QestoColors.border,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CashFlowWaterfall extends StatelessWidget {
  const _CashFlowWaterfall({required this.controller});
  final StatisticsController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final large = snapshot.transactions
        .where(
          (item) =>
              item.type == TransactionType.expense &&
              controller.calculationService.isLargePurchase(
                item,
                snapshot.transactions,
              ),
        )
        .fold<int>(0, (sum, item) => sum + item.amount);
    final recurring = snapshot.recurringTransactions
        .where((item) => item.type == TransactionType.expense)
        .fold<int>(0, (sum, item) => sum + item.amount);
    final ordinary = math.max(snapshot.summary.expenses - large - recurring, 0);
    final values = [
      ('Доходы', snapshot.summary.income, true),
      ('Обычные расходы', ordinary, false),
      ('Крупные покупки', large, false),
      ('Регулярные', recurring, false),
      ('Накопления', snapshot.summary.savings, false),
      ('Остаток', snapshot.summary.balance, true),
    ];
    return QestoCard(
      child: Column(
        children: [
          const StatisticsSectionHeader(title: 'Разложение потока'),
          const SizedBox(height: 8),
          for (final item in values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Icon(
                    item.$3
                        ? Icons.add_circle_outline_rounded
                        : Icons.remove_circle_outline_rounded,
                    color: item.$3 ? QestoColors.green : QestoColors.orange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.$1,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    formatMoney(item.$2, 'RUB'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _IncomeSourcesCard extends StatelessWidget {
  const _IncomeSourcesCard({required this.controller});
  final StatisticsController controller;

  @override
  Widget build(BuildContext context) {
    final groups = <String, int>{};
    for (final item in controller.snapshot.transactions.where(
      (item) => item.type == TransactionType.income,
    )) {
      final title = item.title ?? 'Другие поступления';
      groups.update(
        title,
        (value) => value + item.amount,
        ifAbsent: () => item.amount,
      );
    }
    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatisticsSectionHeader(title: 'Источники дохода'),
          const SizedBox(height: 8),
          if (groups.isEmpty)
            const StatisticsInfoBanner(
              message:
                  'В периоде нет обычных доходов. Возвраты не смешиваются с доходами.',
            )
          else
            for (final entry in groups.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.south_west_rounded,
                  color: QestoColors.green,
                ),
                title: Text(entry.key),
                trailing: Text(
                  formatMoney(entry.value, 'RUB'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
        ],
      ),
    );
  }
}

class _BudgetPeriodRow extends StatelessWidget {
  const _BudgetPeriodRow({required this.point});
  final StatisticsPeriodPoint point;

  @override
  Widget build(BuildContext context) {
    final hasBudget = point.plan > 0;
    final ratio = hasBudget ? point.expenses / point.plan : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  capitalize(
                    formatBudgetPeriod(point.period.month, point.period.year),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                hasBudget
                    ? '${formatMoney(point.expenses, 'RUB')} / ${formatMoney(point.plan, 'RUB')}'
                    : '${formatMoney(point.expenses, 'RUB')} · бюджет не назначен',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: ratio.clamp(0, 1),
            minHeight: 8,
            borderRadius: BorderRadius.circular(7),
            backgroundColor: QestoColors.border,
            valueColor: AlwaysStoppedAnimation(
              !hasBudget
                  ? QestoColors.secondaryText
                  : ratio > 1
                  ? QestoColors.orange
                  : QestoColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              !hasBudget
                  ? 'Назначьте бюджет для сравнения'
                  : ratio > 1
                  ? '↑ превышение ${(ratio * 100 - 100).toStringAsFixed(0)}%'
                  : '✓ в пределах плана',
              style: TextStyle(
                fontSize: 12,
                color: !hasBudget
                    ? QestoColors.secondaryText
                    : ratio > 1
                    ? const Color(0xFFB76500)
                    : const Color(0xFF168C4A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryOverrunsCard extends StatelessWidget {
  const _CategoryOverrunsCard({required this.controller});
  final StatisticsController controller;

  @override
  Widget build(BuildContext context) {
    final period = controller.budgetController.periods
        .where((item) => item.contains(controller.query.period.end))
        .firstOrNull;
    final plans = period == null
        ? const <CategoryPlanStatus>[]
        : controller.budgetController.categoryPlansFor(period);
    final exceeded = plans.where((item) => item.isExceeded).toList();
    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StatisticsSectionHeader(title: 'Категории с превышением'),
          const SizedBox(height: 8),
          if (exceeded.isEmpty)
            const StatisticsInfoBanner(
              message:
                  'В этом периоде нет подтверждённых превышений по категориям',
            )
          else
            for (final item in exceeded)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.category.name),
                subtitle: Text(
                  'План ${formatMoney(item.plannedAmount, 'RUB')}',
                ),
                trailing: Text(
                  '↑ ${formatMoney(item.spentAmount - item.plannedAmount, 'RUB')}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFB76500),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _RecurringDynamicsCard extends StatelessWidget {
  const _RecurringDynamicsCard({required this.controller});
  final StatisticsController controller;

  @override
  Widget build(BuildContext context) {
    final values = <(String, int)>[];
    for (final period
        in controller.snapshot.periods.reversed.take(6).toList().reversed) {
      final amount = controller.budgetController.transactions
          .where((item) => period.period.contains(item.date))
          .where(
            (item) => item.isRecurring && item.type == TransactionType.expense,
          )
          .fold<int>(0, (sum, item) => sum + item.amount);
      values.add((
        capitalize(formatBudgetPeriod(period.period.month, period.period.year)),
        amount,
      ));
    }
    final maxValue = values.fold<int>(
      1,
      (value, item) => math.max(value, item.$2),
    );
    return QestoCard(
      child: Column(
        children: [
          const StatisticsSectionHeader(title: 'Динамика регулярных расходов'),
          const SizedBox(height: 8),
          for (final item in values)
            _HorizontalValueRow(
              label: item.$1,
              value: item.$2,
              maxValue: maxValue,
              caption: item.$2 == 0
                  ? 'нет подтверждённых списаний'
                  : 'подтверждённые платежи',
            ),
        ],
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  const _SmallMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 105,
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
