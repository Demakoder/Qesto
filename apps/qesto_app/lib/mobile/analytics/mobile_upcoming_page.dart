import 'package:flutter/material.dart';
import '../../core/formatters/qesto_formatters.dart';
import '../../features/budget/services/upcoming_events_service.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/budget/upcoming_expense_editor.dart';
import 'mobile_financial_widgets.dart';
import '../capital/mobile_capital_common.dart';
import '../capital/mobile_debt_pages.dart';

UpcomingEventsSnapshot buildMobileUpcoming(
  BudgetController controller, {
  DateTime? asOf,
}) => const UpcomingEventsService().build(
  userId: controller.user.id,
  asOf: asOf ?? DateTime.now(),
  streams: controller.synoballState.recurringStreams,
  transactions: controller.synoballState.transactions,
  manualExpenses: controller.upcomingExpenses,
  debts: controller.debts,
);

String mobileEventOrigin(UpcomingPaymentEvent event) => switch (event.origin) {
  UpcomingEventOrigin.manualOneTime => 'Ручной план',
  UpcomingEventOrigin.manualRecurring => 'Ручной регулярный план',
  UpcomingEventOrigin.inferredRecurring => 'Прогноз по истории',
  UpcomingEventOrigin.debt => 'Платёж по долгу',
};

class MobileUpcomingRow extends StatelessWidget {
  const MobileUpcomingRow({
    required this.event,
    this.hidden = false,
    this.onTap,
    super.key,
  });
  final UpcomingPaymentEvent event;
  final bool hidden;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => MobileValueRow(
    title: event.title,
    amount: event.amount,
    currency: event.currency,
    hidden: hidden,
    onTap: onTap,
    caption:
        '${formatDate(event.date)} · ${mobileEventOrigin(event)}${event.isEstimate ? ' · оценка' : ''}',
  );
}

class MobileUpcomingPage extends StatefulWidget {
  const MobileUpcomingPage({
    required this.controller,
    required this.onOpenFilteredTransactions,
    this.initiallyHidden = false,
    this.asOf,
    super.key,
  });
  final BudgetController controller;
  final ValueChanged<List<String>> onOpenFilteredTransactions;
  final bool initiallyHidden;
  final DateTime? asOf;
  @override
  State<MobileUpcomingPage> createState() => _MobileUpcomingPageState();
}

class _MobileUpcomingPageState extends State<MobileUpcomingPage> {
  late bool _hidden = widget.initiallyHidden;
  Future<void> _edit([UpcomingPaymentEvent? event]) async {
    final item = widget.controller.upcomingExpenses
        .where((e) => e.id == event?.sourceId)
        .firstOrNull;
    final date = item?.plannedDate ?? widget.asOf ?? DateTime.now();
    final period =
        widget.controller.periods.where((p) => p.contains(date)).firstOrNull ??
        widget.controller.periods.first;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => UpcomingExpenseEditor(
          controller: widget.controller,
          period: period,
          expense: item,
        ),
      ),
    );
  }

  void _open(UpcomingPaymentEvent event) {
    if (event.origin == UpcomingEventOrigin.debt) {
      capitalPush(
        context,
        '/capital/debt/${event.sourceId}',
        MobileDebtDetail(
          controller: widget.controller,
          debtId: event.sourceId,
          initiallyHidden: _hidden,
        ),
      );
      return;
    }
    if (event.origin == UpcomingEventOrigin.manualOneTime ||
        event.origin == UpcomingEventOrigin.manualRecurring) {
      _edit(event);
      return;
    }
    final stream = widget.controller.synoballState.recurringStreams
        .where((s) => s.id == event.sourceId)
        .firstOrNull;
    final existingIds = widget.controller.transactions.map((t) => t.id).toSet();
    final ids =
        stream?.transactionIds.where(existingIds.contains).toList() ??
        <String>[];
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(event.title)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              MobileUpcomingRow(event: event, hidden: _hidden),
              const Text(
                'Ожидаемое событие — не списание. Оно не создаёт операцию и не меняет баланс.',
              ),
              if (ids.isNotEmpty)
                TextButton(
                  onPressed: () => widget.onOpenFilteredTransactions(ids),
                  child: const Text('Фактические операции серии'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Предстоящие и регулярные'),
      actions: [
        IconButton(
          tooltip: _hidden ? 'Показать суммы' : 'Скрыть суммы',
          onPressed: () => setState(() => _hidden = !_hidden),
          icon: const Icon(Icons.visibility_outlined),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final data = buildMobileUpcoming(
            widget.controller,
            asOf: widget.asOf,
          );
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Планы и прогнозы отдельно от фактических операций.'),
              MobileSection(
                title: 'Регулярные в среднем за месяц',
                child: Column(
                  children: [
                    if (data.monthlyRegularByCurrency.isEmpty)
                      const Text('Регулярных обязательств пока нет'),
                    for (final e in data.monthlyRegularByCurrency.entries)
                      MobileValueRow(
                        title: e.key,
                        amount: e.value,
                        currency: e.key,
                        hidden: _hidden,
                      ),
                    Text('Найдено серий: ${data.detectedStreamCount}'),
                  ],
                ),
              ),
              FilledButton.icon(
                key: const Key('mobile-upcoming-add'),
                onPressed: _edit,
                icon: const Icon(Icons.add),
                label: const Text('Запланировать платёж'),
              ),
              if (data.overdue.isNotEmpty)
                MobileSection(
                  title: 'Дата плана прошла',
                  child: Column(
                    children: [
                      for (final event in data.overdue)
                        MobileUpcomingRow(
                          event: event,
                          hidden: _hidden,
                          onTap: () => _open(event),
                        ),
                    ],
                  ),
                ),
              MobileSection(
                title: 'Ближайшие события',
                child: Column(
                  children: [
                    if (data.upcoming.isEmpty)
                      const Text(
                        'Предстоящих событий нет. План можно добавить вручную.',
                      ),
                    for (final event in data.upcoming)
                      MobileUpcomingRow(
                        event: event,
                        hidden: _hidden,
                        onTap: () => _open(event),
                      ),
                  ],
                ),
              ),
              if (data.tentativeEvents.isNotEmpty)
                MobileSection(
                  title: 'Предварительные серии',
                  child: Column(
                    children: [
                      const Text(
                        'Недостаточно повторений для устойчивого прогноза. Не включены в сумму регулярных.',
                      ),
                      for (final event in data.tentativeEvents)
                        MobileUpcomingRow(
                          event: event,
                          hidden: _hidden,
                          onTap: () => _open(event),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
