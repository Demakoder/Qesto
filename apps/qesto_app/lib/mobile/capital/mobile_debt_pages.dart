import 'package:flutter/material.dart';
import '../../core/formatters/qesto_formatters.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../analytics/mobile_financial_widgets.dart';
import '../analytics/mobile_statistics_controls.dart';
import 'mobile_capital_common.dart';
import 'mobile_capital_editor.dart';
import 'mobile_investment_pages.dart' show capitalCurrencies;

const debtTypes = {
  'mortgage': 'Ипотека',
  'personalLoan': 'Потребительский кредит',
  'creditCard': 'Кредитная карта',
  'autoLoan': 'Автокредит',
  'installment': 'Рассрочка',
  'other': 'Другой',
};
const debtStatuses = {
  'active': 'Активный',
  'paidOff': 'Погашен',
  'closed': 'Закрыт',
  'archived': 'В архиве',
};

class MobileDebtsPage extends StatefulWidget {
  const MobileDebtsPage({
    required this.controller,
    this.initiallyHidden = false,
    super.key,
  });
  final BudgetController controller;
  final bool initiallyHidden;
  @override
  State<MobileDebtsPage> createState() => _MobileDebtsPageState();
}

class _MobileDebtsPageState extends State<MobileDebtsPage> {
  bool _all = false;
  late bool _hidden = widget.initiallyHidden;
  DebtAnalyticsPeriod _period = DebtAnalyticsPeriod.threeMonths;
  void _open(String id) => capitalPush(
    context,
    '/capital/debt/$id',
    MobileDebtDetail(
      controller: widget.controller,
      debtId: id,
      initiallyHidden: _hidden,
    ),
  );
  @override
  Widget build(BuildContext context) => CapitalPage(
    title: 'Долги',
    controller: widget.controller,
    actions: [
      capitalPrivacy(_hidden, () => setState(() => _hidden = !_hidden)),
    ],
    builder: (context) {
      final c = widget.controller;
      final d = mobileDebts(c, _period);
      final rows = c.debts.where((d) => _all || d.isOpen).toList();
      return CapitalRows(
        storageKey: 'mobile-debts-scroll',
        items: [
          () => TextButton(
            onPressed: () async {
              final v = await mobileChoice(context, 'Период долгов', {
                for (final p in DebtAnalyticsPeriod.values) p.name: p.label,
              }, _period.name);
              if (v != null && mounted) {
                setState(() => _period = DebtAnalyticsPeriod.values.byName(v));
              }
            },
            child: Text('Период: ${_period.label}'),
          ),
          () => MobileSection(
            title: 'Обязательства',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MobileMoney(
                  d.totalDebt,
                  currency: d.baseCurrency,
                  hidden: _hidden,
                  key: const Key('mobile-debt-total'),
                ),
                MobileValueRow(
                  title: 'Платежи в месяц',
                  amount: d.monthlyDebtPayments,
                  currency: d.baseCurrency,
                  hidden: _hidden,
                ),
                if (!d.hasCompletePaymentData)
                  const Text('Не у всех долгов известны платежи'),
                MobileCapitalHistory(
                  points: [
                    for (final p in d.trend)
                      (
                        date: p.date,
                        amount: p.totalBalance,
                        confirmed: p.isConfirmed,
                      ),
                  ],
                  currency: d.baseCurrency,
                  hidden: _hidden,
                ),
              ],
            ),
          ),
          () => FilledButton(
            key: const Key('debt-add-button'),
            onPressed: () async {
              final id = await openMobileDebtEditor(context, c);
              if (id != null && mounted) _open(id);
            },
            child: const Text('Добавить долг'),
          ),
          () => SwitchListTile(
            title: const Text('Закрытые и архивные'),
            value: _all,
            onChanged: (v) => setState(() => _all = v),
          ),
          if (rows.isEmpty)
            () => capitalNote('Активных долгов нет. Это нормальное состояние.'),
          for (final a in rows)
            () => MobileValueRow(
              title: a.name,
              amount: a.currentBalance,
              currency: a.currency,
              hidden: _hidden,
              caption:
                  '${debtTypes[a.type.name]} · ${debtStatuses[a.status.name]}',
              onTap: () => _open(a.id),
              key: Key('capital-debt-${a.id}'),
            ),
          if (d.hasUnconvertedCurrencies)
            () => capitalNote(
              'Некоторые валюты не включены в пересчитанный итог.',
            ),
        ],
      );
    },
  );
}

