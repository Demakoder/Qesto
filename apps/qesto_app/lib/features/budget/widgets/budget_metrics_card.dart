import 'package:flutter/material.dart';

import '../../../core/formatters/qesto_formatters.dart';
import '../../../core/theme/qesto_theme.dart';
import '../../../core/widgets/qesto_card.dart';
import '../../../data/models/qesto_models.dart';

class BudgetMetricsCard extends StatelessWidget {
  const BudgetMetricsCard({
    required this.period,
    required this.currentExpense,
    required this.planAtDate,
    required this.allowedDailyExpense,
    required this.activeDate,
    super.key,
  });

  final BudgetPeriod period;
  final int currentExpense;
  final int planAtDate;
  final int allowedDailyExpense;
  final DateTime activeDate;

  @override
  Widget build(BuildContext context) {
    final hasBudget = period.hasAssignedBudget;
    final exceeded = hasBudget && currentExpense > period.totalPlan;
    return QestoCard(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - 20) / 2;
          return Wrap(
            spacing: 20,
            runSpacing: 26,
            children: [
              SizedBox(
                width: itemWidth,
                child: _Metric(
                  label: 'Текущий расход',
                  value: formatMoney(currentExpense, period.currency),
                  emphasized: true,
                  valueColor: exceeded ? QestoColors.danger : null,
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: _Metric(
                  label: 'План на ${formatDate(activeDate)}',
                  value: formatMoney(planAtDate, period.currency),
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: _Metric(
                  label: period.type == BudgetPeriodType.calendarMonth
                      ? 'План на месяц'
                      : 'План на период',
                  value: hasBudget
                      ? formatMoney(period.totalPlan, period.currency)
                      : 'Не назначен',
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: _Metric(
                  label: 'Допустимый расход',
                  value: !hasBudget
                      ? 'Назначьте бюджет'
                      : exceeded
                      ? 'Лимит превышен'
                      : allowedDailyExpense == 0
                      ? 'Период завершён'
                      : '${formatMoney(allowedDailyExpense, period.currency)}/день',
                  valueColor: exceeded ? QestoColors.danger : null,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasized;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: QestoColors.secondaryText,
          ),
        ),
        const SizedBox(height: 7),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: emphasized ? 28 : 21,
              height: 1.05,
              letterSpacing: -0.6,
              fontWeight: FontWeight.w800,
              color: valueColor ?? QestoColors.text,
            ),
          ),
        ),
      ],
    );
  }
}
