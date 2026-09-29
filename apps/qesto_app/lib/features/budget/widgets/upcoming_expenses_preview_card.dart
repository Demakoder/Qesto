import 'package:flutter/material.dart';

import '../../../core/theme/qesto_theme.dart';
import '../../../core/widgets/qesto_card.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/qesto_models.dart';
import 'upcoming_expense_row.dart';

class UpcomingExpensesPreviewCard extends StatelessWidget {
  const UpcomingExpensesPreviewCard({
    required this.expenses,
    required this.onAdd,
    required this.onExpenseTap,
    required this.onShowAll,
    super.key,
  });

  final List<UpcomingExpense> expenses;
  final VoidCallback onAdd;
  final ValueChanged<UpcomingExpense> onExpenseTap;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final preview = expenses.take(3).toList();
    return QestoCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Предстоящие траты',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_circle_rounded, size: 23),
                label: const Text('Добавить'),
              ),
            ],
          ),
          if (preview.isEmpty)
            const EmptyState(message: 'Предстоящих трат пока нет')
          else
            for (var index = 0; index < preview.length; index++) ...[
              UpcomingExpenseRow(
                expense: preview[index],
                onTap: () => onExpenseTap(preview[index]),
              ),
              if (index < preview.length - 1)
                Divider(height: 1, color: context.qestoColors.border),
            ],
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              key: const Key('show-all-upcoming-expenses'),
              onPressed: onShowAll,
              child: const Text('Показать все'),
            ),
          ),
        ],
      ),
    );
  }
}