class MobileDebtDetail extends StatefulWidget {
  const MobileDebtDetail({
    required this.controller,
    required this.debtId,
    this.initiallyHidden = false,
    super.key,
  });
  final BudgetController controller;
  final String debtId;
  final bool initiallyHidden;
  @override
  State<MobileDebtDetail> createState() => _MobileDebtDetailState();
}

class _MobileDebtDetailState extends State<MobileDebtDetail> {
  late bool _hidden = widget.initiallyHidden;
  @override
  Widget build(BuildContext context) => CapitalPage(
    title: 'Долг',
    controller: widget.controller,
    actions: [
      capitalPrivacy(_hidden, () => setState(() => _hidden = !_hidden)),
    ],
    builder: (context) {
      final c = widget.controller;
      final a = c.debts.where((a) => a.id == widget.debtId).firstOrNull;
      if (a == null) {
        return const Center(child: Text('Долг больше не доступен'));
      }
      final projection = !a.isOpen
          ? null
          : const DebtAnalyticsService().projectedPayoffDate(
              a,
              asOf: c.referenceDate,
            );
      final upcoming = const DebtAnalyticsService().getNextPayments([
        a,
      ], asOf: c.referenceDate);
      final history =
          c.debtBalanceSnapshots.where((s) => s.debtId == a.id).toList()
            ..sort((x, y) => x.date.compareTo(y.date));
      final payments = c.debtPayments.where((p) => p.debtId == a.id).toList()
        ..sort((x, y) => y.date.compareTo(x.date));
      return CapitalRows(
        storageKey: 'debt-${a.id}',
        items: [
          () => MobileSection(
            title: a.name,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MobileMoney(
                  a.currentBalance,
                  currency: a.currency,
                  hidden: _hidden,
                  key: const Key('mobile-debt-balance'),
                ),
                Text(
                  '${debtStatuses[a.status.name]} · ${debtTypes[a.type.name]}',
                ),
                Text(
                  'Данные: ${capitalStatus(a.dataQuality.name)} · ${formatDate(a.updatedAt, includeYear: true)}',
                ),
              ],
            ),
          ),
          () => MobileSection(
            title: 'Условия',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(a.institutionName ?? 'Кредитор не указан'),
                if (a.interestRate != null)
                  Text(
                    _hidden ? 'Ставка скрыта' : 'Ставка: ${a.interestRate}%',
                  ),
                if (a.originalPrincipal != null)
                  MobileValueRow(
                    title: 'Начальная сумма',
                    amount: a.originalPrincipal!,
                    currency: a.currency,
                    hidden: _hidden,
                  ),
                if (a.monthlyPayment != null)
                  MobileValueRow(
                    title: 'Платёж в месяц',
                    amount: a.monthlyPayment!,
                    currency: a.currency,
                    hidden: _hidden,
                  ),
                if (a.paymentDay != null) Text('День платежа: ${a.paymentDay}'),
                Text('Схема: ${capitalStatus(a.paymentType.name)}'),
                if (a.creditCardDetails case final card?) ...[
                  if (card.creditLimit != null)
                    MobileValueRow(
                      title: 'Кредитный лимит',
                      amount: card.creditLimit!,
                      currency: a.currency,
                      hidden: _hidden,
                    ),
                  if (card.minimumPayment != null)
                    MobileValueRow(
                      title: 'Минимальный платёж',
                      amount: card.minimumPayment!,
                      currency: a.currency,
                      hidden: _hidden,
                    ),
                  if (card.gracePaymentAmount != null)
                    MobileValueRow(
                      title: 'Платёж для льготного периода',
                      amount: card.gracePaymentAmount!,
                      currency: a.currency,
                      hidden: _hidden,
                    ),
                  if (card.graceDeadline != null)
                    Text(
                      'Льготный срок: ${formatDate(card.graceDeadline!, includeYear: true)}',
                    ),
                ],
                if (a.startDate != null)
                  Text(
                    'Начало: ${formatDate(a.startDate!, includeYear: true)}',
                  ),
                if (a.plannedEndDate != null)
                  Text(
                    'Плановый срок: ${formatDate(a.plannedEndDate!, includeYear: true)}',
                  ),
              ],
            ),
          ),
          () => MobileSection(
            title: 'Прогноз · не совершённый платёж',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (projection == null)
                  const Text('Не хватает условий для расчёта погашения')
                else ...[
                  Text(
                    'Расчётная дата: ${formatDate(projection.payoffDate, includeYear: true)}',
                  ),
                  if (projection.totalInterest != null)
                    MobileValueRow(
                      title: 'Оценка процентов',
                      amount: projection.totalInterest!,
                      currency: a.currency,
                      hidden: _hidden,
                    ),
                ],
                capitalLink(
                  'Рассчитать сценарий',
                  () => capitalPush(
                    context,
                    '/capital/debt/${a.id}/scenario',
                    MobileDebtScenario(
                      controller: c,
                      debtId: a.id,
                      initiallyHidden: _hidden,
                    ),
                  ),
                  key: const Key('capital-debt-scenario'),
                ),
              ],
            ),
          ),
          () => capitalLink(
            'История остатков',
            () => capitalPush(
              context,
              '/capital/debt/${a.id}/history',
              CapitalPage(
                title: 'История долга',
                controller: c,
                builder: (_) => CapitalRows(
                  items: [
                    () => MobileCapitalHistory(
                      points: [
                        for (final s in history)
                          (
                            date: s.date,
                            amount: s.totalBalance,
                            confirmed: s.confidence >= .8,
                          ),
                      ],
                      currency: a.currency,
                      hidden: _hidden,
                    ),
                  ],
                ),
              ),
            ),
          ),
          () => capitalLink(
            'Записанные платежи (${payments.length})',
            () => capitalPush(
              context,
              '/capital/debt/${a.id}/payments',
              CapitalPage(
                title: 'Фактические платежи',
                controller: c,
                builder: (_) => CapitalRows(
                  items: [
                    () => capitalNote(
                      'Только уже записанные платежи. Новый payment CRUD не добавлен.',
                    ),
                    for (final p in payments)
                      () => MobileValueRow(
                        title: formatDate(p.date, includeYear: true),
                        amount: p.amount,
                        currency: p.currency,
                        hidden: _hidden,
                        caption: p.source.name,
                      ),
                  ],
                ),
              ),
            ),
          ),
          for (final p in upcoming)
            () => MobileValueRow(
              title: 'Ожидаемый платёж',
              amount: p.amount,
              currency: p.currency,
              hidden: _hidden,
              caption:
                  '${formatDate(p.date, includeYear: true)} · прогноз, не факт',
            ),
          () => capitalLink(
            'Редактировать условия',
            () => openMobileDebtEditor(context, c, debt: a),
            key: const Key('capital-debt-edit'),
          ),
          if (a.status != DebtStatus.archived)
            () => capitalLink(
              'Архивировать',
              () => capitalPush(
                context,
                '/capital/debt/${a.id}/archive',
                MobileCapitalEditor(
                  controller: c,
                  title: 'Архивировать долг',
                  note:
                      'Долг исключится из активных обязательств. История останется. Это не запись фактического погашения.',
                  fields: const [],
                  initial: const {},
                  saveLabel: 'Архивировать',
                  save: (d, w) async {
                    await w.run([() => c.archiveDebt(a.id)]);
                    return a.id;
                  },
                ),
              ),
            ),
        ],
      );
    },
  );
}

