import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../synoball/core/models.dart';
import '../widgets/desktop_components.dart';

class DesktopRecurringPage extends StatelessWidget {
  const DesktopRecurringPage({required this.controller, super.key});
  final BudgetController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final streams = controller.synoballState.recurringStreams.toList()
          ..sort((a, b) => a.nextExpectedAt.compareTo(b.nextExpectedAt));
        final upcoming =
            controller.upcomingExpenses
                .where((item) => !item.isCancelled)
                .toList()
              ..sort((a, b) => a.plannedDate.compareTo(b.plannedDate));
        return Padding(
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 28),
          child: Column(
            children: [
              Row(
                children:
                    [
                          DesktopKpiCard(
                            label: 'Регулярные обязательства',
                            value: formatMoney(
                              controller
                                      .financialState
                                      .mandatoryExpenses
                                      .minorUnits ~/
                                  100,
                              controller
                                  .financialState
                                  .mandatoryExpenses
                                  .currency,
                            ),
                            detail: 'Оценка Synoball',
                            icon: Icons.event_repeat_outlined,
                            accent: QestoColors.purple,
                          ),
                          const SizedBox(width: 14),
                          DesktopKpiCard(
                            label: 'Следующее событие',
                            value: _nextDate(streams, upcoming),
                            detail: 'Ожидаемое, не факт',
                            icon: Icons.calendar_month_outlined,
                          ),
                          const SizedBox(width: 14),
                          DesktopKpiCard(
                            label: 'Потоков найдено',
                            value: '${streams.length}',
                            detail: 'По повторениям операций',
                            icon: Icons.auto_awesome_outlined,
                            accent: QestoColors.positive,
                          ),
                        ]
                        .map(
                          (item) => Expanded(
                            child: SizedBox(height: 138, child: item),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: DesktopCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(18),
                        child: DesktopSectionHeader(
                          title: 'Предстоящие и регулярные',
                          subtitle:
                              'Expected, planned и inferred события не смешиваются с observed транзакциями',
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: streams.isEmpty && upcoming.isEmpty
                            ? const DesktopEmptyState(
                                title: 'Регулярные платежи ещё не найдены',
                                message:
                                    'Synoball определит их по истории повторяющихся операций.',
                                icon: Icons.event_repeat_outlined,
                              )
                            : ListView(
                                children: [
                                  for (final item in upcoming)
                                    _UpcomingRow(item: item),
                                  for (final stream in streams)
                                    _StreamRow(stream: stream),
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

  String _nextDate(
    List<RecurringStream> streams,
    List<UpcomingExpense> upcoming,
  ) {
    final dates = <DateTime>[
      ...streams.map((item) => item.nextExpectedAt),
      ...upcoming.map((item) => item.plannedDate),
    ]..sort();
    return dates.isEmpty ? 'Нет событий' : formatDate(dates.first);
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({required this.item});
  final UpcomingExpense item;
  @override
  Widget build(BuildContext context) => _RecurringRow(
    date: item.plannedDate,
    title: item.title,
    amount: item.amount,
    currency: item.currency,
    status: item.source == UpcomingExpenseSource.manual
        ? 'Запланировано'
        : 'Ожидается',
    icon: item.source == UpcomingExpenseSource.manual
        ? Icons.edit_calendar_outlined
        : Icons.schedule_rounded,
    color: item.source == UpcomingExpenseSource.manual
        ? QestoColors.primary
        : QestoColors.purple,
  );
}

class _StreamRow extends StatelessWidget {
  const _StreamRow({required this.stream});
  final RecurringStream stream;
  @override
  Widget build(BuildContext context) => _RecurringRow(
    date: stream.nextExpectedAt,
    title: stream.title,
    amount: stream.typicalAmount.minorUnits ~/ 100,
    currency: stream.typicalAmount.currency,
    status: '≈ прогноз · ${(stream.confidence * 100).round()}%',
    icon: Icons.auto_awesome_outlined,
    color: QestoColors.warning,
  );
}

class _RecurringRow extends StatelessWidget {
  const _RecurringRow({
    required this.date,
    required this.title,
    required this.amount,
    required this.currency,
    required this.status,
    required this.icon,
    required this.color,
  });
  final DateTime date;
  final String title;
  final int amount;
  final String currency;
  final String status;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 62,
        child: Row(
          children: [
            const SizedBox(width: 18),
            SizedBox(
              width: 72,
              child: Text(
                formatDate(date),
                style: const TextStyle(
                  color: QestoColors.secondaryText,
                  fontSize: 11,
                ),
              ),
            ),
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            DesktopPill(label: status, color: color),
            const SizedBox(width: 18),
            SizedBox(
              width: 120,
              child: Text(
                formatMoney(-amount, currency),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 20),
          ],
        ),
      ),
      const Divider(height: 1, indent: 18, endIndent: 18),
    ],
  );
}
