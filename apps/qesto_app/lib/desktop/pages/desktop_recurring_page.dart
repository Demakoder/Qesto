import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/services/upcoming_events_service.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/budget/upcoming_expense_editor.dart';
import '../../synoball/core/models.dart';
import '../widgets/desktop_components.dart';

class DesktopRecurringPage extends StatelessWidget {
  const DesktopRecurringPage({
    required this.controller,
    this.onOpenDebt,
    this.asOf,
    super.key,
  });

  static const _service = UpcomingEventsService();
  final BudgetController controller;
  final ValueChanged<String>? onOpenDebt;
  final DateTime? asOf;

  Future<void> _openEditor(BuildContext context, [UpcomingExpense? item]) {
    final date = item?.plannedDate ?? asOf ?? DateTime.now();
    final period = controller.periods
        .where((candidate) => candidate.contains(date))
        .firstOrNull;
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => UpcomingExpenseEditor(
          controller: controller,
          // Opening and cancelling the editor must not create a budget
          // period. A new one is created only if the user saves the plan.
          period: period ?? controller.periods.first,
          expense: item,
        ),
      ),
    );
  }

  void _openEvent(BuildContext context, UpcomingPaymentEvent event) {
    switch (event.origin) {
      case UpcomingEventOrigin.manualOneTime:
      case UpcomingEventOrigin.manualRecurring:
        final item = controller.upcomingExpenses
            .where((expense) => expense.id == event.sourceId)
            .firstOrNull;
        if (item != null) _openEditor(context, item);
      case UpcomingEventOrigin.debt:
        onOpenDebt?.call(event.sourceId);
      case UpcomingEventOrigin.inferredRecurring:
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(event.title),
            content: const Text(
              'Это прогноз по повторяющимся фактическим операциям. '
              'Ожидаемый платёж не создаёт новую операцию и не изменяет баланс.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Понятно'),
              ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final data = _service.build(
        userId: controller.user.id,
        asOf: asOf ?? DateTime.now(),
        streams: controller.synoballState.recurringStreams,
        transactions: controller.synoballState.transactions,
        manualExpenses: controller.upcomingExpenses,
        debts: controller.debts,
      );
      final amounts = data.monthlyRegularByCurrency;
      final regularAmount = amounts.isEmpty
          ? formatMoney(0, controller.user.defaultCurrency)
          : amounts.length == 1
          ? formatMoney(amounts.values.single, amounts.keys.single)
          : 'Несколько валют';
      final next = data.nextEvent;
      return Padding(
        padding: QestoSpacing.workspace(context),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: constraints.maxWidth < 600
                      ? 790
                      : constraints.maxWidth,
                  child: Row(
                    children:
                        [
                              DesktopKpiCard(
                                label: 'Регулярные расходы',
                                value: regularAmount,
                                detail:
                                    'В среднем за месяц · без разовых событий',
                                icon: Icons.event_repeat_outlined,
                                accent: context.qestoColors.purple,
                              ),
                              const SizedBox(width: 14),
                              DesktopKpiCard(
                                label: 'Следующее событие',
                                value: next == null
                                    ? 'Нет событий'
                                    : formatDate(next.date),
                                detail: next?.title ?? 'Ожидаемое, не факт',
                                icon: Icons.calendar_month_outlined,
                              ),
                              const SizedBox(width: 14),
                              DesktopKpiCard(
                                label: 'Потоков найдено',
                                value: '${data.detectedStreamCount}',
                                detail: 'По повторениям фактических операций',
                                icon: Icons.auto_awesome_outlined,
                                accent: context.qestoColors.positive,
                              ),
                            ]
                            .map(
                              (item) => Expanded(
                                child: SizedBox(height: 138, child: item),
                              ),
                            )
                            .toList(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: DesktopCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final addButton = OutlinedButton.icon(
                            key: const Key('recurring-add-payment'),
                            onPressed: () => _openEditor(context),
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: const Text('Добавить платёж'),
                          );
                          const header = DesktopSectionHeader(
                            title: 'Предстоящие и регулярные',
                            subtitle:
                                'Прогнозы и планы не считаются фактическими операциями',
                          );
                          if (constraints.maxWidth < 600) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                header,
                                const SizedBox(height: 10),
                                addButton,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              const Expanded(child: header),
                              addButton,
                            ],
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child:
                          data.upcoming.isEmpty &&
                              data.overdue.isEmpty &&
                              data.tentativeStreams.isEmpty &&
                              data.tentativeEvents.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.event_available_outlined,
                                    size: 42,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Предстоящих платежей пока нет',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Qesto найдёт регулярные списания при достаточной истории. '
                                    'Будущий платёж можно добавить вручную.',
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: () => _openEditor(context),
                                    icon: const Icon(Icons.add_rounded),
                                    label: const Text('Добавить платёж'),
                                  ),
                                ],
                              ),
                            )
                          : ListView(
                              children: [
                                for (final event in data.upcoming)
                                  _EventRow(
                                    event: event,
                                    onTap: () => _openEvent(context, event),
                                  ),
                                if (data.overdue.isNotEmpty) ...[
                                  const _GroupLabel('Прошедшие планы'),
                                  for (final event in data.overdue)
                                    _EventRow(
                                      event: event,
                                      onTap: () => _openEvent(context, event),
                                    ),
                                ],
                                if (data.tentativeStreams.isNotEmpty ||
                                    data.tentativeEvents.isNotEmpty) ...[
                                  const _GroupLabel('Возможные повторы'),
                                  for (final stream in data.tentativeStreams)
                                    _TentativeRow(stream: stream),
                                  for (final event in data.tentativeEvents)
                                    ListTile(
                                      title: Text(event.title),
                                      subtitle: const Text(
                                        'Предварительная оценка · требуется больше истории',
                                      ),
                                      trailing: Text(
                                        formatMoney(
                                          event.amount,
                                          event.currency,
                                        ),
                                      ),
                                    ),
                                ],
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
    },
  );
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
  );
}

