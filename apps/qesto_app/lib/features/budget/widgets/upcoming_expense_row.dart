import 'package:flutter/material.dart';

import '../../../core/formatters/qesto_formatters.dart';
import '../../../core/theme/qesto_theme.dart';
import '../../../data/models/qesto_models.dart';

class UpcomingExpenseRow extends StatelessWidget {
  const UpcomingExpenseRow({
    required this.expense,
    required this.onTap,
    super.key,
  });

  final UpcomingExpense expense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: QestoGeometry.control,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
          child: Row(
            children: [
              SizedBox(
                width: 38,
                height: 38,
                child: Icon(
                  Icons.calendar_month_outlined,
                  color: context.qestoColors.secondaryText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${formatDate(expense.plannedDate)} · ${expense.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatMoney(expense.amount, expense.currency),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 2),
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
