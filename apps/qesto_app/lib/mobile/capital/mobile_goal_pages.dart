import 'package:flutter/material.dart';
import '../../core/formatters/qesto_formatters.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../analytics/mobile_financial_widgets.dart';
import 'mobile_capital_common.dart';
import 'mobile_capital_editor.dart';
import 'mobile_investment_pages.dart' show capitalCurrencies;

const goalTypes = {
  'targetAmountDate': 'Сумма к дате',
  'targetAmount': 'Целевая сумма',
  'recurringSaving': 'Регулярные накопления',
  'reserve': 'Резерв',
};
const goalStatuses = {
  'active': 'Активна',
  'funded': 'Накоплена',
  'spending': 'Используется',
  'completed': 'Завершена',
  'paused': 'На паузе',
  'archived': 'В архиве',
};

class MobileGoalsPage extends StatefulWidget {
  const MobileGoalsPage({
    required this.controller,
    this.initiallyHidden = false,
    super.key,
  });
  final BudgetController controller;
  final bool initiallyHidden;
  @override
  State<MobileGoalsPage> createState() => _MobileGoalsPageState();
}

class _MobileGoalsPageState extends State<MobileGoalsPage> {
  bool _archive = false;
  late bool _hidden = widget.initiallyHidden;
  void _open(String id) => capitalPush(
    context,
    '/capital/goal/$id',
    MobileGoalDetail(
      controller: widget.controller,
      goalId: id,
      initiallyHidden: _hidden,
    ),
  );
  @override
  Widget build(BuildContext context) => CapitalPage(
    title: 'Цели',
    controller: widget.controller,
    actions: [
      capitalPrivacy(_hidden, () => setState(() => _hidden = !_hidden)),
    ],
    builder: (context) {
      final c = widget.controller;
      final d = mobileGoals(c);
      final rows = c.savingsGoals
          .where((g) => _archive || g.status != GoalStatus.archived)
          .toList();
      return CapitalRows(
        storageKey: 'mobile-goals-scroll',
        items: [
          () => MobileSection(
            title: 'Накопления на цели',
            child: Column(
              children: [
                MobileValueRow(
                  title: 'Распределено',
                  amount: d.currentAmount,
                  currency: d.baseCurrency,
                  hidden: _hidden,
                  key: const Key('mobile-goal-total'),
                ),
                MobileValueRow(
                  title: 'Целевые суммы',
                  amount: d.targetAmount,
                  currency: d.baseCurrency,
                  hidden: _hidden,
                ),
                MobileValueRow(
                  title: 'План на месяц',
                  amount: d.monthlyPlan,
                  currency: d.baseCurrency,
                  hidden: _hidden,
                ),
                capitalProgress(d.monthlyProgress, hidden: _hidden),
                const Text('Цели не добавляют деньги к капиталу повторно.'),
              ],
            ),
          ),
          () => FilledButton(
            key: const Key('goal-add-button'),
            onPressed: () async {
              final id = await openMobileGoalEditor(context, c);
              if (id != null && mounted) _open(id);
            },
            child: const Text('Создать цель'),
          ),
          () => SwitchListTile(
            title: const Text('Показать архив'),
            value: _archive,
            onChanged: (v) => setState(() => _archive = v),
          ),
          if (rows.isEmpty)
            () =>
                capitalNote('Целей пока нет. Создайте цель через кнопку выше.'),
          for (final g in rows)
            () {
              final p = mobileGoal(c, g);
              return MobileValueRow(
                title: g.title,
                amount: p.currentAmount,
                currency: g.currency,
                hidden: _hidden,
                caption: _hidden
                    ? goalStatuses[p.effectiveStatus.name]
                    : '${goalStatuses[p.effectiveStatus.name]} · цель ${formatMoney(g.targetAmount, g.currency)}${g.targetDate == null ? '' : ' · ${formatDate(g.targetDate!)}'}',
                progress: _hidden ? null : p.progressPercent,
                onTap: () => _open(g.id),
                key: Key('capital-goal-${g.id}'),
              );
            },
          if (d.hasUnconvertedCurrencies)
            () => capitalNote(
              'Некоторые валюты не включены в пересчитанный итог.',
            ),
        ],
      );
    },
  );
}

class MobileGoalDetail extends StatefulWidget {
  const MobileGoalDetail({
    required this.controller,
    required this.goalId,
    this.initiallyHidden = false,
    super.key,
  });
  final BudgetController controller;
  final String goalId;
  final bool initiallyHidden;
  @override
  State<MobileGoalDetail> createState() => _MobileGoalDetailState();
}

