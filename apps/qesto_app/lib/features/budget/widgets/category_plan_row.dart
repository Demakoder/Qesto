import 'package:flutter/material.dart';

import '../../../core/formatters/qesto_formatters.dart';
import '../../../core/theme/qesto_theme.dart';
import '../../../core/widgets/qesto_elements.dart';
import '../services/category_budget_calculation_service.dart';
import 'budget_category_icon.dart';

class CategoryPlanRow extends StatelessWidget {
  const CategoryPlanRow({
    required this.status,
    required this.currency,
    required this.onTap,
    super.key,
  });

  final CategoryPlanStatus status;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = status.isExceeded
        ? context.qestoColors.orange
        : Color(status.category.colorValue);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: QestoGeometry.control,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              BudgetCategoryIcon(
                iconKey: status.category.iconKey,
                color: Color(status.category.colorValue),
                size: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: formatMoney(status.spentAmount, currency),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: context.qestoColors.text,
                            ),
                          ),
                          TextSpan(
                            text: status.plannedAmount > 0
                                ? ' из ${formatMoney(status.plannedAmount, currency)}'
                                : ' · план не задан',
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 7),
                    QestoProgressBar(
                      value: status.progress,
                      color: color,
                      backgroundColor: status.isExceeded
                          ? const Color(0xFFFFE4E1)
                          : const Color(0xFFEEF1F6),
                      height: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 62,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        status.plannedAmount == 0
                            ? '—'
                            : formatPercent(status.progress),
                        style: TextStyle(
                          color: status.isExceeded
                              ? context.qestoColors.danger
                              : context.qestoColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (status.isExceeded)
                      Text(
                        'Превышение',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: context.qestoColors.danger,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.qestoColors.secondaryText,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