class _TentativeRow extends StatelessWidget {
  const _TentativeRow({required this.stream});
  final RecurringStream stream;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(
      Icons.help_outline_rounded,
      color: context.qestoColors.warning,
    ),
    title: Text(stream.title),
    subtitle: const Text('Пока недостаточно истории для уверенного прогноза'),
    trailing: Text(
      formatMoney(
        stream.typicalAmount.minorUnits ~/ 100,
        stream.typicalAmount.currency,
      ),
    ),
  );
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.onTap});
  final UpcomingPaymentEvent event;
  final VoidCallback onTap;

  String get _sourceLabel => switch (event.origin) {
    UpcomingEventOrigin.inferredRecurring => 'Регулярный · прогноз Qesto',
    UpcomingEventOrigin.manualOneTime => 'Запланировано вами',
    UpcomingEventOrigin.manualRecurring => 'Регулярный · добавлено вами',
    UpcomingEventOrigin.debt => 'Из долгов',
  };

  IconData get _icon => switch (event.origin) {
    UpcomingEventOrigin.inferredRecurring => Icons.auto_awesome_outlined,
    UpcomingEventOrigin.manualOneTime => Icons.edit_calendar_outlined,
    UpcomingEventOrigin.manualRecurring => Icons.event_repeat_outlined,
    UpcomingEventOrigin.debt => Icons.account_balance_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final status = event.isOverdue
        ? 'Просрочено · $_sourceLabel'
        : _sourceLabel;
    final amount =
        '${event.isEstimate ? '≈ ' : ''}'
        '${formatMoney(event.amount, event.currency)}';
    return Column(
      children: [
        ListTile(
          key: Key('upcoming-event-${event.id}'),
          onTap: onTap,
          leading: Icon(_icon, color: context.qestoColors.primary),
          title: Text(event.title),
          subtitle: Text(
            '${formatDate(event.date, includeYear: true)} · $status',
          ),
          trailing: Text(
            amount,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const Divider(height: 1, indent: 18, endIndent: 18),
      ],
    );
  }
}
