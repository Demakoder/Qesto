import 'package:flutter/material.dart';

import '../../core/theme/qesto_theme.dart';
import '../../core/widgets/nested_screen_header.dart';
import '../../core/widgets/qesto_card.dart';
import '../../core/widgets/states.dart';
import '../../data/models/qesto_models.dart';
import '../budget/state/budget_controller.dart';

class ActionHistoryScreen extends StatelessWidget {
  const ActionHistoryScreen({required this.controller, super.key});

  final BudgetController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text(
          'История действий',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final actions = controller.actions;
          if (actions.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(18),
              child: EmptyState(
                message: 'Здесь появятся импорт выписок и добавленные операции',
                icon: Icons.history_rounded,
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 30),
            itemCount: actions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _ActionCard(
              action: actions[index],
              onUndo: () => _undo(context, actions[index]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _undo(BuildContext context, FinancialAction action) async {
    final undone = await controller.undoAction(action.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          undone ? 'Действие отменено' : 'Это действие уже отменено',
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action, required this.onUndo});

  final FinancialAction action;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final count =
        action.createdTransactionIds.length +
        action.previousTransactions.length;
    return QestoCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: action.isUndone
                  ? QestoColors.border
                  : QestoColors.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              action.type == FinancialActionType.statementImport
                  ? Icons.upload_file_rounded
                  : Icons.add_circle_outline_rounded,
              color: action.isUndone
                  ? QestoColors.secondaryText
                  : QestoColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_formatDateTime(action.occurredAt)}'
                  '${count == 0 ? '' : ' · операций: $count'}'
                  '${action.isUndone ? ' · отменено' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!action.isUndone) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: Key('undo-action-${action.id}'),
                    onPressed: onUndo,
                    icon: const Icon(Icons.undo_rounded),
                    label: const Text('Отменить'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}