class _MobileGoalDetailState extends State<MobileGoalDetail> {
  late bool _hidden = widget.initiallyHidden;
  @override
  Widget build(BuildContext context) => CapitalPage(
    title: 'Цель',
    controller: widget.controller,
    actions: [
      capitalPrivacy(_hidden, () => setState(() => _hidden = !_hidden)),
    ],
    builder: (context) {
      final c = widget.controller;
      final g = c.savingsGoals.where((g) => g.id == widget.goalId).firstOrNull;
      if (g == null) {
        return const Center(child: Text('Цель больше не доступна'));
      }
      final p = mobileGoal(c, g);
      return CapitalRows(
        storageKey: 'goal-${g.id}',
        items: [
          () => MobileSection(
            title: g.title,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MobileMoney(
                  p.currentAmount,
                  currency: g.currency,
                  hidden: _hidden,
                  key: const Key('mobile-goal-current'),
                ),
                MobileValueRow(
                  title: 'Цель',
                  amount: g.targetAmount,
                  currency: g.currency,
                  hidden: _hidden,
                ),
                MobileValueRow(
                  title: 'Осталось',
                  amount: p.remainingAmount,
                  currency: g.currency,
                  hidden: _hidden,
                ),
                capitalProgress(p.progressPercent, hidden: _hidden),
                Text(goalStatuses[p.effectiveStatus.name]!),
                if (g.targetDate != null)
                  Text(
                    'Срок: ${formatDate(g.targetDate!, includeYear: true)}${p.isTargetDateExpired ? ' · просрочен' : ''}',
                  )
                else
                  const Text('Без срока'),
              ],
            ),
          ),
          () => capitalLink(
            'Внести взнос / снять',
            () => openMobileGoalContribution(context, c, g),
            key: const Key('capital-goal-contribution'),
          ),
          () => capitalLink(
            'Распределение средств (${p.allocations.length})',
            () => capitalPush(
              context,
              '/capital/goal/${g.id}/allocations',
              MobileGoalAllocations(
                controller: c,
                goalId: g.id,
                initiallyHidden: _hidden,
              ),
            ),
          ),
          () => capitalLink(
            'Темп и сценарий',
            () => capitalPush(
              context,
              '/capital/goal/${g.id}/pace',
              MobileGoalPace(
                controller: c,
                goalId: g.id,
                initiallyHidden: _hidden,
              ),
            ),
          ),
          () => capitalLink(
            'История и взносы',
            () => capitalPush(
              context,
              '/capital/goal/${g.id}/history',
              CapitalPage(
                title: 'История цели',
                controller: c,
                builder: (_) {
                  final plan = mobileGoal(
                    c,
                    c.savingsGoals.firstWhere((a) => a.id == g.id),
                  );
                  final events =
                      c.goalHistoryEvents
                          .where((e) => e.goalId == g.id)
                          .toList()
                        ..sort((a, b) => b.date.compareTo(a.date));
                  final flows = plan.contributions.toList()
                    ..sort((a, b) => b.date.compareTo(a.date));
                  return CapitalRows(
                    items: [
                      () => MobileCapitalHistory(
                        points: [
                          for (final v in plan.goal.history)
                            (date: v.date, amount: v.amount, confirmed: true),
                        ],
                        currency: g.currency,
                        hidden: _hidden,
                      ),
                      if (plan.allocations.isNotEmpty)
                        () => capitalNote(
                          'График — сохранённая история ручных сумм. Текущая сумма определяется привязанными распределениями.',
                        ),
                      for (final f in flows)
                        () => MobileValueRow(
                          title: f.type == GoalContributionType.contribution
                              ? 'Взнос'
                              : 'Снятие',
                          amount: f.amount,
                          currency: f.currency,
                          hidden: _hidden,
                          caption:
                              '${formatDate(f.date)} · ${f.source.name}${f.comment == null ? '' : ' · ${f.comment}'}',
                        ),
                      for (final e in events)
                        () => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(e.description),
                          subtitle: Text(formatDate(e.date, includeYear: true)),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          () => capitalLink(
            'Редактировать цель',
            () => openMobileGoalEditor(context, c, goal: g),
            key: const Key('capital-goal-edit'),
          ),
          () => capitalNote(
            '${g.category} · ${goalTypes[g.type.name]}${g.comment == null ? '' : '\n${g.comment}'}',
          ),
          if (g.status != GoalStatus.archived)
            () => capitalLink(
              'Архивировать',
              () => capitalPush(
                context,
                '/capital/goal/${g.id}/archive',
                MobileCapitalEditor(
                  controller: c,
                  title: 'Архивировать цель',
                  note:
                      'Цель и её история сохранятся. Баланс счетов не изменится.',
                  fields: const [],
                  initial: const {},
                  saveLabel: 'Архивировать',
                  save: (d, w) async {
                    await w.run([() => c.deleteSavingsGoal(g.id)]);
                    return g.id;
                  },
                ),
              ),
            ),
        ],
      );
    },
  );
}

class MobileGoalPace extends StatefulWidget {
  const MobileGoalPace({
    required this.controller,
    required this.goalId,
    this.initiallyHidden = false,
    super.key,
  });
  final BudgetController controller;
  final String goalId;
  final bool initiallyHidden;
  @override
  State<MobileGoalPace> createState() => _MobileGoalPaceState();
}

class _MobileGoalPaceState extends State<MobileGoalPace> {
  final _amount = TextEditingController();
  GoalSimulation? _simulation;
  String? _error;
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CapitalPage(
    title: 'Темп накопления',
    controller: widget.controller,
    builder: (context) {
      final g = widget.controller.savingsGoals
          .where((g) => g.id == widget.goalId)
          .firstOrNull;
      if (g == null) return const Text('Цель недоступна');
      final p = mobileGoal(widget.controller, g);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MobileSection(
            title: 'Текущий план',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (p.requiredMonthlyContribution != null)
                  MobileValueRow(
                    title: 'Нужно в месяц',
                    amount: p.requiredMonthlyContribution!,
                    currency: g.currency,
                    hidden: widget.initiallyHidden,
                  ),
                if (p.plannedMonthlyContribution != null)
                  MobileValueRow(
                    title: 'Запланировано в месяц',
                    amount: p.plannedMonthlyContribution!,
                    currency: g.currency,
                    hidden: widget.initiallyHidden,
                  ),
                MobileValueRow(
                  title: 'Внесено в этом месяце',
                  amount: p.actualContributionThisMonth,
                  currency: g.currency,
                  hidden: widget.initiallyHidden,
                ),
                if (p.projectedCompletionDate != null)
                  Text(
                    'Прогноз: ${formatDate(p.projectedCompletionDate!, includeYear: true)}',
                  )
                else
                  const Text('Прогноз не рассчитан'),
              ],
            ),
          ),
          const Text('Сценарий не изменяет план и не создаёт взнос.'),
          TextField(
            key: const Key('capital-goal-scenario-amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Взнос в месяц для сценария',
            ),
          ),
          FilledButton(
            onPressed: () {
              try {
                final n = capitalWhole(_amount.text);
                if (n <= 0) throw const FormatException();
                setState(() {
                  _error = null;
                  _simulation = const GoalPlanningService()
                      .simulateMonthlyContribution(
                        plan: p,
                        monthlyContribution: n,
                        asOf: widget.controller.referenceDate,
                      );
                });
              } catch (_) {
                setState(() => _error = 'Укажите целую положительную сумму');
              }
            },
            child: const Text('Рассчитать сценарий'),
          ),
          if (_error != null) Text(_error!),
          if (_simulation != null)
            Text(
              _simulation!.projectedDate == null
                  ? 'Нет даты прогноза'
                  : 'Прогнозная дата: ${formatDate(_simulation!.projectedDate!, includeYear: true)}',
            ),
        ],
      );
    },
  );
}

