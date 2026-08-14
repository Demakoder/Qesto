import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../synoball/core/models.dart';
import '../desktop_financial_helpers.dart';
import '../widgets/desktop_charts.dart';
import '../widgets/desktop_components.dart';

class DesktopDashboardPage extends StatelessWidget {
  const DesktopDashboardPage({
    required this.controller,
    required this.onOpenTransactions,
    required this.onOpenBudget,
    required this.onOpenRecurring,
    required this.onOpenTransaction,
    super.key,
  });

  final BudgetController controller;
  final VoidCallback onOpenTransactions;
  final VoidCallback onOpenBudget;
  final VoidCallback onOpenRecurring;
  final ValueChanged<String> onOpenTransaction;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.transactions.isEmpty) {
          return const DesktopEmptyState(
            title: 'Здесь появится финансовая картина',
            message:
                'Добавьте расход, чек или банковскую выписку, чтобы Qesto собрала dashboard.',
            icon: Icons.space_dashboard_outlined,
          );
        }
        final period = controller.periods.firstWhere(
          (item) => item.contains(controller.referenceDate),
          orElse: () => controller.periods.last,
        );
        final summary = controller.summaryFor(period);
        final previous = _previousPeriod(period);
        final previousExpense = previous == null
            ? 0
            : controller.summaryFor(previous).currentExpense;
        final expenseChange = previousExpense == 0
            ? null
            : (summary.currentExpense - previousExpense) / previousExpense;
        final state = controller.financialState;
        final currency = period.currency;
        final capital =
            (state.assets.minorUnits - state.debts.minorUnits) ~/ 100;
        final periodTransactions = controller.transactions.where(
          (transaction) => period.contains(transaction.date),
        );
        final actualIncome = periodTransactions
            .where(
              (transaction) =>
                  transaction.type == TransactionType.income ||
                  transaction.type == TransactionType.refund,
            )
            .fold<int>(0, (total, transaction) => total + transaction.amount);
        final actualExpenses = periodTransactions
            .where((transaction) => transaction.type == TransactionType.expense)
            .fold<int>(0, (total, transaction) => total + transaction.amount);
        final cashflow = actualIncome - actualExpenses;
        final hasBudget = period.hasAssignedBudget;
        final remaining = hasBudget
            ? period.totalPlan - summary.currentExpense
            : null;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 34),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Добрый день',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: QestoColors.secondaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Вот что происходит с вашими деньгами',
                style: TextStyle(
                  color: QestoColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.35,
                ),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1080 ? 4 : 2;
                  const gap = 14.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  final cards = [
                    DesktopKpiCard(
                      label: 'Расходы',
                      value: formatMoney(summary.currentExpense, currency),
                      detail: expenseChange == null
                          ? 'Текущий месяц'
                          : '${expenseChange <= 0 ? '↓' : '↑'} ${expenseChange.abs() * 100 ~/ 1}% к прошлому месяцу',
                      detailColor: expenseChange == null
                          ? null
                          : expenseChange <= 0
                          ? QestoColors.positive
                          : QestoColors.negative,
                      icon: Icons.south_east_rounded,
                      accent: QestoColors.orange,
                    ),
                    DesktopKpiCard(
                      label: 'Денежный поток',
                      value: formatMoney(cashflow, currency, showSign: true),
                      detail: 'Доходы минус расходы',
                      icon: Icons.swap_vert_rounded,
                      accent: cashflow >= 0
                          ? QestoColors.positive
                          : QestoColors.negative,
                    ),
                    DesktopKpiCard(
                      label: 'Капитал',
                      value: formatMoney(capital, currency),
                      detail: '${controller.accounts.length} счетов и активов',
                      icon: Icons.show_chart_rounded,
                      accent: QestoColors.purple,
                    ),
                    DesktopKpiCard(
                      label: 'Доступно до конца месяца',
                      value: hasBudget
                          ? formatMoney(remaining!, currency)
                          : 'Не назначен',
                      detail: !hasBudget
                          ? 'Выберите бюджет'
                          : remaining! >= 0
                          ? 'В пределах плана'
                          : 'План превышен',
                      detailColor: !hasBudget
                          ? QestoColors.secondaryText
                          : remaining! >= 0
                          ? QestoColors.positive
                          : QestoColors.negative,
                      icon: Icons.event_available_outlined,
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
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 850;
                  final trajectory = _SpendingCard(
                    controller: controller,
                    period: period,
                    onOpenTransactions: onOpenTransactions,
                  );
                  final categories = _TopCategoriesCard(
                    summary: summary,
                    currency: currency,
                    onOpenBudget: onOpenBudget,
                  );
                  if (stacked) {
                    return Column(
                      children: [
                        trajectory,
                        const SizedBox(height: 16),
                        categories,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: trajectory),
                      const SizedBox(width: 16),
                      Expanded(child: categories),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final stacked = constraints.maxWidth < 850;
                  final review = _ReviewCard(
                    controller: controller,
                    onOpenTransactions: onOpenTransactions,
                    onOpenTransaction: onOpenTransaction,
                  );
                  final upcoming = _UpcomingCard(
                    controller: controller,
                    period: period,
                    onOpenRecurring: onOpenRecurring,
                  );
                  if (stacked) {
                    return Column(
                      children: [review, const SizedBox(height: 16), upcoming],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: review),
                      const SizedBox(width: 16),
                      Expanded(child: upcoming),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _InsightCard(controller: controller, period: period),
              const SizedBox(height: 16),
              _LatestTransactionsCard(
                controller: controller,
                onOpenTransactions: onOpenTransactions,
                onOpenTransaction: onOpenTransaction,
              ),
            ],
          ),
        );
      },
    );
  }

  BudgetPeriod? _previousPeriod(BudgetPeriod current) {
    final index = controller.periods.indexWhere(
      (item) => item.id == current.id,
    );
    return index <= 0 ? null : controller.periods[index - 1];
  }
}

