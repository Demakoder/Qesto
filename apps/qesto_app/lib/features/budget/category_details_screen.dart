import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../core/widgets/nested_screen_header.dart';
import '../../core/widgets/qesto_card.dart';
import '../../core/widgets/qesto_elements.dart';
import '../../core/widgets/states.dart';
import '../../data/models/qesto_models.dart';
import 'services/category_budget_calculation_service.dart';
import 'state/budget_controller.dart';
import 'transaction_details_screen.dart';
import 'widgets/budget_category_icon.dart';

class CategoryDetailsScreen extends StatelessWidget {
  const CategoryDetailsScreen({
    required this.controller,
    required this.period,
    required this.categoryId,
    super.key,
  });

  final BudgetController controller;
  final BudgetPeriod period;
  final String categoryId;

  void _openTransaction(BuildContext context, BudgetTransaction transaction) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionDetailsScreen(
          controller: controller,
          period: period,
          transactionId: transaction.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final category = controller.categoryById(categoryId);
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text(
          category.name,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final plans = controller.categoryPlansFor(period);
          final status =
              plans
                  .where((item) => item.category.id == categoryId)
                  .firstOrNull ??
              CategoryPlanStatus(
                category: category,
                spentAmount: 0,
                plannedAmount: 0,
              );
          final transactions = controller.transactionsForCategory(
            period,
            categoryId,
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
            children: [
              _CategorySummaryCard(status: status, currency: period.currency),
              const SizedBox(height: 14),
              QestoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Динамика по дням',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 126,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _CategoryDailyPainter(c: context.qestoColors,
                          period: period,
                          transactions: transactions,
                          color: Color(category.colorValue),
                          controller: controller,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('Операции', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              if (transactions.isEmpty)
                const EmptyState(
                  message: 'Для этой категории пока нет операций',
                )
              else
                QestoCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      for (
                        var index = 0;
                        index < transactions.length;
                        index++
                      ) ...[
                        _TransactionRow(
                          transaction: transactions[index],
                          account: controller.accountById(
                            transactions[index].accountId,
                          ),
                          onTap: () =>
                              _openTransaction(context, transactions[index]),
                        ),
                        if (index < transactions.length - 1)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CategorySummaryCard extends StatelessWidget {
  const _CategorySummaryCard({required this.status, required this.currency});

  final CategoryPlanStatus status;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final color = Color(status.category.colorValue);
    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BudgetCategoryIcon(
                iconKey: status.category.iconKey,
                color: color,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.category.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      status.isExceeded
                          ? 'Превышено на ${formatMoney(status.remaining.abs(), currency)}'
                          : status.plannedAmount == 0
                          ? 'План не задан'
                          : 'Осталось ${formatMoney(status.remaining, currency)}',
                      style: TextStyle(
                        color: status.isExceeded
                            ? context.qestoColors.danger
                            : context.qestoColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _SummaryValue(
                  label: 'Потрачено',
                  value: formatMoney(status.spentAmount, currency),
                ),
              ),
              Expanded(
                child: _SummaryValue(
                  label: 'План',
                  value: status.plannedAmount == 0
                      ? 'Не задан'
                      : formatMoney(status.plannedAmount, currency),
                ),
              ),
              Expanded(
                child: _SummaryValue(
                  label: 'Выполнено',
                  value: status.plannedAmount == 0
                      ? '—'
                      : formatPercent(status.progress),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          QestoProgressBar(
            value: status.progress,
            color: status.isExceeded ? context.qestoColors.orange : color,
            backgroundColor: status.isExceeded
                ? const Color(0xFFFFE4E1)
                : const Color(0xFFEEF1F6),
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.transaction,
    required this.account,
    required this.onTap,
  });

  final BudgetTransaction transaction;
  final QestoAccount account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final refund = transaction.type == TransactionType.refund;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        title: Text(
          transaction.merchant ?? transaction.title ?? 'Операция',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${formatDate(transaction.date)} · ${transaction.subcategoryId ?? account.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${refund ? '−' : ''}${formatMoney(transaction.amount, transaction.currency)}',
              style: TextStyle(
                color: refund
                    ? context.qestoColors.green
                    : context.qestoColors.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: context.qestoColors.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDailyPainter extends CustomPainter {
 final QestoSemanticColors c;
  const _CategoryDailyPainter({required this.c,
    required this.period,
    required this.transactions,
    required this.color,
    required this.controller,
  });

  final BudgetPeriod period;
  final List<BudgetTransaction> transactions;
  final Color color;
  final BudgetController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final byDay = <int, int>{};
    for (final transaction in transactions) {
      byDay.update(
        transaction.date.day,
        (value) =>
            value + controller.calculationService.signedExpense(transaction),
        ifAbsent: () =>
            controller.calculationService.signedExpense(transaction),
      );
    }
    final maximum = math.max(1, byDay.values.fold<int>(0, math.max));
    final baseline = size.height - 20;
    final barWidth = math.max(2.0, (size.width - 12) / period.dayCount - 2);
    for (var day = 1; day <= period.dayCount; day++) {
      final amount = math.max(byDay[day] ?? 0, 0);
      final height = amount / maximum * (size.height - 32);
      final x = 6 + (day - 1) / period.dayCount * (size.width - 12);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, baseline - height, barWidth, height),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: 0.75));
    }
    canvas.drawLine(
      Offset(4, baseline),
      Offset(size.width - 4, baseline),
      Paint()..color = c.border,
    );
  }

  @override
  bool shouldRepaint(covariant _CategoryDailyPainter oldDelegate) =>
 oldDelegate.c != c ||
      oldDelegate.transactions != transactions ||
      oldDelegate.period.id != period.id;
}