class MobileGoalAllocations extends StatelessWidget {
  const MobileGoalAllocations({
    required this.controller,
    required this.goalId,
    this.initiallyHidden = false,
    super.key,
  });
  final BudgetController controller;
  final String goalId;
  final bool initiallyHidden;
  @override
  Widget build(BuildContext context) => CapitalPage(
    title: 'Распределение средств',
    controller: controller,
    builder: (context) {
      final g = controller.savingsGoals
          .where((g) => g.id == goalId)
          .firstOrNull;
      if (g == null) return const Text('Цель недоступна');
      final p = mobileGoal(controller, g);
      return CapitalRows(
        items: [
          () => capitalNote(
            'Привязка денег к цели не создаёт перевод и не меняет баланс счёта.',
          ),
          () => FilledButton(
            key: const Key('capital-goal-allocation-add'),
            onPressed: () => openMobileGoalAllocation(context, controller, g),
            child: const Text('Распределить со счёта'),
          ),
          if (p.allocations.isEmpty)
            () => capitalNote('Средства пока не привязаны'),
          for (final a in p.allocations)
            () => MobileValueRow(
              title: allocationTitle(controller, a),
              amount: a.allocatedAmount,
              currency: a.currency,
              hidden: initiallyHidden,
              onTap: () => openMobileGoalAllocation(
                context,
                controller,
                g,
                allocation: a,
              ),
              caption: a.sourceType.name,
            ),
        ],
      );
    },
  );
}