class _SpendingCard extends StatelessWidget {
  const _SpendingCard({
    required this.controller,
    required this.period,
    required this.onOpenTransactions,
  });

  final BudgetController controller;
  final BudgetPeriod period;
  final VoidCallback onOpenTransactions;

  @override
  Widget build(BuildContext context) {
    final hasBudget = period.hasAssignedBudget;
    final forecast = controller.forecastFor(period);
    final actual = forecast.actualPoints.map((point) => point.amount).toList();
    final plan = hasBudget
        ? <double>[
            for (var day = 1; day <= period.dayCount; day++)
              period.totalPlan * day / period.dayCount,
          ]
        : const <double>[];
    final projected = List<double>.filled(period.dayCount, 0);
    for (var index = 0; index < actual.length; index++) {
      projected[index] = actual[index];
    }
    final current = actual.isEmpty ? 0.0 : actual.last;
    final recentRate = actual.length < 2
        ? 0.0
        : (actual.last - actual[math.max(0, actual.length - 7)]) /
              math.min(6, actual.length - 1);
    for (var index = actual.length; index < projected.length; index++) {
      projected[index] = current + recentRate * (index - actual.length + 1);
    }
    final remaining = hasBudget ? period.totalPlan - current.round() : 0;
    final activeDate = controller.activeDateFor(period);
    final daysLeft = math.max(
      1,
      period.endDate.difference(activeDate).inDays + 1,
    );
    final safeDaily = math.max(0, remaining) ~/ daysLeft;
    return DesktopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesktopSectionHeader(
            title: 'Ритм расходов',
            subtitle: hasBudget
                ? 'Фактический темп против идеальной линии бюджета'
                : 'Расходы показаны без сравнения: бюджет не назначен',
            trailing: DesktopTextButton(
              label: 'Транзакции',
              icon: Icons.arrow_forward_rounded,
              onPressed: onOpenTransactions,
            ),
          ),
          const SizedBox(height: 12),
          SpendingTrajectoryChart(
            actual: actual,
            plan: plan,
            forecast: projected,
            currency: period.currency,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 15,
            runSpacing: 6,
            children: [
              const _LegendDot(label: 'Факт', color: QestoColors.primary),
              if (hasBudget) ...const [
                _LegendDot(label: 'План', color: Color(0xFFBBC3D1)),
                _LegendDot(label: 'Прогноз', color: QestoColors.purple),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Container(
            key: const Key('desktop-free-to-spend'),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: !hasBudget || remaining >= 0
                  ? QestoColors.primarySoft
                  : const Color(0xFFFFEFED),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Icon(
                  !hasBudget
                      ? Icons.account_balance_wallet_outlined
                      : remaining >= 0
                      ? Icons.speed_rounded
                      : Icons.warning_amber_rounded,
                  size: 18,
                  color: !hasBudget || remaining >= 0
                      ? QestoColors.primary
                      : QestoColors.negative,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    !hasBudget
                        ? 'Бюджет не назначен — выберите месячный лимит'
                        : remaining >= 0
                        ? 'Свободно к трате: ${formatMoney(remaining, period.currency)}'
                        : 'Превышение плана: ${formatMoney(remaining.abs(), period.currency)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  !hasBudget
                      ? 'Без процентов и превышений'
                      : remaining >= 0
                      ? '${formatMoney(safeDaily, period.currency)} / день'
                      : 'Нужна корректировка',
                  style: TextStyle(
                    color: !hasBudget || remaining >= 0
                        ? QestoColors.primary
                        : QestoColors.negative,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
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

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(color: QestoColors.secondaryText, fontSize: 11),
      ),
    ],
  );
}

class _TopCategoriesCard extends StatelessWidget {
  const _TopCategoriesCard({
    required this.summary,
    required this.currency,
    required this.onOpenBudget,
  });

  final BudgetSummary summary;
  final String currency;
  final VoidCallback onOpenBudget;

  @override
  Widget build(BuildContext context) {
    final categories = summary.categories.take(5).toList();
    final maxAmount = categories.isEmpty ? 1 : categories.first.amount;
    return DesktopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesktopSectionHeader(
            title: 'Верхние категории',
            trailing: DesktopTextButton(
              label: 'Бюджет',
              onPressed: onOpenBudget,
            ),
          ),
          const SizedBox(height: 18),
          if (categories.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'Пока нет расходов',
                  style: TextStyle(color: QestoColors.secondaryText),
                ),
              ),
            )
          else
            for (final category in categories) ...[
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: Color(category.colorValue),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    formatMoney(category.amount, currency),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              DesktopProgressBar(
                value: category.amount / maxAmount,
                color: Color(category.colorValue),
                height: 5,
              ),
              const SizedBox(height: 13),
            ],
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.controller,
    required this.onOpenTransactions,
    required this.onOpenTransaction,
  });

  final BudgetController controller;
  final VoidCallback onOpenTransactions;
  final ValueChanged<String> onOpenTransaction;

  @override
  Widget build(BuildContext context) {
    final transactions = controller.transactions
        .where(desktopNeedsReview)
        .take(3)
        .toList();
    final candidates = controller.pendingCandidates.take(3).toList();
    final count = transactions.length + candidates.length;
    return DesktopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesktopSectionHeader(
            title: 'Требуют проверки',
            subtitle: count == 0
                ? 'Всё разобрано'
                : '$count операций ждут решения',
            trailing: DesktopTextButton(
              label: 'Все',
              onPressed: onOpenTransactions,
            ),
          ),
          const SizedBox(height: 12),
          if (count == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    color: QestoColors.positive,
                  ),
                  SizedBox(width: 8),
                  Text('Новых операций для проверки нет'),
                ],
              ),
            )
          else ...[
            for (final candidate in candidates)
              _ReviewCandidateRow(controller: controller, candidate: candidate),
            for (final transaction in transactions)
              _ReviewTransactionRow(
                controller: controller,
                transaction: transaction,
                onTap: () => onOpenTransaction(transaction.id),
              ),
          ],
        ],
      ),
    );
  }
}

