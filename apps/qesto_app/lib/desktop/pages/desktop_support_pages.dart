import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../features/classification/category_manager_screen.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/app_appearance_controller.dart';
import '../../core/theme/qesto_theme.dart';
import '../../design_system/qesto_window.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/ai_export/presentation/ai_export_page.dart';
import '../../features/capital/domain/goal_planning_service.dart';
import '../../features/profile/services/cbr_currency_service.dart';
import '../../features/trash/transaction_trash_screen.dart';
import '../../synoball/ai/context.dart';
import '../widgets/desktop_chrome.dart';
import '../widgets/desktop_components.dart';

class DesktopGoalsPage extends StatelessWidget {
  const DesktopGoalsPage({required this.controller, super.key});
  final BudgetController controller;
  static const _planningService = GoalPlanningService();

  static const categories = <String>[
    'Финансовая подушка',
    'Путешествие',
    'Крупная покупка',
    'Жильё',
    'Образование',
    'Другое',
  ];

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final portfolio = _planningService.calculate(
      goals: controller.savingsGoals,
      allocations: controller.goalAllocations,
      contributions: controller.goalContributions,
      asOf: controller.referenceDate,
      baseCurrency: controller.user.defaultCurrency,
    );
    if (portfolio.goals.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(26, 20, 26, 30),
        children: [
          _GoalsHeader(onAdd: () => _openEditor(context)),
          const SizedBox(height: 16),
          DesktopEmptyState(
            title: 'Целей пока нет',
            message:
                'Добавьте цель, чтобы Qesto помогал отслеживать прогресс и рассчитывал необходимый темп накопления.',
            icon: Icons.flag_outlined,
            action: FilledButton.icon(
              onPressed: () => _openEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Создать цель'),
            ),
          ),
        ],
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GoalsHeader(onAdd: () => _openEditor(context)),
          const SizedBox(height: 16),
          _GoalsSummaryCard(portfolio: portfolio),
          const SizedBox(height: 16),
          _GoalsMonthlyCard(portfolio: portfolio),
          const SizedBox(height: 20),
          const Text(
            'Активные цели',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final plan in portfolio.goals)
                SizedBox(
                  width: 350,
                  height:
                      352 *
                      math.max(
                        1,
                        MediaQuery.textScalerOf(context).scale(14) / 14,
                      ),
                  child: _GoalCard(
                    plan: plan,
                    onOpen: () => _openDetails(context, plan.goal),
                    onEdit: () => _openEditor(context, goal: plan.goal),
                    onDelete: () => _archive(context, plan.goal),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, {SavingsGoal? goal}) async {
    final title = TextEditingController(text: goal?.title ?? '');
    final target = TextEditingController(
      text: goal == null ? '' : goal.targetAmount.toString(),
    );
    final saved = TextEditingController(
      text: goal == null ? '0' : goal.savedAmount.toString(),
    );
    final desiredMonthly = TextEditingController(
      text: goal?.desiredMonthlyContribution?.toString() ?? '',
    );
    final reminderAmount = TextEditingController(
      text: goal?.reminder?.amount.toString() ?? '',
    );
    final reminderDay = TextEditingController(
      text: goal?.reminder?.day.toString() ?? '12',
    );
    final comment = TextEditingController(text: goal?.comment ?? '');
    var category = goal?.category ?? categories.first;
    var targetDate =
        goal?.targetDate ?? DateTime.now().add(const Duration(days: 180));
    var hasTargetDate = goal?.targetDate != null;
    var currency = goal?.currency ?? controller.user.defaultCurrency;
    var priority = goal?.priority ?? GoalPriority.medium;
    var status = goal?.effectiveStatus ?? GoalStatus.active;
    var reminderEnabled = goal?.reminder?.enabled ?? false;
    var reminderCadence =
        goal?.reminder?.cadence ?? GoalReminderCadence.monthly;
    var goalType = goal?.type ?? GoalType.targetAmount;
    if (!const {'RUB', 'USD', 'EUR', 'CNY'}.contains(currency)) {
      currency = 'RUB';
    }
    String? error;
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          key: const Key('goal-editor-dialog'),
          title: Text(goal == null ? 'Новая цель' : 'Редактировать цель'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('goal-title-field'),
                    controller: title,
                    decoration: const InputDecoration(
                      labelText: 'Название цели',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('goal-category-field'),
                    isExpanded: true,
                    initialValue: category,
                    decoration: const InputDecoration(
                      labelText: 'Категория',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: [
                      for (final item in categories)
                        DropdownMenuItem(value: item, child: Text(item)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => category = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<GoalType>(
                    key: const Key('goal-type-field'),
                    initialValue: goalType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Тип цели',
                      prefixIcon: Icon(Icons.route_outlined),
                    ),
                    items: [
                      for (final item in GoalType.values)
                        DropdownMenuItem(
                          value: item,
                          child: Text(_goalTypeLabel(item)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          goalType = value;
                          if (value == GoalType.targetAmountDate) {
                            hasTargetDate = true;
                          } else if (value == GoalType.targetAmount ||
                              value == GoalType.recurringSaving ||
                              value == GoalType.reserve) {
                            hasTargetDate = false;
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('goal-target-field'),
                          controller: target,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Цель'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const Key('goal-saved-field'),
                          controller: saved,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Накоплено',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 110,
                        child: DropdownButtonFormField<String>(
                          key: const Key('goal-currency-field'),
                          initialValue: currency,
                          decoration: const InputDecoration(
                            labelText: 'Валюта',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'RUB', child: Text('RUB')),
                            DropdownMenuItem(value: 'USD', child: Text('USD')),
                            DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                            DropdownMenuItem(value: 'CNY', child: Text('CNY')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => currency = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('goal-monthly-field'),
                          controller: desiredMonthly,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Желаемый взнос в месяц',
                            prefixIcon: Icon(Icons.savings_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<GoalPriority>(
                          key: const Key('goal-priority-field'),
                          isExpanded: true,
                          initialValue: priority,
                          decoration: const InputDecoration(
                            labelText: 'Приоритет',
                          ),
                          items: [
                            for (final item in GoalPriority.values)
                              DropdownMenuItem(
                                value: item,
                                child: Text(_goalPriorityLabel(item)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => priority = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<GoalStatus>(
                          key: const Key('goal-status-field'),
                          isExpanded: true,
                          initialValue: status,
                          decoration: const InputDecoration(
                            labelText: 'Статус',
                          ),
                          items: [
                            for (final item in GoalStatus.values.where(
                              (item) => item != GoalStatus.archived,
                            ))
                              DropdownMenuItem(
                                value: item,
                                child: Text(_goalStatusLabel(item)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => status = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Установить срок'),
                    subtitle: const Text(
                      'Если срок задан, Qesto рассчитает обязательный взнос',
                    ),
                    value: hasTargetDate,
                    onChanged: (value) => setDialogState(() {
                      hasTargetDate = value;
                      if (value) {
                        goalType = GoalType.targetAmountDate;
                      } else if (goalType == GoalType.targetAmountDate) {
                        goalType = GoalType.targetAmount;
                      }
                    }),
                  ),
                  if (hasTargetDate)
                    InkWell(
                      key: const Key('goal-date-field'),
                      onTap: () async {
                        final value = await showDatePicker(
                          context: context,
                          initialDate: targetDate.isBefore(DateTime.now())
                              ? DateTime.now()
                              : targetDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (value != null) {
                          setDialogState(() => targetDate = value);
                        }
                      },
                      borderRadius: QestoGeometry.control,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Срок цели',
                          prefixIcon: Icon(Icons.event_outlined),
                        ),
                        child: Text(formatDate(targetDate, includeYear: true)),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Напоминать откладывать'),
                    subtitle: const Text(
                      'Настройка сохранится для будущих уведомлений',
                    ),
                    value: reminderEnabled,
                    onChanged: (value) =>
                        setDialogState(() => reminderEnabled = value),
                  ),
                  if (reminderEnabled) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('goal-reminder-amount-field'),
                            controller: reminderAmount,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Сумма напоминания',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            key: const Key('goal-reminder-day-field'),
                            controller: reminderDay,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'День месяца',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 145,
                          child: DropdownButtonFormField<GoalReminderCadence>(
                            isExpanded: true,
                            initialValue: reminderCadence,
                            decoration: const InputDecoration(
                              labelText: 'Периодичность',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: GoalReminderCadence.monthly,
                                child: Text('Ежемесячно'),
                              ),
                              DropdownMenuItem(
                                value: GoalReminderCadence.weekly,
                                child: Text('Еженедельно'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => reminderCadence = value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: comment,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Комментарий',
                      prefixIcon: Icon(Icons.notes_rounded),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
                      style: TextStyle(color: context.qestoColors.danger),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const Key('goal-save-button'),
              onPressed: () {
                final targetAmount = _amount(target.text);
                final reminderValue = _amount(reminderAmount.text);
                final reminderDayValue = _amount(reminderDay.text);
                final targetRequired = goalType != GoalType.recurringSaving;
                if (title.text.trim().isEmpty ||
                    targetAmount < 0 ||
                    (targetRequired && targetAmount <= 0) ||
                    (!targetRequired &&
                        targetAmount == 0 &&
                        _amount(desiredMonthly.text) <= 0)) {
                  setDialogState(
                    () => error = targetRequired
                        ? 'Укажите название и сумму больше нуля'
                        : 'Для регулярной цели укажите ежемесячный взнос',
                  );
                } else if (reminderEnabled &&
                    (reminderValue <= 0 ||
                        reminderDayValue < 1 ||
                        reminderDayValue > 31)) {
                  setDialogState(
                    () => error =
                        'Для напоминания укажите сумму и день от 1 до 31',
                  );
                } else {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (shouldSave == true) {
      final monthly = _amount(desiredMonthly.text);
      final reminder = reminderEnabled
          ? GoalReminder(
              enabled: true,
              amount: _amount(reminderAmount.text),
              day: _amount(reminderDay.text),
              cadence: reminderCadence,
            )
          : null;
      if (goal == null) {
        await controller.addSavingsGoal(
          title: title.text,
          category: category,
          targetAmount: _amount(target.text),
          savedAmount: _amount(saved.text),
          targetDate: hasTargetDate ? targetDate : null,
          currency: currency,
          desiredMonthlyContribution: monthly > 0 ? monthly : null,
          priority: priority,
          status: status,
          reminder: reminder,
          type: goalType,
          comment: comment.text,
        );
      } else {
        await controller.updateSavingsGoal(
          goal.copyWith(
            title: title.text,
            category: category,
            targetAmount: _amount(target.text),
            savedAmount: _amount(saved.text),
            targetDate: hasTargetDate ? targetDate : null,
            currency: currency,
            desiredMonthlyContribution: monthly > 0 ? monthly : null,
            priority: priority,
            status: status,
            isActive: status == GoalStatus.active,
            reminder: reminder,
            type: goalType,
            comment: comment.text,
            clearComment: comment.text.trim().isEmpty,
            clearTargetDate: !hasTargetDate,
            clearDesiredMonthlyContribution: monthly <= 0,
            clearReminder: reminder == null,
          ),
        );
      }
    }
    // The dialog route may still be animating after its Future completes.
    // Keep field controllers alive until its widgets have left the tree.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    title.dispose();
    target.dispose();
    saved.dispose();
    desiredMonthly.dispose();
    reminderAmount.dispose();
    reminderDay.dispose();
    comment.dispose();
  }

  Future<void> _openDetails(BuildContext context, SavingsGoal goal) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) =>
            _DesktopGoalDetailsPage(controller: controller, goalId: goal.id),
      ),
    );
  }

  Future<void> _archive(BuildContext context, SavingsGoal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Архивировать цель?'),
        content: Text(
          '«${goal.title}» исчезнет из активных целей, но история сохранится.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('goal-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('В архив'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.updateSavingsGoal(
        goal.copyWith(status: GoalStatus.archived, isActive: false),
      );
    }
  }

  int _amount(String value) =>
      int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
}

String _goalPriorityLabel(GoalPriority priority) => switch (priority) {
  GoalPriority.low => 'Низкий',
  GoalPriority.medium => 'Обычный',
  GoalPriority.high => 'Высокий',
};

String _goalTypeLabel(GoalType type) => switch (type) {
  GoalType.targetAmountDate => 'Сумма к определённой дате',
  GoalType.targetAmount => 'Целевая сумма без срока',
  GoalType.recurringSaving => 'Откладывать регулярно',
  GoalType.reserve => 'Поддерживать резерв',
};

String _goalStatusLabel(GoalStatus status) => switch (status) {
  GoalStatus.active => 'Активна',
  GoalStatus.funded => 'Сумма собрана',
  GoalStatus.spending => 'Используется',
  GoalStatus.completed => 'Достигнута',
  GoalStatus.paused => 'На паузе',
  GoalStatus.archived => 'В архиве',
};

class _GoalsHeader extends StatelessWidget {
  const _GoalsHeader({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Финансовые цели', style: QestoTypography.sectionTitle),
            SizedBox(height: 4),
            Text(
              'Планируйте сумму и срок накопления',
              style: TextStyle(color: context.qestoColors.secondaryText),
            ),
          ],
        ),
      ),
      FilledButton.icon(
        key: const Key('goal-add-button'),
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Новая цель'),
      ),
    ],
  );
}

class _GoalsSummaryCard extends StatelessWidget {
  const _GoalsSummaryCard({required this.portfolio});
  final GoalPortfolioPlan portfolio;
  @override
  Widget build(BuildContext context) => QestoWindow(
    title: 'Позиция по целям',
    child: LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 600 ? 4 : 2;
        final values = [
          _GoalSummaryValue(
            label: 'Активные цели',
            value: '${portfolio.activeCount}',
          ),
          _GoalSummaryValue(
            label: 'Нужно',
            value: formatMoney(portfolio.targetAmount, portfolio.baseCurrency),
            isMoney: true,
          ),
          _GoalSummaryValue(
            label: 'Накоплено',
            value: formatMoney(portfolio.currentAmount, portfolio.baseCurrency),
            isMoney: true,
          ),
          _GoalSummaryValue(
            label: 'План в месяц',
            value: portfolio.monthlyPlan == 0
                ? 'Не рассчитан'
                : formatMoney(portfolio.monthlyPlan, portfolio.baseCurrency),
            isMoney: portfolio.monthlyPlan != 0,
          ),
        ];
        return Wrap(
          spacing: 16,
          runSpacing: 20,
          children: [
            for (final value in values)
              SizedBox(
                width: (constraints.maxWidth - 16 * (columns - 1)) / columns,
                child: value,
              ),
          ],
        );
      },
    ),
  );
}

class _GoalsMonthlyCard extends StatelessWidget {
  const _GoalsMonthlyCard({required this.portfolio});
  final GoalPortfolioPlan portfolio;

  @override
  Widget build(BuildContext context) => DesktopCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.qestoColors.purple.withValues(alpha: 0.1),
                borderRadius: QestoGeometry.control,
              ),
              child: Icon(
                Icons.calendar_month_outlined,
                color: context.qestoColors.purple,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'План этого месяца',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              portfolio.monthlyPlan == 0
                  ? 'План не задан'
                  : '${(portfolio.monthlyProgress * 100).round()}%',
              style: TextStyle(
                color: context.qestoColors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        DesktopProgressBar(value: portfolio.monthlyProgress, height: 8),
        const SizedBox(height: 12),
        Wrap(
          spacing: 44,
          runSpacing: 10,
          children: [
            _GoalSummaryValue(
              label: 'Нужно отложить',
              value: portfolio.monthlyPlan == 0
                  ? 'Не рассчитано'
                  : formatMoney(portfolio.monthlyPlan, portfolio.baseCurrency),
            ),
            _GoalSummaryValue(
              label: 'Отложено',
              value: formatMoney(
                portfolio.actualThisMonth,
                portfolio.baseCurrency,
              ),
            ),
            _GoalSummaryValue(
              label: 'Осталось',
              value: formatMoney(
                portfolio.monthlyPlanGap,
                portfolio.baseCurrency,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _GoalSummaryValue extends StatelessWidget {
  const _GoalSummaryValue({
    required this.label,
    required this.value,
    this.isMoney = false,
  });
  final bool isMoney;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: context.qestoColors.secondaryText,
          fontSize: 10,
        ),
      ),
      const SizedBox(height: 4),
      if (isMoney)
        QestoHeroMoney(value, large: false)
      else
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
    ],
  );
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.plan,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });
  final GoalPlan plan;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final goal = plan.goal;
    final status = plan.effectiveStatus;
    return DesktopCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status == GoalStatus.completed || status == GoalStatus.funded
                    ? Icons.emoji_events_outlined
                    : Icons.flag_outlined,
                color:
                    status == GoalStatus.completed ||
                        status == GoalStatus.funded
                    ? context.qestoColors.positive
                    : context.qestoColors.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  goal.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                key: Key('goal-edit-${goal.id}'),
                tooltip: 'Редактировать',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                key: Key('goal-delete-${goal.id}'),
                tooltip: 'В архив',
                onPressed: onDelete,
                icon: const Icon(Icons.archive_outlined, size: 18),
              ),
            ],
          ),
          Text(
            goal.category,
            style: TextStyle(
              color: context.qestoColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            goal.targetAmount == 0
                ? '${formatMoney(plan.actualContributionThisMonth, goal.currency)} в этом месяце'
                : '${formatMoney(plan.currentAmount, goal.currency)} из ${formatMoney(goal.targetAmount, goal.currency)}',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          DesktopProgressBar(value: plan.progressPercent, height: 8),
          const SizedBox(height: 8),
          Text(
            plan.needsRestore
                ? 'Нужно восстановить ${formatMoney(plan.remainingAmount, goal.currency)}'
                : status == GoalStatus.completed
                ? 'Цель реализована'
                : status == GoalStatus.funded
                ? 'Необходимая сумма собрана'
                : '${(plan.progressPercent * 100).round()}% накоплено',
            style: TextStyle(
              color: context.qestoColors.secondaryText,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          if (plan.requiredMonthlyContribution != null)
            Text(
              'Нужно откладывать ${formatMoney(plan.requiredMonthlyContribution!, goal.currency)} / месяц',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            )
          else if (plan.projectedCompletionDate != null)
            Text(
              'Текущий темп: примерно ${capitalize(formatBudgetPeriod(plan.projectedCompletionDate!.month, plan.projectedCompletionDate!.year, includeYear: true))}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            )
          else
            Text(
              plan.isTargetDateExpired
                  ? 'Срок цели прошёл · измените дату'
                  : goal.type == GoalType.recurringSaving
                  ? 'План: ${formatMoney(goal.desiredMonthlyContribution ?? 0, goal.currency)} / месяц'
                  : 'Укажите срок или ежемесячный взнос для прогноза',
              style: TextStyle(
                color: plan.isTargetDateExpired
                    ? context.qestoColors.warning
                    : context.qestoColors.secondaryText,
                fontSize: 10,
              ),
            ),
          if (plan.plannedMonthlyContribution != null) ...[
            const SizedBox(height: 8),
            Text(
              'В этом месяце: ${formatMoney(plan.actualContributionThisMonth, goal.currency)} / ${formatMoney(plan.plannedMonthlyContribution!, goal.currency)}',
              style: TextStyle(
                color: context.qestoColors.secondaryText,
                fontSize: 10,
              ),
            ),
          ],
          const Spacer(),
          Row(
            children: [
              Icon(
                Icons.event_outlined,
                size: 15,
                color: context.qestoColors.secondaryText,
              ),
              const SizedBox(width: 6),
              Text(
                goal.targetDate == null
                    ? 'Срок не задан'
                    : 'До ${formatDate(goal.targetDate!, includeYear: true)}',
                style: TextStyle(
                  color: context.qestoColors.secondaryText,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopGoalDetailsPage extends StatelessWidget {
  const _DesktopGoalDetailsPage({
    required this.controller,
    required this.goalId,
  });

  final BudgetController controller;
  final String goalId;
  static const _service = GoalPlanningService();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Цель'),
      leading: IconButton(
        tooltip: 'Назад',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    body: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final goal = controller.savingsGoals
            .where((item) => item.id == goalId)
            .firstOrNull;
        if (goal == null) {
          return const Center(child: Text('Цель не найдена'));
        }
        final plan = _service.calculateGoal(
          goal: goal,
          allocations: controller.goalAllocations
              .where((item) => item.goalId == goal.id)
              .toList(growable: false),
          contributions: controller.goalContributions
              .where((item) => item.goalId == goal.id)
              .toList(growable: false),
          asOf: controller.referenceDate,
        );
        return _buildContent(context, plan);
      },
    ),
  );

  Widget _buildContent(BuildContext context, GoalPlan plan) {
    final goal = plan.goal;
    final events =
        controller.goalHistoryEvents
            .where((item) => item.goalId == goal.id)
            .toList()
          ..sort((left, right) => right.date.compareTo(left.date));
    return ListView(
      key: const Key('goal-details-page'),
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: context.qestoColors.primary.withValues(alpha: 0.1),
                borderRadius: QestoGeometry.control,
              ),
              child: Icon(
                goal.type == GoalType.reserve
                    ? Icons.shield_outlined
                    : Icons.flag_outlined,
                color: context.qestoColors.primary,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goal.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_goalTypeLabel(goal.type)} · ${_goalPriorityLabel(goal.priority)} приоритет',
                    style: TextStyle(color: context.qestoColors.secondaryText),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _addContribution(context, plan),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Пополнение'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: () => _addAllocation(context, plan),
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: const Text('Распределить деньги'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DesktopCard(
          color: context.qestoColors.primarySoft.withValues(alpha: 0.45),
          borderColor: context.qestoColors.primary.withValues(alpha: 0.14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                goal.targetAmount == 0
                    ? formatMoney(
                        plan.actualContributionThisMonth,
                        goal.currency,
                      )
                    : '${formatMoney(plan.currentAmount, goal.currency)} / ${formatMoney(goal.targetAmount, goal.currency)}',
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              DesktopProgressBar(
                value: goal.targetAmount == 0
                    ? plan.plannedMonthlyContribution == null ||
                              plan.plannedMonthlyContribution == 0
                          ? 0
                          : (plan.actualContributionThisMonth /
                                    plan.plannedMonthlyContribution!)
                                .clamp(0, 1)
                    : plan.progressPercent,
                height: 9,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 38,
                runSpacing: 14,
                children: [
                  _GoalDetailMetric(
                    label: plan.needsRestore
                        ? 'Нужно восстановить'
                        : 'Осталось',
                    value: goal.targetAmount == 0
                        ? 'Регулярная цель'
                        : formatMoney(plan.remainingAmount, goal.currency),
                  ),
                  _GoalDetailMetric(
                    label: 'До цели',
                    value: plan.isTargetDateExpired
                        ? 'Срок прошёл'
                        : plan.monthsRemaining == null
                        ? 'Без срока'
                        : '${plan.monthsRemaining} мес.',
                  ),
                  _GoalDetailMetric(
                    label: 'Нужно в месяц',
                    value: plan.requiredMonthlyContribution == null
                        ? 'Не рассчитано'
                        : formatMoney(
                            plan.requiredMonthlyContribution!,
                            goal.currency,
                          ),
                  ),
                  _GoalDetailMetric(
                    label: 'План пользователя',
                    value: plan.plannedMonthlyContribution == null
                        ? 'Не задан'
                        : '${formatMoney(plan.plannedMonthlyContribution!, goal.currency)} / мес.',
                  ),
                ],
              ),
              if (goal.comment?.isNotEmpty == true) ...[
                const SizedBox(height: 14),
                Text(
                  goal.comment!,
                  style: TextStyle(color: context.qestoColors.secondaryText),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final chart = _GoalHistoryCard(goal: goal);
            final month = _GoalMonthProgressCard(plan: plan);
            if (constraints.maxWidth < 850) {
              return Column(
                children: [chart, const SizedBox(height: 14), month],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: chart),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: month),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        _GoalAllocationsCard(
          plan: plan,
          controller: controller,
          onAdd: () => _addAllocation(context, plan),
        ),
        const SizedBox(height: 14),
        _GoalWhatIfCard(plan: plan, asOf: controller.referenceDate),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final contributions = _GoalTimelineCard(
              title: 'Последние пополнения и списания',
              emptyText: 'Операций по цели пока нет',
              children: [
                for (final item in plan.contributions.take(10))
                  _GoalTimelineRow(
                    icon: item.type == GoalContributionType.contribution
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    title: item.type == GoalContributionType.contribution
                        ? 'Пополнение'
                        : 'Списание',
                    subtitle: formatDate(item.date, includeYear: true),
                    value:
                        '${item.type == GoalContributionType.contribution ? '+' : '−'}${formatMoney(item.amount, item.currency)}',
                    color: item.type == GoalContributionType.contribution
                        ? context.qestoColors.positive
                        : context.qestoColors.warning,
                  ),
              ],
            );
            final history = _GoalTimelineCard(
              title: 'История цели',
              emptyText: 'История начнёт собираться с новых изменений',
              children: [
                for (final event in events.take(10))
                  _GoalTimelineRow(
                    icon: Icons.history_rounded,
                    title: event.description,
                    subtitle: formatDate(event.date, includeYear: true),
                    value: event.amount == null
                        ? null
                        : formatMoney(event.amount!, goal.currency),
                  ),
              ],
            );
            if (constraints.maxWidth < 850) {
              return Column(
                children: [contributions, const SizedBox(height: 14), history],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: contributions),
                const SizedBox(width: 14),
                Expanded(child: history),
              ],
            );
          },
        ),
        if (plan.isCompleted && goal.status != GoalStatus.completed) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => controller.updateSavingsGoal(
                goal.copyWith(
                  status: GoalStatus.completed,
                  isActive: false,
                  completedAt: DateTime.now(),
                ),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Отметить цель реализованной'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _addContribution(BuildContext context, GoalPlan plan) async {
    final amount = TextEditingController();
    final comment = TextEditingController();
    var type = GoalContributionType.contribution;
    var date = DateTime.now();
    String? error;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          key: const Key('goal-contribution-dialog'),
          title: const Text('Операция по цели'),
          content: SizedBox(
            width: 410,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<GoalContributionType>(
                  segments: const [
                    ButtonSegment(
                      value: GoalContributionType.contribution,
                      label: Text('Пополнение'),
                    ),
                    ButtonSegment(
                      value: GoalContributionType.withdrawal,
                      label: Text('Списание'),
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: (value) =>
                      setDialogState(() => type = value.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('goal-contribution-amount-field'),
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Сумма, ${plan.goal.currency}',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(formatDate(date, includeYear: true)),
                  onTap: () async {
                    final value = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: plan.goal.createdAt ?? DateTime(2000),
                      lastDate: DateTime.now(),
                    );
                    if (value != null) setDialogState(() => date = value);
                  },
                ),
                TextField(
                  controller: comment,
                  decoration: const InputDecoration(labelText: 'Комментарий'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    error!,
                    style: TextStyle(color: context.qestoColors.danger),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const Key('goal-contribution-save'),
              onPressed: () {
                if (_parseGoalAmount(amount.text) <= 0) {
                  setDialogState(() => error = 'Укажите сумму больше нуля');
                } else {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      await controller.addGoalContribution(
        goalId: plan.goal.id,
        amount: _parseGoalAmount(amount.text),
        type: type,
        date: date,
        comment: comment.text,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    amount.dispose();
    comment.dispose();
  }

  Future<void> _addAllocation(BuildContext context, GoalPlan plan) async {
    final sources = <_GoalSourceOption>[
      for (final account in controller.accounts.where(
        (item) =>
            {
              AccountType.cash,
              AccountType.bankCard,
              AccountType.savings,
              AccountType.deposit,
            }.contains(item.type) &&
            item.balance > 0,
      ))
        _GoalSourceOption(
          id: account.id,
          type: GoalAllocationSourceType.account,
          title: account.title,
          balance: account.balance,
          currency: account.currency,
        ),
      for (final account in controller.investmentAccounts.where(
        (item) => item.isActive && item.currentBalance > 0,
      ))
        _GoalSourceOption(
          id: account.id,
          type: GoalAllocationSourceType.investmentAccount,
          title: account.name,
          balance: account.currentBalance,
          currency: account.currency,
        ),
    ];
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала добавьте счёт с положительным балансом'),
        ),
      );
      return;
    }
    var source = sources.first;
    final amount = TextEditingController();
    String? error;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final existing = controller.goalAllocations
              .where(
                (item) =>
                    item.goalId == plan.goal.id &&
                    item.sourceId == source.id &&
                    item.sourceType == source.type,
              )
              .firstOrNull;
          final availability = _service.allocationAvailability(
            sourceBalance: source.balance,
            sourceId: source.id,
            sourceType: source.type,
            allocations: controller.goalAllocations,
            excludingAllocationId: existing?.id,
          );
          return AlertDialog(
            key: const Key('goal-allocation-dialog'),
            title: const Text('Распределить деньги на цель'),
            content: SizedBox(
              width: 430,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<_GoalSourceOption>(
                    initialValue: source,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Где находятся деньги',
                    ),
                    items: [
                      for (final item in sources)
                        DropdownMenuItem(
                          value: item,
                          child: Text(
                            '${item.title} · ${formatMoney(item.balance, item.currency)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          source = value;
                          amount.clear();
                          error = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('goal-allocation-amount-field'),
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Сумма, ${source.currency}',
                      helperText:
                          'Доступно без двойного распределения: ${formatMoney(availability.available, source.currency)}',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Это логическая разметка. Реальный баланс счёта не изменится.',
                    style: TextStyle(
                      color: context.qestoColors.secondaryText,
                      fontSize: 11,
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(color: context.qestoColors.danger),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                key: const Key('goal-allocation-save'),
                onPressed: () {
                  final value = _parseGoalAmount(amount.text);
                  if (value <= 0 || value > availability.available) {
                    setDialogState(
                      () => error = 'Сумма превышает доступный баланс',
                    );
                  } else {
                    Navigator.pop(dialogContext, true);
                  }
                },
                child: const Text('Распределить'),
              ),
            ],
          );
        },
      ),
    );
    if (save == true) {
      final existing = controller.goalAllocations
          .where(
            (item) =>
                item.goalId == plan.goal.id &&
                item.sourceId == source.id &&
                item.sourceType == source.type,
          )
          .firstOrNull;
      final success = await controller.upsertGoalAllocation(
        GoalAllocation(
          id:
              existing?.id ??
              'goal-allocation-${DateTime.now().microsecondsSinceEpoch}',
          goalId: plan.goal.id,
          sourceType: source.type,
          sourceId: source.id,
          allocatedAmount: _parseGoalAmount(amount.text),
          currency: source.currency,
          updatedAt: DateTime.now(),
        ),
      );
      if (!success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось распределить: проверьте доступный баланс',
            ),
          ),
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    amount.dispose();
  }
}

class _GoalSourceOption {
  const _GoalSourceOption({
    required this.id,
    required this.type,
    required this.title,
    required this.balance,
    required this.currency,
  });
  final String id;
  final GoalAllocationSourceType type;
  final String title;
  final int balance;
  final String currency;
}

class _GoalDetailMetric extends StatelessWidget {
  const _GoalDetailMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.qestoColors.secondaryText,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _GoalHistoryCard extends StatelessWidget {
  const _GoalHistoryCard({required this.goal});
  final SavingsGoal goal;

  @override
  Widget build(BuildContext context) => DesktopCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'График накопления',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 160,
          child: goal.history.length < 2
              ? Center(
                  child: Text(
                    'Недостаточно истории для графика',
                    style: TextStyle(color: context.qestoColors.secondaryText),
                  ),
                )
              : CustomPaint(
                  painter: _GoalHistoryPainter(
                    context.qestoColors,
                    goal.history,
                  ),
                  size: Size.infinite,
                ),
        ),
      ],
    ),
  );
}

class _GoalMonthProgressCard extends StatelessWidget {
  const _GoalMonthProgressCard({required this.plan});
  final GoalPlan plan;

  @override
  Widget build(BuildContext context) {
    final target = plan.plannedMonthlyContribution ?? 0;
    final progress = target <= 0
        ? 0.0
        : (plan.actualContributionThisMonth / target).clamp(0, 1);
    return DesktopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'План месяца',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          Text(
            target <= 0
                ? 'Не задан'
                : '${formatMoney(plan.actualContributionThisMonth, plan.goal.currency)} / ${formatMoney(target, plan.goal.currency)}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          DesktopProgressBar(value: progress.toDouble(), height: 8),
          const SizedBox(height: 9),
          Text(
            target <= 0
                ? 'Укажите ежемесячный взнос в настройках цели'
                : plan.monthlyPlanGap == 0
                ? 'План выполнен'
                : 'Осталось ${formatMoney(plan.monthlyPlanGap, plan.goal.currency)}',
            style: TextStyle(
              color: context.qestoColors.secondaryText,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalAllocationsCard extends StatelessWidget {
  const _GoalAllocationsCard({
    required this.plan,
    required this.controller,
    required this.onAdd,
  });
  final GoalPlan plan;
  final BudgetController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => DesktopCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Где находятся деньги',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Добавить источник'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (plan.allocations.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(
              'Средства пока не связаны с конкретными счетами. Текущая сумма учитывается как ручная.',
              style: TextStyle(color: context.qestoColors.secondaryText),
            ),
          )
        else
          for (final allocation in plan.allocations)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                allocation.sourceType ==
                        GoalAllocationSourceType.investmentAccount
                    ? Icons.show_chart_rounded
                    : Icons.account_balance_wallet_outlined,
                color: context.qestoColors.primary,
              ),
              title: Text(_allocationSourceTitle(controller, allocation)),
              subtitle: Text(
                allocation.sourceType ==
                        GoalAllocationSourceType.investmentAccount
                    ? 'Инвестиционный счёт'
                    : 'Ликвидный счёт',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatMoney(
                      allocation.allocatedAmount,
                      allocation.currency,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  IconButton(
                    tooltip: 'Убрать распределение',
                    onPressed: () =>
                        controller.removeGoalAllocation(allocation.id),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
      ],
    ),
  );
}

class _GoalWhatIfCard extends StatefulWidget {
  const _GoalWhatIfCard({required this.plan, required this.asOf});
  final GoalPlan plan;
  final DateTime asOf;

  @override
  State<_GoalWhatIfCard> createState() => _GoalWhatIfCardState();
}

class _GoalWhatIfCardState extends State<_GoalWhatIfCard> {
  static const _service = GoalPlanningService();
  late final TextEditingController _amount;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.plan.plannedMonthlyContribution?.toString() ?? '',
    )..addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant _GoalWhatIfCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan.goal.id != widget.plan.goal.id) {
      _amount.text = widget.plan.plannedMonthlyContribution?.toString() ?? '';
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _amount
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = _parseGoalAmount(_amount.text);
    final simulation = _service.simulateMonthlyContribution(
      plan: widget.plan,
      monthlyContribution: amount,
      asOf: widget.asOf,
    );
    return DesktopCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.tune_rounded, color: context.qestoColors.purple),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Что если откладывать больше?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 4),
                Text(
                  'Измените сумму — расчёт не повлияет на текущий план',
                  style: TextStyle(
                    color: context.qestoColors.secondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 190,
            child: TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '${widget.plan.goal.currency} / месяц',
              ),
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 210,
            child: Text(
              simulation.projectedDate == null
                  ? 'Укажите сумму для прогноза'
                  : 'Новая дата: ${capitalize(formatBudgetPeriod(simulation.projectedDate!.month, simulation.projectedDate!.year, includeYear: true))}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalTimelineCard extends StatelessWidget {
  const _GoalTimelineCard({
    required this.title,
    required this.emptyText,
    required this.children,
  });
  final String title;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DesktopCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                emptyText,
                style: TextStyle(color: context.qestoColors.secondaryText),
              ),
            ),
          )
        else
          ...children,
      ],
    ),
  );
}

class _GoalTimelineRow extends StatelessWidget {
  const _GoalTimelineRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.value,
    this.color,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                subtitle,
                style: TextStyle(
                  color: context.qestoColors.secondaryText,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        if (value != null)
          Text(
            value!,
            style: TextStyle(
              color: color ?? context.qestoColors.text,
              fontWeight: FontWeight.w800,
            ),
          ),
      ],
    ),
  );
}

class _GoalHistoryPainter extends CustomPainter {
  final QestoSemanticColors c;
  _GoalHistoryPainter(this.c, this.points);
  final List<SavingsHistoryPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final ordered = List<SavingsHistoryPoint>.of(points)
      ..sort((left, right) => left.date.compareTo(right.date));
    if (ordered.length < 2) return;
    final minValue = ordered
        .map((item) => item.amount)
        .reduce(math.min)
        .toDouble();
    final maxValue = ordered
        .map((item) => item.amount)
        .reduce(math.max)
        .toDouble();
    final range = math.max(1, maxValue - minValue);
    final path = Path();
    for (var index = 0; index < ordered.length; index++) {
      final x = size.width * index / (ordered.length - 1);
      final y =
          size.height -
          10 -
          (ordered[index].amount - minValue) / range * (size.height - 20);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = c.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _GoalHistoryPainter oldDelegate) =>
      oldDelegate.c != c || oldDelegate.points != points;
}

String _allocationSourceTitle(
  BudgetController controller,
  GoalAllocation allocation,
) {
  if (allocation.sourceType == GoalAllocationSourceType.investmentAccount) {
    return controller.investmentAccounts
            .where((item) => item.id == allocation.sourceId)
            .map((item) => item.name)
            .firstOrNull ??
        'Инвестиционный счёт';
  }
  if (allocation.sourceType == GoalAllocationSourceType.account) {
    return controller.accounts
            .where((item) => item.id == allocation.sourceId)
            .map((item) => item.title)
            .firstOrNull ??
        'Счёт';
  }
  return 'Ручной актив';
}

int _parseGoalAmount(String value) =>
    int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

class DesktopInsightsPage extends StatelessWidget {
  const DesktopInsightsPage({required this.controller, super.key});
  final BudgetController controller;
  @override
  Widget build(BuildContext context) => AiExportPage(controller: controller);
}

class DesktopAssistantPage extends StatefulWidget {
  const DesktopAssistantPage({required this.controller, super.key});
  final BudgetController controller;
  @override
  State<DesktopAssistantPage> createState() => _DesktopAssistantPageState();
}

class _DesktopAssistantPageState extends State<DesktopAssistantPage> {
  final _messages = <String>[];
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.financialState;
    return Padding(
      padding: QestoSpacing.workspace(context),
      child: Row(
        children: [
          SizedBox(
            width: 285,
            child: DesktopCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DesktopSectionHeader(
                    title: 'Финансовый контекст',
                    subtitle: 'Передаётся AI по задаче',
                  ),
                  const SizedBox(height: 18),
                  _ContextLine(
                    'Ликвидные средства',
                    state.liquidMoney.minorUnits ~/ 100,
                    state.liquidMoney.currency,
                  ),
                  _ContextLine(
                    'Доход месяца',
                    state.monthlyIncome.minorUnits ~/ 100,
                    state.monthlyIncome.currency,
                  ),
                  _ContextLine(
                    'Расходы месяца',
                    state.monthlyExpenses.minorUnits ~/ 100,
                    state.monthlyExpenses.currency,
                  ),
                  _ContextLine(
                    'Свободный cash-flow',
                    state.freeCashflow.minorUnits ~/ 100,
                    state.freeCashflow.currency,
                  ),
                  const Divider(height: 28),
                  Text(
                    'Качество: ${(state.dataQuality.overall * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DesktopProgressBar(
                    value: state.dataQuality.overall,
                    color: state.dataQuality.overall >= 0.7
                        ? context.qestoColors.positive
                        : context.qestoColors.warning,
                  ),
                  const Spacer(),
                  Text(
                    'Сырая полная история в LLM не отправляется.',
                    style: TextStyle(
                      color: context.qestoColors.secondaryText,
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: DesktopCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: DesktopSectionHeader(
                      title: 'Qesto Assistant',
                      subtitle: 'Объяснения поверх deterministic analytics',
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _messages.isEmpty
                        ? Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 590),
                              child: Wrap(
                                spacing: 9,
                                runSpacing: 9,
                                alignment: WrapAlignment.center,
                                children: [
                                  for (final prompt in _prompts)
                                    ActionChip(
                                      label: Text(prompt),
                                      avatar: const Icon(
                                        Icons.auto_awesome_outlined,
                                        size: 16,
                                      ),
                                      onPressed: () => _ask(prompt),
                                    ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(18),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) => Align(
                              alignment: index.isEven
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                constraints: const BoxConstraints(
                                  maxWidth: 590,
                                ),
                                decoration: BoxDecoration(
                                  color: index.isEven
                                      ? context.qestoColors.primary
                                      : context.qestoColors.surfaceSecondary,
                                  borderRadius: QestoGeometry.control,
                                ),
                                child: Text(
                                  _messages[index],
                                  style: TextStyle(
                                    color: index.isEven
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onPrimary
                                        : context.qestoColors.text,
                                    fontSize: 12,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            onSubmitted: _ask,
                            decoration: const InputDecoration(
                              hintText: 'Спросите о своих финансах…',
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        IconButton.filled(
                          onPressed: () => _ask(_input.text),
                          icon: const Icon(Icons.arrow_upward_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: context.qestoColors.primary,
                          ),
                        ),
                      ],
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

  static const _prompts = [
    'Что изменилось в расходах?',
    'Где я трачу больше обычного?',
    'Что ждёт до конца месяца?',
    'Могу ли я позволить себе покупку?',
  ];

  void _ask(String value) {
    final question = value.trim();
    if (question.isEmpty) return;
    final context = widget.controller.aiContext(
      question.contains('покуп')
          ? AiContextPurpose.purchaseDecision
          : AiContextPurpose.financialSummary,
    );
    setState(() {
      _messages.add(question);
      _messages.add(
        'Факты Synoball: свободный cash-flow ${context.facts['freeCashflow'] ?? 'не рассчитан'}, качество данных ${(context.dataQuality * 100).round()}%. Это локальный deterministic preview; подключение LLM используется только для объяснения этих фактов.',
      );
      _input.clear();
    });
  }
}

class _ContextLine extends StatelessWidget {
  const _ContextLine(this.label, this.amount, this.currency);
  final String label;
  final int amount;
  final String currency;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: context.qestoColors.secondaryText,
              fontSize: 11,
            ),
          ),
        ),
        Text(
          formatMoney(amount, currency),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class DesktopBenefitsPage extends StatelessWidget {
  const DesktopBenefitsPage({
    required this.coupons,
    required this.promotions,
    required this.trackedProducts,
    super.key,
  });
  final List<Deal> coupons;
  final List<Deal> promotions;
  final List<TrackedProduct> trackedProducts;
  @override
  Widget build(BuildContext context) {
    final deals = [...coupons, ...promotions];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesktopCard(
            color: Color(0xFFF0F2F3),
            borderColor: Color(0xFFD9DDE0),
            child: Row(
              children: [
                Icon(
                  Icons.savings_outlined,
                  color: context.qestoColors.primary,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Выгода — это действия в контексте ваших расходов. Купоны остаются дополнительным источником, а не основой раздела.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Найденная выгода',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final deal in deals.take(6))
                SizedBox(
                  width: 350,
                  height: 150,
                  child: DesktopCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DesktopPill(
                          label: deal.category,
                          color: context.qestoColors.purple,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          deal.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          deal.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.qestoColors.secondaryText,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final item in trackedProducts)
                SizedBox(
                  width: 350,
                  height: 150,
                  child: DesktopCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DesktopPill(
                          label: 'Отслеживается',
                          color: context.qestoColors.positive,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${formatMoney(item.currentPrice, item.currency)} · ${item.changePercent}% · ${item.bestMarketplace}',
                          style: TextStyle(
                            color: context.qestoColors.secondaryText,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class DesktopSettingsPage extends StatefulWidget {
  const DesktopSettingsPage({required this.controller, super.key});
  final BudgetController controller;

  @override
  State<DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

class _DesktopSettingsPageState extends State<DesktopSettingsPage> {
  static const _avatars = <String?>[
    null,
    'emoji:🙂',
    'emoji:😎',
    'emoji:🧑‍💻',
    'emoji:🦊',
    'emoji:🐼',
    'emoji:🚀',
    'emoji:🌿',
  ];

  late final TextEditingController _nameController;
  late String _currency;
  String? _avatarUrl;
  late Future<CbrRateSnapshot> _ratesFuture;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final user = widget.controller.user;
    _nameController = TextEditingController(text: user.name);
    _currency =
        CbrCurrencyService.supportedCurrencies.contains(user.defaultCurrency)
        ? user.defaultCurrency
        : 'RUB';
    _avatarUrl = user.avatarUrl;
    _ratesFuture = _loadRates();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    await widget.controller.updateUserProfile(
      name: _nameController.text,
      defaultCurrency: _currency,
      avatarUrl: _avatarUrl,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Профиль сохранён')));
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(26, 20, 26, 30),
    children: [
      Text(
        'Профиль',
        style: context.qestoTypography.display(
          TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: context.qestoColors.text,
          ),
        ),
      ),
      const SizedBox(height: 5),
      Text(
        'Личные настройки Qesto. Они не изменяют структуру или историю Synoball.',
        style: TextStyle(
          color: context.qestoColors.secondaryText,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 16),
      DesktopCard(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final profile = _profileEditor(context);
            final appearance = _appearanceEditor(context);
            return compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [profile, const SizedBox(height: 22), appearance],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: profile),
                      const SizedBox(width: 28),
                      Expanded(flex: 5, child: appearance),
                    ],
                  );
          },
        ),
      ),
      const SizedBox(height: 14),
      _currencyRatesCard(),
      const SizedBox(height: 24),
      Text(
        'Система',
        style: context.qestoTypography.display(
          const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      const SizedBox(height: 10),
      _SettingsSection(
        title: 'Счета и источники',
        icon: Icons.account_balance_outlined,
        description:
            '${widget.controller.accounts.length} счетов · ${widget.controller.synoballState.connections.length} подключений',
      ),
      Card(
        child: ListTile(
          title: const Text('Категории и теги'),
          leading: const Icon(Icons.category_outlined),
          trailing: const Icon(Icons.chevron_right),
          subtitle: Text(
            '${widget.controller.categories.length} категорий · ${widget.controller.classification.tags.length} тегов',
          ),
          onTap: () => openCategoryManager(context, widget.controller),
        ),
      ),
      _SettingsSection(
        title: 'Данные',
        icon: Icons.storage_outlined,
        description:
            '${widget.controller.synoballState.ingestionRecords.length} ingestion records · schema v2',
      ),
      TransactionTrashEntry(controller: widget.controller),
      if (const bool.fromEnvironment('DEV_MODE'))
        _SettingsSection(
          title: 'Developer mode',
          icon: Icons.developer_mode_rounded,
          description:
              '${widget.controller.synoballState.rawPayloads.length} raw payloads · ${widget.controller.synoballState.auditEntries.length} audit entries',
        ),
    ],
  );

  Widget _profileEditor(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          DesktopUserAvatar(
            user: widget.controller.user.copyWith(
              name: _nameController.text,
              avatarUrl: _avatarUrl,
              clearAvatar: _avatarUrl == null,
            ),
            radius: 29,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ваш профиль',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 3),
                Text(
                  'Имя, аватар и основная валюта',
                  style: TextStyle(
                    color: context.qestoColors.secondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      TextField(
        key: const Key('profile-name-field'),
        controller: _nameController,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Имя',
          prefixIcon: Icon(Icons.person_outline_rounded),
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Аватар',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final avatar in _avatars)
            ChoiceChip(
              label: Text(
                avatar == null ? 'А' : avatar.substring('emoji:'.length),
              ),
              selected: _avatarUrl == avatar,
              onSelected: (_) => setState(() => _avatarUrl = avatar),
            ),
        ],
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        key: const Key('profile-currency-field'),
        isExpanded: true,
        initialValue: _currency,
        decoration: const InputDecoration(
          labelText: 'Основная валюта',
          prefixIcon: Icon(Icons.currency_exchange_rounded),
        ),
        items: [
          for (final code in CbrCurrencyService.supportedCurrencies)
            DropdownMenuItem(
              value: code,
              child: Text('$code · ${CbrCurrencyService.currencyNames[code]}'),
            ),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _currency = value);
        },
      ),
      const SizedBox(height: 7),
      Text(
        'Существующие операции сохраняют исходную валюту. Выбор применяется к интерфейсу и новым данным.',
        style: TextStyle(
          color: context.qestoColors.secondaryText,
          fontSize: 10,
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const Key('profile-save-button'),
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_rounded, size: 18),
        label: const Text('Сохранить профиль'),
      ),
    ],
  );

  Widget _appearanceEditor(BuildContext context) {
    final appearance = AppAppearanceScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.palette_outlined, color: context.qestoColors.primary),
            SizedBox(width: 9),
            Text(
              'Оформление',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Тема применяется ко всему приложению и сохраняется на устройстве.',
          style: TextStyle(
            color: context.qestoColors.secondaryText,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          key: const Key('profile-theme-selector'),
          spacing: 8,
          runSpacing: 8,
          children: [
            _ThemeChoice(
              label: 'Система',
              icon: Icons.brightness_auto_outlined,
              selected: appearance.preference == QestoThemePreference.system,
              onTap: () => appearance.select(QestoThemePreference.system),
            ),
            _ThemeChoice(
              label: 'Светлая',
              icon: Icons.light_mode_outlined,
              selected: appearance.preference == QestoThemePreference.light,
              onTap: () => appearance.select(QestoThemePreference.light),
            ),
            _ThemeChoice(
              label: 'Тёмная',
              icon: Icons.dark_mode_outlined,
              selected: appearance.preference == QestoThemePreference.dark,
              onTap: () => appearance.select(QestoThemePreference.dark),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.qestoColors.surfaceSecondary,
            borderRadius: QestoGeometry.control,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.text_fields_rounded,
                color: context.qestoColors.primary,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'White Silver: Onest для интерфейса, Prata для заголовков и Noto Serif Display Italic для крупных финансовых значений. Тёмный режим сохраняет светлые финансовые инструменты без инверсии цветов.',
                  style: TextStyle(fontSize: 11, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<CbrRateSnapshot> _loadRates() {
    final future = CbrCurrencyService().loadLatest();
    // On a phone this lazy list item is initially off screen. Attach an error
    // listener now; the FutureBuilder still displays the failure when reached.
    future.ignore();
    return future;
  }

  Widget _currencyRatesCard() => DesktopCard(
    padding: const EdgeInsets.all(18),
    child: FutureBuilder<CbrRateSnapshot>(
      future: _ratesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const DesktopAdaptiveRow(
            children: [
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Получаем официальный курс ЦБ…'),
            ],
          );
        }
        if (!snapshot.hasData) {
          return Row(
            children: [
              Icon(
                Icons.cloud_off_outlined,
                color: context.qestoColors.warning,
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  'Курс ЦБ сейчас недоступен. Валюту можно выбрать без конвертации данных.',
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _ratesFuture = _loadRates()),
                child: const Text('Повторить'),
              ),
            ],
          );
        }
        final value = snapshot.requireData;
        final rate = value.rates[_currency];
        return Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: context.qestoColors.primarySoft,
                borderRadius: QestoGeometry.control,
              ),
              child: Icon(
                Icons.account_balance_rounded,
                color: context.qestoColors.primary,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Официальный курс Банка России',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    rate == null
                        ? 'Для $_currency курс не опубликован'
                        : '1 $_currency = ${_rateText(rate.rublesPerUnit)} ₽ · ${_dateText(value.date)}',
                    style: TextStyle(
                      color: context.qestoColors.secondaryText,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            DesktopPill(
              label: 'ЦБ РФ',
              color: context.qestoColors.positive,
              background: Color(0xFFEAF8ED),
            ),
          ],
        );
      },
    ),
  );

  String _dateText(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

  String _rateText(double value) {
    final digits = value >= 10 ? 2 : 4;
    return value.toStringAsFixed(digits).replaceFirst('.', ',');
  }
}

class _ThemeChoice extends StatelessWidget {
  const _ThemeChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    avatar: Icon(
      icon,
      size: 17,
      color: selected
          ? context.qestoColors.primary
          : context.qestoColors.secondaryText,
    ),
    selected: selected,
    showCheckmark: false,
    onSelected: (_) => onTap(),
  );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.description,
  });
  final String title;
  final IconData icon;
  final String description;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: DesktopCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.qestoColors.primarySoft,
              borderRadius: QestoGeometry.control,
            ),
            child: Icon(icon, size: 19, color: context.qestoColors.primary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    color: context.qestoColors.secondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