String allocationTitle(BudgetController c, GoalAllocation a) =>
    a.sourceType == GoalAllocationSourceType.account
    ? c.accounts.where((s) => s.id == a.sourceId).firstOrNull?.title ??
          'Счёт недоступен'
    : a.sourceType == GoalAllocationSourceType.investmentAccount
    ? c.investmentAccounts.where((s) => s.id == a.sourceId).firstOrNull?.name ??
          'Инвестиция недоступна'
    : 'Ручной актив';
Future<String?> openMobileGoalAllocation(
  BuildContext context,
  BudgetController c,
  SavingsGoal g, {
  GoalAllocation? allocation,
}) {
  final sources =
      <
        String,
        ({
          String id,
          String title,
          String currency,
          int balance,
          GoalAllocationSourceType type,
        })
      >{
        for (final a in c.accounts.where(
          (a) =>
              {
                AccountType.cash,
                AccountType.bankCard,
                AccountType.savings,
                AccountType.deposit,
              }.contains(a.type) &&
              a.balance > 0,
        ))
          'account:${a.id}': (
            id: a.id,
            title: a.title,
            currency: a.currency,
            balance: a.balance,
            type: GoalAllocationSourceType.account,
          ),
        for (final a in c.investmentAccounts.where(
          (a) => a.isActive && a.currentBalance > 0,
        ))
          'investmentAccount:${a.id}': (
            id: a.id,
            title: a.name,
            currency: a.currency,
            balance: a.currentBalance,
            type: GoalAllocationSourceType.investmentAccount,
          ),
      };
  if (allocation != null &&
      !sources.containsKey(
        '${allocation.sourceType.name}:${allocation.sourceId}',
      )) {
    sources['${allocation.sourceType.name}:${allocation.sourceId}'] = (
      id: allocation.sourceId,
      title: allocationTitle(c, allocation),
      currency: allocation.currency,
      balance: allocation.sourceType == GoalAllocationSourceType.manualAsset
          ? allocation.allocatedAmount
          : 0,
      type: allocation.sourceType,
    );
  }
  if (sources.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Сначала добавьте счёт с положительным балансом'),
      ),
    );
    return Future.value();
  }
  final initial = allocation == null
      ? sources.keys.first
      : '${allocation.sourceType.name}:${allocation.sourceId}';
  final id =
      allocation?.id ??
      'goal-allocation-${DateTime.now().microsecondsSinceEpoch}';
  return capitalPush(
    context,
    '/capital/goal/${g.id}/allocation/edit',
    MobileCapitalEditor(
      controller: c,
      title: 'Распределить деньги',
      note:
          'Сумма указана в валюте выбранного источника. Проверка доступности выполняется существующим GoalPlanningService.',
      fields: [
        CapitalField(
          'source',
          'Источник',
          kind: CapitalInput.choice,
          options: {
            for (final e in sources.entries)
              e.key: '${e.value.title} · ${e.value.currency}',
          },
        ),
        const CapitalField(
          'goal-allocation-amount-field',
          'Распределённая сумма',
          kind: CapitalInput.whole,
          required: true,
        ),
        if (allocation != null)
          const CapitalField(
            'remove',
            'Убрать привязку',
            kind: CapitalInput.toggle,
          ),
      ],
      initial: {
        'source': initial,
        'goal-allocation-amount-field':
            allocation?.allocatedAmount.toString() ?? '',
        'remove': 'false',
      },
      saveKey: 'goal-allocation-save',
      validate: (d) {
        if (capitalBool(d, 'remove')) return null;
        final s = sources[d['source']]!;
        final existing = c.goalAllocations
            .where(
              (a) =>
                  a.goalId == g.id &&
                  a.sourceId == s.id &&
                  a.sourceType == s.type,
            )
            .firstOrNull;
        final available = const GoalPlanningService().allocationAvailability(
          sourceBalance: s.balance,
          sourceId: s.id,
          sourceType: s.type,
          allocations: c.goalAllocations,
          excludingAllocationId: allocation?.id ?? existing?.id,
        );
        return capitalWhole(d['goal-allocation-amount-field']!) >
                available.available
            ? 'Сумма превышает доступный баланс (${formatMoney(available.available, s.currency)})'
            : null;
      },
      save: (d, w) async {
        final s = sources[d['source']]!;
        final existing = c.goalAllocations
            .where(
              (a) =>
                  a.goalId == g.id &&
                  a.sourceId == s.id &&
                  a.sourceType == s.type,
            )
            .firstOrNull;
        await w.run([
          () async {
            if (capitalBool(d, 'remove')) {
              await c.removeGoalAllocation(allocation!.id);
            } else {
              final ok = await c.upsertGoalAllocation(
                GoalAllocation(
                  id: allocation?.id ?? existing?.id ?? id,
                  goalId: g.id,
                  sourceType: s.type,
                  sourceId: s.id,
                  allocatedAmount: capitalWhole(
                    d['goal-allocation-amount-field']!,
                  ),
                  currency: s.currency,
                  updatedAt: DateTime.now(),
                ),
              );
              if (!ok) {
                throw const FormatException('Источник или баланс изменился');
              }
            }
          },
        ]);
        return g.id;
      },
    ),
  );
}