class MobileDebtScenario extends StatefulWidget {
  const MobileDebtScenario({
    required this.controller,
    required this.debtId,
    this.initiallyHidden = false,
    super.key,
  });
  final BudgetController controller;
  final String debtId;
  final bool initiallyHidden;
  @override
  State<MobileDebtScenario> createState() => _MobileDebtScenarioState();
}

class _MobileDebtScenarioState extends State<MobileDebtScenario> {
  final _amount = TextEditingController();
  bool _once = false;
  String? _error;
  List<DebtPrepaymentSimulation> _results = [];
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.controller.debts
        .where((a) => a.id == widget.debtId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Сценарий погашения')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Только расчёт. Ни платёж, ни банковская операция не создаются.',
            ),
            SwitchListTile(
              title: const Text('Разовый досрочный платёж'),
              value: _once,
              onChanged: (v) => setState(() {
                _once = v;
                _results = [];
              }),
            ),
            TextField(
              key: const Key('capital-scenario-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _once ? 'Разовая сумма' : 'Дополнительно в месяц',
              ),
            ),
            FilledButton(
              key: const Key('capital-scenario-calculate'),
              onPressed: a == null
                  ? null
                  : () {
                      try {
                        final n = capitalWhole(_amount.text);
                        if (n <= 0) throw const FormatException();
                        final service = const DebtAnalyticsService();
                        final once = _once
                            ? service.simulateOneTimePrepayment(
                                a,
                                asOf: widget.controller.referenceDate,
                                amount: n,
                              )
                            : null;
                        final monthly = _once
                            ? null
                            : service.simulateExtraMonthlyPayment(
                                a,
                                asOf: widget.controller.referenceDate,
                                extraMonthlyPayment: n,
                              );
                        setState(() {
                          _results = once != null
                              ? [once.reduceTerm, once.reducePayment]
                              : monthly == null
                              ? []
                              : [monthly];
                          _error = _results.isEmpty
                              ? 'Недостаточно условий для сценария'
                              : null;
                        });
                      } catch (_) {
                        setState(
                          () => _error =
                              'Укажите целую положительную сумму без округления',
                        );
                      }
                    },
              child: const Text('Рассчитать'),
            ),
            if (_error != null) Text(_error!),
            for (var i = 0; i < _results.length; i++)
              MobileSection(
                title: _once
                    ? (i == 0 ? 'Сократить срок' : 'Сократить платёж')
                    : 'Ежемесячный сценарий',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Прогнозная дата ${formatDate(_results[i].payoffDate, includeYear: true)}',
                    ),
                    Text('Месяцев: ${_results[i].months}'),
                    if (_results[i].monthsSaved != null)
                      Text('Сокращение срока: ${_results[i].monthsSaved} мес.'),
                    MobileValueRow(
                      title: 'Расчётный платёж',
                      amount: _results[i].monthlyPayment,
                      currency: a!.currency,
                      hidden: widget.initiallyHidden,
                    ),
                    if (_results[i].interestSaved != null)
                      MobileValueRow(
                        title: 'Оценка экономии процентов',
                        amount: _results[i].interestSaved!,
                        currency: a.currency,
                        hidden: widget.initiallyHidden,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> openMobileDebtEditor(
  BuildContext context,
  BudgetController c, {
  DebtAccount? debt,
}) {
  final a = debt;
  final before = c.debts.map((a) => a.id).toSet();
  return capitalPush(
    context,
    '/capital/debt/${a?.id ?? 'create'}/edit',
    MobileCapitalEditor(
      controller: c,
      title: a == null ? 'Добавить долг' : 'Редактировать долг',
      saveKey: 'debt-save-button',
      fields: [
        const CapitalField('debt-name-field', 'Название', required: true),
        const CapitalField('creditor', 'Кредитор'),
        const CapitalField(
          'debt-balance-field',
          'Остаток долга',
          kind: CapitalInput.whole,
          required: true,
        ),
        CapitalField(
          'currency',
          'Валюта',
          kind: CapitalInput.choice,
          options: {
            ...capitalCurrencies,
            c.user.defaultCurrency: c.user.defaultCurrency,
            if (a != null) a.currency: a.currency,
          },
        ),
        const CapitalField(
          'type',
          'Тип',
          kind: CapitalInput.choice,
          options: debtTypes,
        ),
        if (a != null)
          const CapitalField(
            'status',
            'Статус',
            kind: CapitalInput.choice,
            options: debtStatuses,
          ),
        const CapitalField(
          'original',
          'Начальная сумма',
          kind: CapitalInput.whole,
        ),
        const CapitalField('rate', 'Годовая ставка %', kind: CapitalInput.rate),
        const CapitalField(
          'payment',
          'Платёж в месяц',
          kind: CapitalInput.whole,
        ),
        const CapitalField('day', 'День платежа', kind: CapitalInput.day),
        const CapitalField(
          'paymentType',
          'Схема платежей',
          kind: CapitalInput.choice,
          options: {
            'annuity': 'Аннуитет',
            'differentiated': 'Дифференцированная',
            'unknown': 'Неизвестна',
          },
        ),
        const CapitalField('next', 'Следующий платёж', kind: CapitalInput.date),
        const CapitalField('start', 'Дата начала', kind: CapitalInput.date),
        const CapitalField(
          'end',
          'Плановое окончание',
          kind: CapitalInput.date,
        ),
        CapitalField(
          'limit',
          'Лимит кредитной карты',
          kind: CapitalInput.whole,
          visibleWhen: (d) => d['type'] == 'creditCard',
        ),
        CapitalField(
          'minimum',
          'Минимальный платёж карты',
          kind: CapitalInput.whole,
          visibleWhen: (d) => d['type'] == 'creditCard',
        ),
        CapitalField(
          'grace',
          'Платёж для льготного периода',
          kind: CapitalInput.whole,
          visibleWhen: (d) => d['type'] == 'creditCard',
        ),
        CapitalField(
          'graceDate',
          'Льготный срок',
          kind: CapitalInput.date,
          visibleWhen: (d) => d['type'] == 'creditCard',
        ),
      ],
      initial: {
        'debt-name-field': a?.name ?? '',
        'creditor': a?.institutionName ?? '',
        'debt-balance-field': a?.currentBalance.toString() ?? '',
        'currency': a?.currency ?? c.user.defaultCurrency,
        'type': a?.type.name ?? 'personalLoan',
        'status': a?.status.name ?? 'active',
        'original': a?.originalPrincipal?.toString() ?? '',
        'rate': a?.interestRate?.toString() ?? '',
        'payment': a?.monthlyPayment?.toString() ?? '',
        'day': a?.paymentDay?.toString() ?? '',
        'paymentType': a?.paymentType.name ?? 'unknown',
        'next': a?.nextPaymentDate?.toIso8601String() ?? '',
        'start': a?.startDate?.toIso8601String() ?? '',
        'end': a?.plannedEndDate?.toIso8601String() ?? '',
        'limit': a?.creditCardDetails?.creditLimit?.toString() ?? '',
        'minimum': a?.creditCardDetails?.minimumPayment?.toString() ?? '',
        'grace': a?.creditCardDetails?.gracePaymentAmount?.toString() ?? '',
        'graceDate':
            a?.creditCardDetails?.graceDeadline?.toIso8601String() ?? '',
      },
      save: (d, w) async {
        final type = DebtType.values.byName(d['type']!);
        final rate = double.tryParse(d['rate']!.replaceAll(',', '.'));
        final card = type == DebtType.creditCard
            ? CreditCardDebtDetails(
                creditLimit: capitalOptionalWhole(d['limit']),
                minimumPayment: capitalOptionalWhole(d['minimum']),
                gracePaymentAmount: capitalOptionalWhole(d['grace']),
                graceDeadline: capitalDate(d['graceDate']),
                gracePeriodEnd: a?.creditCardDetails?.gracePeriodEnd,
                interestRateAfterGrace:
                    a?.creditCardDetails?.interestRateAfterGrace ?? rate,
              )
            : null;
        await w.run([
          () async {
            if (a == null) {
              await c.addDebt(
                name: d['debt-name-field']!,
                currentBalance: capitalWhole(d['debt-balance-field']!),
                type: type,
                currency: d['currency'],
                institutionName: d['creditor'],
                originalPrincipal: capitalOptionalWhole(d['original']),
                interestRate: rate,
                monthlyPayment: capitalOptionalWhole(d['payment']),
                paymentDay: capitalOptionalWhole(d['day']),
                nextPaymentDate: capitalDate(d['next']),
                startDate: capitalDate(d['start']),
                plannedEndDate: capitalDate(d['end']),
                paymentType: DebtPaymentType.values.byName(d['paymentType']!),
                creditCardDetails: card,
              );
            } else {
              await c.updateDebt(
                DebtAccount(
                  id: a.id,
                  userId: a.userId,
                  name: d['debt-name-field']!,
                  type: type,
                  currency: d['currency']!,
                  currentBalance: capitalWhole(d['debt-balance-field']!),
                  status: DebtStatus.values.byName(d['status']!),
                  source: a.source,
                  dataQuality: a.dataQuality,
                  confidence: a.confidence,
                  createdAt: a.createdAt,
                  updatedAt: a.updatedAt,
                  institutionId: a.institutionId,
                  institutionName: d['creditor']!.trim().isEmpty
                      ? null
                      : d['creditor'],
                  linkedAccountId: a.linkedAccountId,
                  originalPrincipal: capitalOptionalWhole(d['original']),
                  currentPrincipal: capitalWhole(d['debt-balance-field']!),
                  accruedInterest: a.accruedInterest,
                  interestRate: rate,
                  effectiveRate: a.effectiveRate,
                  monthlyPayment: capitalOptionalWhole(d['payment']),
                  paymentDay: capitalOptionalWhole(d['day']),
                  nextPaymentDate: capitalDate(d['next']),
                  startDate: capitalDate(d['start']),
                  plannedEndDate: capitalDate(d['end']),
                  paymentType: DebtPaymentType.values.byName(d['paymentType']!),
                  creditCardDetails: card,
                ),
              );
            }
          },
        ]);
        return a?.id ??
            c.debts.where((a) => !before.contains(a.id)).firstOrNull?.id;
      },
    ),
  );
}
