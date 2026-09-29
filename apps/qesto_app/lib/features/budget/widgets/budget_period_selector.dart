import 'package:flutter/material.dart';

import '../../../core/formatters/qesto_formatters.dart';
import '../../../core/theme/qesto_theme.dart';
import '../../../data/models/qesto_models.dart';

class BudgetPeriodSelector extends StatelessWidget {
  const BudgetPeriodSelector({
    required this.period,
    required this.hasPrevious,
    required this.hasNext,
    this.onPrevious,
    this.onNext,
    this.large = false,
    super.key,
  });

  final BudgetPeriod period;
  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final style = large
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PeriodArrow(
          icon: Icons.chevron_left_rounded,
          enabled: hasPrevious,
          onTap: onPrevious,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            capitalize(
              formatBudgetPeriod(period.month, period.year, includeYear: true),
            ),
            style: style,
          ),
        ),
        _PeriodArrow(
          icon: Icons.chevron_right_rounded,
          enabled: hasNext,
          onTap: onNext,
        ),
      ],
    );
  }
}

class _PeriodArrow extends StatelessWidget {
  const _PeriodArrow({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 48,
      child: IconButton(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 23),
        color: context.qestoColors.secondaryText,
        disabledColor: context.qestoColors.border,
      ),
    );
  }
}