class _ReviewCandidateRow extends StatelessWidget {
  const _ReviewCandidateRow({
    required this.controller,
    required this.candidate,
  });
  final BudgetController controller;
  final TransactionCandidate candidate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.mic_none_rounded,
            color: QestoColors.purple,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.merchantGuess ?? candidate.rawDescription,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Голос · уверенность ${(candidate.confidence * 100).round()}%',
                  style: const TextStyle(
                    color: QestoColors.secondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(
              candidate.amount.minorUnits ~/ 100,
              candidate.amount.currency,
            ),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Подтвердить',
            onPressed: () => controller.confirmVoiceCandidate(candidate.id),
            icon: const Icon(
              Icons.check_rounded,
              color: QestoColors.positive,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTransactionRow extends StatelessWidget {
  const _ReviewTransactionRow({
    required this.controller,
    required this.transaction,
    required this.onTap,
  });
  final BudgetController controller;
  final BudgetTransaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(9),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: QestoColors.warning,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desktopTransactionTitle(transaction),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  desktopCategoryName(controller, transaction),
                  style: const TextStyle(
                    color: QestoColors.secondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(desktopSignedAmount(transaction), transaction.currency),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({
    required this.controller,
    required this.period,
    required this.onOpenRecurring,
  });
  final BudgetController controller;
  final BudgetPeriod period;
  final VoidCallback onOpenRecurring;

  @override
  Widget build(BuildContext context) {
    final limit = controller.referenceDate.add(const Duration(days: 14));
    final values = controller
        .upcomingFor(period)
        .where(
          (item) =>
              !item.plannedDate.isBefore(controller.referenceDate) &&
              !item.plannedDate.isAfter(limit),
        )
        .take(4)
        .toList();
    return DesktopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesktopSectionHeader(
            title: 'Следующие 14 дней',
            trailing: DesktopTextButton(
              label: 'Все',
              onPressed: onOpenRecurring,
            ),
          ),
          const SizedBox(height: 14),
          if (values.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Нет запланированных списаний',
                style: TextStyle(color: QestoColors.secondaryText),
              ),
            )
          else
            for (final item in values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 42,
                      child: Text(
                        '${item.plannedDate.day} авг',
                        style: const TextStyle(
                          color: QestoColors.secondaryText,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(-item.amount, item.currency),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
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

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.controller, required this.period});
  final BudgetController controller;
  final BudgetPeriod period;

  @override
  Widget build(BuildContext context) {
    final cafes = controller.transactionsForCategory(period, 'cafes');
    final amount = cafes.fold<int>(0, (sum, item) => sum + item.amount);
    final message = cafes.isEmpty
        ? 'Qesto продолжает собирать историю. Когда данных станет больше, здесь появится одно главное наблюдение.'
        : 'На кафе в этом месяце ушло ${formatMoney(amount, period.currency)}. ${cafes.length >= 3 ? 'Большая часть покупок приходится на вечер.' : 'Пока это спокойный темп.'}';
    return DesktopCard(
      color: const Color(0xFFF1F5FF),
      borderColor: const Color(0xFFDCE7FF),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: QestoColors.primary.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: QestoColors.primary,
              size: 21,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Qesto заметила',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: QestoColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          DesktopTextButton(
            label: 'Подробнее',
            icon: Icons.arrow_forward_rounded,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _LatestTransactionsCard extends StatelessWidget {
  const _LatestTransactionsCard({
    required this.controller,
    required this.onOpenTransactions,
    required this.onOpenTransaction,
  });
  final BudgetController controller;
  final VoidCallback onOpenTransactions;
  final ValueChanged<String> onOpenTransaction;

  @override
  Widget build(BuildContext context) {
    final values = controller.transactions.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return DesktopCard(
      child: Column(
        children: [
          DesktopSectionHeader(
            title: 'Последние операции',
            trailing: DesktopTextButton(
              label: 'Все транзакции',
              icon: Icons.arrow_forward_rounded,
              onPressed: onOpenTransactions,
            ),
          ),
          const SizedBox(height: 10),
          for (final transaction in values.take(5))
            InkWell(
              onTap: () => onOpenTransaction(transaction.id),
              borderRadius: BorderRadius.circular(9),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 4,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: QestoColors.surfaceSecondary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.shopping_bag_outlined,
                        size: 17,
                        color: QestoColors.secondaryText,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: Text(
                        desktopTransactionTitle(transaction),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        desktopCategoryName(controller, transaction),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: QestoColors.secondaryText,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 82,
                      child: Text(
                        formatDate(transaction.date),
                        style: const TextStyle(
                          color: QestoColors.secondaryText,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: Text(
                        formatMoney(
                          desktopSignedAmount(transaction),
                          transaction.currency,
                          showSign: true,
                        ),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: desktopAmountColor(transaction),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