Future<String?> openMobileGoalContribution(
  BuildContext context,
  BudgetController c,
  SavingsGoal g,
) => capitalPush(
  context,
  '/capital/goal/${g.id}/contribution',
  MobileCapitalEditor(
    controller: c,
    title: 'Взнос или снятие',
    note:
        'Ручная запись по цели — не банковская операция. При наличии allocations текущая сумма определяется ими.',
    fields: const [
      CapitalField(
        'goal-contribution-amount',
        'Сумма',
        kind: CapitalInput.positive,
        required: true,
      ),
      CapitalField(
        'type',
        'Действие',
        kind: CapitalInput.choice,
        options: {'contribution': 'Взнос', 'withdrawal': 'Снятие'},
      ),
      CapitalField('date', 'Дата', kind: CapitalInput.date, required: true),
      CapitalField('comment', 'Комментарий'),
    ],
    initial: {'type': 'contribution', 'date': DateTime.now().toIso8601String()},
    save: (d, w) async {
      await w.run([
        () async {
          await c.addGoalContribution(
            goalId: g.id,
            amount: capitalWhole(d['goal-contribution-amount']!),
            type: GoalContributionType.values.byName(d['type']!),
            date: capitalDate(d['date'])!,
            comment: d['comment'],
          );
        },
      ]);
      return g.id;
    },
  ),
);
Future<String?> openMobileGoalEditor(
  BuildContext context,
  BudgetController c, {
  SavingsGoal? goal,
}) {
  final g = goal;
  final before = c.savingsGoals.map((g) => g.id).toSet();
  return capitalPush(
    context,
    '/capital/goal/${g?.id ?? 'create'}/edit',
    MobileCapitalEditor(
      controller: c,
      title: g == null ? 'Новая цель' : 'Редактировать цель',
      saveKey: 'goal-save-button',
      fields: [
        const CapitalField('goal-title-field', 'Название', required: true),
        const CapitalField('category', 'Категория'),
        const CapitalField(
          'type',
          'Тип цели',
          kind: CapitalInput.choice,
          options: goalTypes,
        ),
        const CapitalField(
          'goal-target-field',
          'Целевая сумма',
          kind: CapitalInput.whole,
          required: true,
        ),
        const CapitalField(
          'goal-saved-field',
          'Накоплено вручную',
          kind: CapitalInput.whole,
        ),
        CapitalField(
          'currency',
          'Валюта',
          kind: CapitalInput.choice,
          options: {
            ...capitalCurrencies,
            c.user.defaultCurrency: c.user.defaultCurrency,
            if (g != null) g.currency: g.currency,
          },
        ),
        const CapitalField('date', 'Срок цели', kind: CapitalInput.date),
        const CapitalField(
          'monthly',
          'Желаемый взнос в месяц',
          kind: CapitalInput.whole,
        ),
        const CapitalField(
          'priority',
          'Приоритет',
          kind: CapitalInput.choice,
          options: {'low': 'Низкий', 'medium': 'Средний', 'high': 'Высокий'},
        ),
        const CapitalField(
          'status',
          'Статус',
          kind: CapitalInput.choice,
          options: goalStatuses,
        ),
        const CapitalField(
          'remind',
          'Напоминать откладывать',
          kind: CapitalInput.toggle,
        ),
        CapitalField(
          'reminderAmount',
          'Сумма напоминания',
          kind: CapitalInput.positive,
          required: true,
          visibleWhen: (d) => capitalBool(d, 'remind'),
        ),
        CapitalField(
          'reminderDay',
          'День напоминания',
          kind: CapitalInput.day,
          required: true,
          visibleWhen: (d) => capitalBool(d, 'remind'),
        ),
        CapitalField(
          'cadence',
          'Частота напоминания',
          kind: CapitalInput.choice,
          options: {'monthly': 'Ежемесячно', 'weekly': 'Еженедельно'},
          visibleWhen: (d) => capitalBool(d, 'remind'),
        ),
        const CapitalField('comment', 'Комментарий'),
      ],
      initial: {
        'goal-title-field': g?.title ?? '',
        'category': g?.category ?? 'Другое',
        'type': g?.type.name ?? 'targetAmount',
        'goal-target-field': g?.targetAmount.toString() ?? '',
        'goal-saved-field': '${g?.savedAmount ?? 0}',
        'currency': g?.currency ?? c.user.defaultCurrency,
        'date': g?.targetDate?.toIso8601String() ?? '',
        'monthly': g?.desiredMonthlyContribution?.toString() ?? '',
        'priority': g?.priority.name ?? 'medium',
        'status': g?.status.name ?? 'active',
        'remind': '${g?.reminder?.enabled ?? false}',
        'reminderAmount': g?.reminder?.amount.toString() ?? '',
        'reminderDay': '${g?.reminder?.day ?? 12}',
        'cadence': g?.reminder?.cadence.name ?? 'monthly',
        'comment': g?.comment ?? '',
      },
      validate: (d) {
        final amount = capitalWhole(d['goal-target-field']!);
        if (d['type'] != 'recurringSaving' && amount <= 0) {
          return 'Целевая сумма должна быть больше нуля';
        }
        if (d['type'] == 'recurringSaving' &&
            amount == 0 &&
            (capitalOptionalWhole(d['monthly']) ?? 0) <= 0) {
          return 'Для регулярной цели задайте взнос';
        }
        if (d['type'] == 'targetAmountDate' && capitalDate(d['date']) == null) {
          return 'Укажите срок цели';
        }
        if (capitalBool(d, 'remind') &&
            (capitalOptionalWhole(d['reminderAmount']) ?? 0) <= 0) {
          return 'Укажите сумму напоминания';
        }
        return null;
      },
      save: (d, w) async {
        final monthly = capitalOptionalWhole(d['monthly']);
        final reminder = capitalBool(d, 'remind')
            ? GoalReminder(
                enabled: true,
                amount: capitalWhole(d['reminderAmount']!),
                day: capitalWhole(d['reminderDay']!),
                cadence: GoalReminderCadence.values.byName(d['cadence']!),
              )
            : null;
        await w.run([
          () async {
            if (g == null) {
              await c.addSavingsGoal(
                title: d['goal-title-field']!,
                category: d['category']!,
                targetAmount: capitalWhole(d['goal-target-field']!),
                savedAmount: capitalOptionalWhole(d['goal-saved-field']) ?? 0,
                currency: d['currency'],
                targetDate: capitalDate(d['date']),
                desiredMonthlyContribution: monthly,
                priority: GoalPriority.values.byName(d['priority']!),
                status: GoalStatus.values.byName(d['status']!),
                reminder: reminder,
                type: GoalType.values.byName(d['type']!),
                comment: d['comment'],
              );
            } else {
              await c.updateSavingsGoal(
                g.copyWith(
                  title: d['goal-title-field'],
                  category: d['category'],
                  targetAmount: capitalWhole(d['goal-target-field']!),
                  savedAmount: capitalOptionalWhole(d['goal-saved-field']) ?? 0,
                  currency: d['currency'],
                  targetDate: capitalDate(d['date']),
                  clearTargetDate: capitalDate(d['date']) == null,
                  desiredMonthlyContribution: monthly,
                  clearDesiredMonthlyContribution: monthly == null,
                  priority: GoalPriority.values.byName(d['priority']!),
                  status: GoalStatus.values.byName(d['status']!),
                  isActive: d['status'] == 'active',
                  reminder: reminder,
                  clearReminder: reminder == null,
                  type: GoalType.values.byName(d['type']!),
                  comment: d['comment'],
                  clearComment: d['comment']!.trim().isEmpty,
                ),
              );
            }
          },
        ]);
        return g?.id ??
            c.savingsGoals.where((g) => !before.contains(g.id)).firstOrNull?.id;
      },
    ),
  );
}
