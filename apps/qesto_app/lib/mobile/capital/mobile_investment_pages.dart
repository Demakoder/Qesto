import 'package:flutter/material.dart';
import '../../core/formatters/qesto_formatters.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../analytics/mobile_financial_widgets.dart';
import '../analytics/mobile_statistics_controls.dart';
import 'mobile_capital_common.dart';
import 'mobile_capital_editor.dart';

const investmentTypes = {
  'brokerage': 'Брокерский',
  'iis': 'ИИС',
  'pension': 'Пенсионный',
  'crypto': 'Криптоактивы',
  'other': 'Другой',
};
const investmentStatuses = {
  'active': 'Активный',
  'closed': 'Закрыт',
  'archived': 'В архиве',
};
const capitalCurrencies = {
  'RUB': 'RUB',
  'USD': 'USD',
  'EUR': 'EUR',
  'CNY': 'CNY',
};

class MobileInvestmentsPage extends StatefulWidget {
  const MobileInvestmentsPage({
    required this.controller,
    this.initiallyHidden = false,
    super.key,
  });
  final BudgetController controller;
  final bool initiallyHidden;
  @override
  State<MobileInvestmentsPage> createState() => _MobileInvestmentsPageState();
}

class _MobileInvestmentsPageState extends State<MobileInvestmentsPage> {
  late bool _hidden = widget.initiallyHidden;
  bool _archive = false;
  InvestmentPeriod _period = InvestmentPeriod.threeMonths;
  void _open(String id) => capitalPush(
    context,
    '/capital/investment/$id',
    MobileInvestmentDetail(
      controller: widget.controller,
      investmentId: id,
      initiallyHidden: _hidden,
      period: _period,
    ),
  );
  @override
  Widget build(BuildContext context) => CapitalPage(
    title: 'Инвестиции',
    controller: widget.controller,
    actions: [
      capitalPrivacy(_hidden, () => setState(() => _hidden = !_hidden)),
    ],
    builder: (context) {
      final c = widget.controller;
      final d = mobileInvestments(c, _period);
      final rows = c.investmentAccounts
          .where(
            (a) => _archive || a.status != InvestmentAccountStatus.archived,
          )
          .toList();
      return CapitalRows(
        storageKey: 'mobile-investments-scroll',
        items: [
          () => TextButton(
            onPressed: () async {
              final v = await mobileChoice(context, 'Период инвестиций', {
                for (final p in InvestmentPeriod.values) p.name: p.label,
              }, _period.name);
              if (v != null && mounted) {
                setState(() => _period = InvestmentPeriod.values.byName(v));
              }
            },
            child: Text('Период: ${_period.label}'),
          ),
          () => MobileSection(
            title: 'Инвестиционный капитал',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MobileMoney(
                  d.totalBalance,
                  currency: d.baseCurrency,
                  hidden: _hidden,
                  key: const Key('mobile-investment-total'),
                ),
                if (d.change != null && !_hidden)
                  Text(
                    'Изменение ${formatMoney(d.change!, d.baseCurrency, showSign: true)}',
                  ),
                MobileCapitalHistory(
                  points: [
                    for (final p in d.history)
                      (date: p.date, amount: p.balance, confirmed: false),
                  ],
                  currency: d.baseCurrency,
                  hidden: _hidden,
                ),
              ],
            ),
          ),
          () => MobileSection(
            title: 'Взносы и план',
            child: Column(
              children: [
                MobileValueRow(
                  title: 'Вложено в этом месяце',
                  amount: d.investedThisMonth,
                  currency: d.baseCurrency,
                  hidden: _hidden,
                ),
                MobileValueRow(
                  title: 'План на месяц',
                  amount: d.monthlyPlan,
                  currency: d.baseCurrency,
                  hidden: _hidden,
                ),
                capitalProgress(d.monthlyPlanProgress, hidden: _hidden),
              ],
            ),
          ),
          () => FilledButton(
            key: const Key('investment-add-button'),
            onPressed: () async {
              final id = await openMobileInvestmentEditor(context, c);
              if (id != null && mounted) _open(id);
            },
            child: const Text('Добавить инвестицию'),
          ),
          () => SwitchListTile(
            title: const Text('Показать архив'),
            value: _archive,
            onChanged: (v) => setState(() => _archive = v),
          ),
          if (rows.isEmpty)
            () => capitalNote('Инвестиций пока нет. Можно добавить вручную.'),
          for (final a in rows)
            () => MobileValueRow(
              title: a.name,
              amount: a.currentBalance,
              currency: a.currency,
              hidden: _hidden,
              caption:
                  '${a.brokerName ?? investmentTypes[a.type.name]} · ${investmentStatuses[a.status.name]}',
              onTap: () => _open(a.id),
              key: Key('capital-investment-${a.id}'),
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

class MobileInvestmentDetail extends StatefulWidget {
  const MobileInvestmentDetail({
    required this.controller,
    required this.investmentId,
    this.initiallyHidden = false,
    this.period = InvestmentPeriod.threeMonths,
    super.key,
  });
  final BudgetController controller;
  final String investmentId;
  final bool initiallyHidden;
  final InvestmentPeriod period;
  @override
  State<MobileInvestmentDetail> createState() => _MobileInvestmentDetailState();
}

class _MobileInvestmentDetailState extends State<MobileInvestmentDetail> {
  late bool _hidden = widget.initiallyHidden;
  @override
  Widget build(BuildContext context) => CapitalPage(
    title: 'Инвестиция',
    controller: widget.controller,
    actions: [
      capitalPrivacy(_hidden, () => setState(() => _hidden = !_hidden)),
    ],
    builder: (context) {
      final c = widget.controller;
      final a = c.investmentAccounts
          .where((a) => a.id == widget.investmentId)
          .firstOrNull;
      if (a == null) {
        return const Center(child: Text('Инвестиция больше не доступна'));
      }
      final i = mobileInvestments(
        c,
        widget.period,
      ).accounts.where((i) => i.account.id == a.id).firstOrNull;
      final snapshots =
          c.investmentBalanceSnapshots
              .where((s) => s.investmentAccountId == a.id)
              .toList()
            ..sort((x, y) => x.date.compareTo(y.date));
      final flows =
          c.investmentContributions
              .where((f) => f.investmentAccountId == a.id)
              .toList()
            ..sort((x, y) => y.date.compareTo(x.date));
      return CapitalRows(
        storageKey: 'investment-${a.id}',
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
                  key: const Key('mobile-investment-balance'),
                ),
                Text(
                  '${investmentStatuses[a.status.name]} · ${investmentTypes[a.type.name]}',
                ),
                Text(
                  'Стоимость обновлена ${formatDate(a.lastBalanceUpdateAt, includeYear: true)}',
                ),
                Text(
                  'Источник: ${capitalStatus(a.source.name)} · ${capitalStatus(const InvestmentAnalyticsService().freshness(a, c.referenceDate).name)}',
                ),
              ],
            ),
          ),
          if (i != null)
            () => MobileSection(
              title: 'За выбранный период',
              child: Column(
                children: [
                  MobileValueRow(
                    title: 'Внесено',
                    amount: i.contributions,
                    currency: a.currency,
                    hidden: _hidden,
                  ),
                  MobileValueRow(
                    title: 'Выведено',
                    amount: i.withdrawals,
                    currency: a.currency,
                    hidden: _hidden,
                  ),
                  if (i.change != null)
                    MobileValueRow(
                      title: 'Изменение стоимости',
                      amount: i.change!,
                      currency: c.user.defaultCurrency,
                      hidden: _hidden,
                    ),
                  if (i.differenceFromRecordedFlows != null)
                    MobileValueRow(
                      title: 'Разница с записанными потоками · не доходность',
                      amount: i.differenceFromRecordedFlows!,
                      currency: c.user.defaultCurrency,
                      hidden: _hidden,
                    ),
                ],
              ),
            ),
          () => capitalLink(
            'История стоимости',
            () => capitalPush(
              context,
              '/capital/investment/${a.id}/history',
              CapitalPage(
                title: 'История стоимости',
                controller: c,
                builder: (_) => CapitalRows(
                  items: [
                    () => MobileCapitalHistory(
                      points: [
                        for (final s in snapshots)
                          (
                            date: s.date,
                            amount: s.balance,
                            confirmed:
                                s.source != InvestmentDataSource.calculated,
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
            'Обновить стоимость',
            () => openMobileInvestmentValue(context, c, a),
          ),
          () => capitalLink(
            'Записать взнос / вывод',
            () => openMobileInvestmentContribution(context, c, a),
          ),
          () => capitalLink(
            'Взносы и выводы (${flows.length})',
            () => capitalPush(
              context,
              '/capital/investment/${a.id}/flows',
              CapitalPage(
                title: 'Записанные взносы',
                controller: c,
                builder: (_) => CapitalRows(
                  items: [
                    for (final f in flows)
                      () => MobileValueRow(
                        title: f.type == InvestmentContributionType.contribution
                            ? 'Взнос'
                            : 'Вывод',
                        amount: f.amount,
                        currency: f.currency,
                        hidden: _hidden,
                        caption:
                            '${formatDate(f.date)} · ${f.source.name}${f.comment == null ? '' : ' · ${f.comment}'}',
                      ),
                  ],
                ),
              ),
            ),
          ),
          () => capitalLink(
            'Настройки',
            () => openMobileInvestmentEditor(context, c, account: a),
          ),
          () => capitalNote(
            '${a.brokerName ?? 'Брокер не указан'}${a.openedAt == null ? '' : ' · Открыт ${formatDate(a.openedAt!)}'}${a.comment == null ? '' : '\n${a.comment}'}',
          ),
          if (a.status != InvestmentAccountStatus.archived)
            () => capitalLink(
              'Архивировать',
              () => capitalPush(
                context,
                '/capital/investment/${a.id}/archive',
                MobileCapitalEditor(
                  controller: c,
                  title: 'Архивировать инвестицию',
                  fields: const [],
                  initial: const {},
                  note:
                      'Счёт и история сохранятся в архиве. Это не продажа актива.',
                  saveLabel: 'Архивировать',
                  save: (d, w) async {
                    await w.run([
                      () => c.updateInvestmentAccount(
                        a.copyWith(status: InvestmentAccountStatus.archived),
                      ),
                    ]);
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

Future<String?> openMobileInvestmentEditor(
  BuildContext context,
  BudgetController c, {
  InvestmentAccount? account,
}) {
  final a = account;
  final before = c.investmentAccounts.map((a) => a.id).toSet();
  return capitalPush(
    context,
    '/capital/investment/${a?.id ?? 'create'}/edit',
    MobileCapitalEditor(
      controller: c,
      title: a == null ? 'Новая инвестиция' : 'Настройки инвестиции',
      saveKey: 'investment-save-button',
      fields: [
        const CapitalField('investment-name-field', 'Название', required: true),
        const CapitalField('broker', 'Брокер'),
        CapitalField(
          'investment-balance-field',
          'Текущая стоимость',
          kind: CapitalInput.whole,
          required: true,
          enabled: a == null,
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
          enabled: a == null,
        ),
        const CapitalField(
          'type',
          'Тип',
          kind: CapitalInput.choice,
          options: investmentTypes,
        ),
        if (a != null)
          const CapitalField(
            'status',
            'Статус',
            kind: CapitalInput.choice,
            options: investmentStatuses,
          ),
        const CapitalField(
          'include',
          'Учитывать в инвестиционном капитале',
          kind: CapitalInput.toggle,
        ),
        const CapitalField('opened', 'Дата открытия', kind: CapitalInput.date),
        const CapitalField(
          'plan',
          'Ежемесячный план',
          kind: CapitalInput.toggle,
        ),
        CapitalField(
          'planned',
          'Сумма плана',
          kind: CapitalInput.positive,
          required: true,
          visibleWhen: (d) => capitalBool(d, 'plan'),
        ),
        CapitalField(
          'day',
          'День плана',
          kind: CapitalInput.day,
          required: true,
          visibleWhen: (d) => capitalBool(d, 'plan'),
        ),
        CapitalField(
          'remind',
          'Напоминать по плану',
          kind: CapitalInput.toggle,
          visibleWhen: (d) => capitalBool(d, 'plan'),
        ),
        const CapitalField('comment', 'Комментарий'),
      ],
      initial: {
        'investment-name-field': a?.name ?? '',
        'broker': a?.brokerName ?? '',
        'investment-balance-field': a == null ? '' : '${a.currentBalance}',
        'currency': a?.currency ?? c.user.defaultCurrency,
        'type': a?.type.name ?? 'brokerage',
        'status': a?.status.name ?? 'active',
        'include': '${a?.includeInTotal ?? true}',
        'opened': a?.openedAt?.toIso8601String() ?? '',
        'plan': '${a?.plan?.enabled ?? false}',
        'planned': a?.plan?.amount.toString() ?? '',
        'day': '${a?.plan?.preferredDay ?? 12}',
        'remind': '${a?.plan?.reminderEnabled ?? false}',
        'comment': a?.comment ?? '',
      },
      validate: (d) =>
          capitalBool(d, 'plan') &&
              (capitalOptionalWhole(d['planned']) ?? 0) <= 0
          ? 'Для плана нужна положительная сумма'
          : null,
      save: (d, w) async {
        final plan = capitalBool(d, 'plan')
            ? InvestmentPlan(
                amount: capitalWhole(d['planned']!),
                preferredDay: capitalWhole(d['day']!),
                reminderEnabled: capitalBool(d, 'remind'),
              )
            : null;
        await w.run([
          () async {
            if (a == null) {
              await c.addInvestmentAccount(
                name: d['investment-name-field']!,
                currentBalance: capitalWhole(d['investment-balance-field']!),
                currency: d['currency'],
                type: InvestmentAccountType.values.byName(d['type']!),
                brokerName: d['broker'],
                openedAt: capitalDate(d['opened']),
                comment: d['comment'],
                includeInTotal: capitalBool(d, 'include'),
                plan: plan,
              );
            } else {
              await c.updateInvestmentAccount(
                a.copyWith(
                  name: d['investment-name-field'],
                  brokerName: d['broker'],
                  clearBrokerName: d['broker']!.trim().isEmpty,
                  type: InvestmentAccountType.values.byName(d['type']!),
                  status: InvestmentAccountStatus.values.byName(d['status']!),
                  includeInTotal: capitalBool(d, 'include'),
                  openedAt: capitalDate(d['opened']),
                  clearOpenedAt: capitalDate(d['opened']) == null,
                  comment: d['comment'],
                  clearComment: d['comment']!.trim().isEmpty,
                  plan: plan,
                  clearPlan: plan == null,
                ),
              );
            }
          },
        ]);
        return a?.id ??
            c.investmentAccounts
                .where((a) => !before.contains(a.id))
                .firstOrNull
                ?.id;
      },
    ),
  );
}

Future<String?> openMobileInvestmentValue(
  BuildContext context,
  BudgetController c,
  InvestmentAccount a,
) => capitalPush(
  context,
  '/capital/investment/${a.id}/valuation',
  MobileCapitalEditor(
    controller: c,
    title: 'Обновить стоимость',
    fields: const [
      CapitalField(
        'valuation',
        'Стоимость',
        kind: CapitalInput.whole,
        required: true,
      ),
      CapitalField(
        'date',
        'Дата оценки',
        kind: CapitalInput.date,
        required: true,
      ),
    ],
    initial: {
      'valuation': '${a.currentBalance}',
      'date': DateTime.now().toIso8601String(),
    },
    save: (d, w) async {
      await w.run([
        () => c.updateInvestmentBalance(
          investmentAccountId: a.id,
          balance: capitalWhole(d['valuation']!),
          date: capitalDate(d['date'])!,
        ),
      ]);
      return a.id;
    },
  ),
);
Future<String?> openMobileInvestmentContribution(
  BuildContext context,
  BudgetController c,
  InvestmentAccount a,
) => capitalPush(
  context,
  '/capital/investment/${a.id}/contribution',
  MobileCapitalEditor(
    controller: c,
    title: 'Взнос или вывод',
    note: 'Это запись движения инвестиций. Она не создаёт банковскую операцию.',
    fields: const [
      CapitalField(
        'amount',
        'Сумма',
        kind: CapitalInput.positive,
        required: true,
      ),
      CapitalField(
        'type',
        'Действие',
        kind: CapitalInput.choice,
        options: {'contribution': 'Взнос', 'withdrawal': 'Вывод'},
      ),
      CapitalField('date', 'Дата', kind: CapitalInput.date, required: true),
      CapitalField(
        'adjust',
        'Также изменить текущую стоимость',
        kind: CapitalInput.toggle,
      ),
      CapitalField('comment', 'Комментарий'),
    ],
    initial: {
      'type': 'contribution',
      'date': DateTime.now().toIso8601String(),
      'adjust': 'false',
    },
    save: (d, w) async {
      await w.run([
        () async {
          await c.addInvestmentContribution(
            investmentAccountId: a.id,
            amount: capitalWhole(d['amount']!),
            type: InvestmentContributionType.values.byName(d['type']!),
            date: capitalDate(d['date'])!,
            adjustBalance: capitalBool(d, 'adjust'),
            comment: d['comment'],
          );
        },
      ]);
      return a.id;
    },
  ),
);
