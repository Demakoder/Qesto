import 'package:flutter/material.dart';

import '../../../core/formatters/qesto_formatters.dart';
import '../../../core/theme/qesto_theme.dart';
import '../../../core/widgets/qesto_card.dart';
import '../../../core/widgets/qesto_elements.dart';
import '../../../data/models/qesto_models.dart';

class BudgetLimitCard extends StatelessWidget {
  const BudgetLimitCard({
    required this.summary,
    required this.onTap,
    super.key,
  });

  final BudgetSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final period = summary.period;
    final hasBudget = summary.hasAssignedBudget;
    final exceeded = hasBudget && summary.remainingAmount < 0;
    final accent = !hasBudget
        ? QestoColors.secondaryText
        : exceeded
        ? QestoColors.danger
        : QestoColors.primary;
    final percent = hasBudget ? formatPercent(summary.progress) : 'Не назначен';
    final periodName = formatBudgetPeriod(period.month, period.year);

    return QestoCard(
      onTap: onTap,
      semanticsLabel: 'Открыть детали бюджета за $periodName',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Бюджет на $periodName',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: QestoColors.secondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 7,
                  runSpacing: 4,
                  children: [
                    AmountText(
                      formatMoney(summary.currentExpense, period.currency),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        hasBudget
                            ? '/ ${formatMoney(period.totalPlan, period.currency)}'
                            : '/ бюджет не назначен',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: QestoColors.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  percent,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          QestoProgressBar(value: summary.progress, color: accent),
          const SizedBox(height: 10),
          Text(
            !hasBudget
                ? 'Назначьте общий бюджет, чтобы Qesto рассчитала темп и остаток'
                : exceeded
                ? 'Превышение лимита на ${formatMoney(summary.remainingAmount.abs(), period.currency)}'
                : 'Осталось ${formatMoney(summary.remainingAmount, period.currency)} до лимита',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: exceeded ? QestoColors.danger : QestoColors.secondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
