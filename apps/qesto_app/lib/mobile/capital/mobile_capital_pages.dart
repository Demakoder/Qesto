import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/formatters/qesto_formatters.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../analytics/mobile_financial_widgets.dart';
import '../analytics/mobile_statistics_controls.dart';
import 'mobile_capital_common.dart';
import 'mobile_capital_editor.dart';
import 'mobile_investment_pages.dart';
import 'mobile_debt_pages.dart';
import 'mobile_goal_pages.dart';

class MobileCapitalLanding extends StatefulWidget {
  const MobileCapitalLanding({
    required this.controller,
    required this.onOpenFilteredTransactions,
    super.key,
  });
  final BudgetController controller;
  final ValueChanged<List<String>> onOpenFilteredTransactions;
  @override
  State<MobileCapitalLanding> createState() => _MobileCapitalLandingState();
}

class _MobileCapitalLandingState extends State<MobileCapitalLanding> {
  bool _hidden = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final state = c.financialState;
      final liquidity = mobileLiquidity(c, CapitalPeriod.oneMonth);
      final known =
          c.synoballState.accounts.any(
            (a) => !a.isVirtual || a.balance.minorUnits != 0,
          ) ||
          c.investmentAccounts.isNotEmpty ||
          c.debts.isNotEmpty;
      return CapitalRows(
        storageKey: 'mobile-capital-root-scroll',
        items: [
          () => Row(
            children: [
              const Expanded(child: Text('Моё финансовое состояние')),
              capitalPrivacy(_hidden, () => setState(() => _hidden = !_hidden)),
            ],
          ),
          () => MobileSection(
            title: 'Общий капитал',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (known)
                  CapitalExactMoney(
                    (state.assets.minorUnits - state.debts.minorUnits).round(),
                    state.assets.currency,
                    hidden: _hidden,
                    key: const Key('mobile-capital-total'),
                  )
                else
                  const Text('Данные об активах и долгах ещё не добавлены'),
                const SizedBox(height: 8),
                const Text(
                  'Активы минус долги. Цели — распределение денег, не дополнительный актив.',
                ),
                if (c.synoballState.accounts.any(
                  (a) => a.currency != state.assets.currency,
                ))
                  const Text(
                    'Капитал — в базовой валюте учёта. Валютные счета доступны отдельно; итоги разделов могут использовать другой пересчёт.',
                  ),
              ],
            ),
          ),
          () => MobileValueRow(
            title: 'Ликвидность',
            amount: liquidity.totalLiquidAssets,
            currency: liquidity.baseCurrency,
            hidden: _hidden,
            caption: 'Деньги на счетах',
            onTap: () => capitalPush(
              context,
              '/capital/liquidity',
              MobileLiquidityPage(controller: c, initiallyHidden: _hidden),
            ),
          ),
          () => capitalLink(
            'Счета',
            () => capitalPush(
              context,
              '/capital/accounts',
              MobileAccountsPage(
                controller: c,
                initiallyHidden: _hidden,
                onOpenFilteredTransactions: widget.onOpenFilteredTransactions,
              ),
            ),
            key: const Key('mobile-capital-accounts'),
          ),
          () => capitalLink(
            'Подушка безопасности',
            () => capitalPush(
              context,
              '/capital/reserve',
              MobileReservePage(controller: c, initiallyHidden: _hidden),
            ),
          ),
          () => MobileValueRow(
            title: 'Инвестиции',
            amount: mobileInvestments(
              c,
              InvestmentPeriod.threeMonths,
            ).totalBalance,
            currency: c.user.defaultCurrency,
            hidden: _hidden,
            onTap: () => capitalPush(
              context,
              '/capital/investments',
              MobileInvestmentsPage(controller: c, initiallyHidden: _hidden),
            ),
            key: const Key('mobile-destination-investments'),
          ),
          () => MobileValueRow(
            title: 'Долги',
            amount: mobileDebts(c, DebtAnalyticsPeriod.threeMonths).totalDebt,
            currency: c.user.defaultCurrency,
            hidden: _hidden,
            onTap: () => capitalPush(
              context,
              '/capital/debts',
              MobileDebtsPage(controller: c, initiallyHidden: _hidden),
            ),
            key: const Key('mobile-destination-debts'),
          ),
          () => capitalLink(
            'Цели',
            () => capitalPush(
              context,
              '/capital/goals',
              MobileGoalsPage(controller: c, initiallyHidden: _hidden),
            ),
            subtitle: 'Накопления, сроки и распределение',
            key: const Key('mobile-destination-goals'),
          ),
          () => capitalLink('Добавить счёт', () async {
            final id = await openMobileAccountCreate(context, c);
            if (id != null && context.mounted) {
              capitalPush(
                context,
                '/capital/account/$id',
                MobileAccountDetail(
                  controller: c,
                  accountId: id,
                  onOpenFilteredTransactions: widget.onOpenFilteredTransactions,
                ),
              );
            }
          }, icon: Icons.add),
        ],
      );
    },
  );
}

class MobileLiquidityPage extends StatefulWidget {
  const MobileLiquidityPage({
    required this.controller,
    this.initiallyHidden = false,
    super.key,
  });
  final BudgetController controller;
  final bool initiallyHidden;
  @override
  State<MobileLiquidityPage> createState() => _MobileLiquidityPageState();
}

class _MobileLiquidityPageState extends State<MobileLiquidityPage> {
  CapitalPeriod _period = CapitalPeriod.oneMonth;
  late bool _hidden = widget.initiallyHidden;
  @override
  Widget build(BuildContext context) => CapitalPage(
    title: 'Ликвидность',
    controller: widget.controller,
    actions: [
      capitalPrivacy(_hidden, () => setState(() => _hidden = !_hidden)),
    ],
    builder: (context) {
      final d = mobileLiquidity(widget.controller, _period);
      return CapitalRows(
        storageKey: 'mobile-liquidity-scroll',
        items: [
          () => TextButton(
            onPressed: () async {
              final v = await mobileChoice(context, 'Период ликвидности', {
                for (final p in CapitalPeriod.values) p.name: p.label,
              }, _period.name);
              if (v != null && mounted) {
                setState(() => _period = CapitalPeriod.values.byName(v));
              }
            },
            child: Text('История: ${_period.label}'),
          ),
          () => MobileSection(
            title: 'Деньги на счетах',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d.accounts.isEmpty)
                  const Text('Нет ликвидных счетов')
                else
                  MobileMoney(
                    d.totalLiquidAssets,
                    currency: d.baseCurrency,
                    hidden: _hidden,
                    key: const Key('mobile-liquidity-total'),
                  ),
                if (!_hidden && d.change != null)
                  Text(
                    'Изменение: ${formatMoney(d.change!, d.baseCurrency, showSign: true)}',
                  ),
                if (d.accounts.isNotEmpty)
                  MobileCapitalHistory(
                    points: [
                      for (final p in d.history)
                        (
                          date: p.date,
                          amount: p.balance,
                          confirmed: p.isConfirmed,
                        ),
                    ],
                    currency: d.baseCurrency,
                    hidden: _hidden,
                  ),
                Text(
                  d.isHistoryReconstructed
                      ? 'История рассчитана по операциям, не банковские ежедневные снимки.'
                      : 'История по доступным остаткам.',
                ),
              ],
            ),
          ),
          () => MobileSection(
            title: 'Распределение денег',
            child: Column(
              children: [
                for (final row in d.distribution)
                  MobileValueRow(
                    title: row.label,
                    amount: row.amount,
                    currency: d.baseCurrency,
                    hidden: _hidden,
                  ),
              ],
            ),
          ),
          () => MobileSection(
            title: 'До следующего дохода · оценка',
            child: Column(
              children: [
                MobileValueRow(
                  title: 'Зарезервировано',
                  amount: d.reservedCash,
                  currency: d.baseCurrency,
                  hidden: _hidden,
                ),
                MobileValueRow(
                  title: 'Платежи по долгам в резерве',
                  amount: d.debtPaymentsReserved,
                  currency: d.baseCurrency,
                  hidden: _hidden,
                ),
                MobileValueRow(
                  title: 'Доступно',
                  amount: d.availableCash,
                  currency: d.baseCurrency,
                  hidden: _hidden,
                ),
                if (d.nextExpectedIncome case final next?)
                  MobileValueRow(
                    title: next.title,
                    amount: next.amount,
                    currency: d.baseCurrency,
                    hidden: _hidden,
                    caption:
                        '${formatDate(next.date)} · ожидаемый доход, не факт',
                  )
                else
                  const Text('Недостаточно данных для следующего дохода'),
                if (d.minimumProjectedBalance != null)
                  MobileValueRow(
                    title: 'Минимальный прогнозный остаток',
                    amount: d.minimumProjectedBalance!,
                    currency: d.baseCurrency,
                    hidden: _hidden,
                  ),
                Text(
                  'Состояние оценки: ${capitalStatus(d.lowBalanceRisk.name)}',
                ),
              ],
            ),
          ),
          () => capitalLink(
            'Настроить подушку',
            () => capitalPush(
              context,
              '/capital/reserve',
              MobileReservePage(
                controller: widget.controller,
                initiallyHidden: _hidden,
              ),
            ),
          ),
          if (d.hasUnconvertedCurrencies)
            () => capitalNote(
              'Часть валют не пересчитана. Проверьте счета в исходной валюте.',
            ),
          if (d.unlinkedTransactionCount > 0)
            () => capitalNote(
              'Операций без точной привязки: ${d.unlinkedTransactionCount}. История может быть расчётной.',
            ),
        ],
      );
    },
  );
}

const accountTypeOptions = {
  'bankCard': 'Карта / текущий счёт',
  'savings': 'Накопительный счёт',
  'deposit': 'Ликвидный вклад',
  'cash': 'Наличные',
};
const accountRoleOptions = {
  'everyday': 'Повседневный',
  'emergency': 'Подушка',
  'savings': 'Накопления',
  'salary': 'Зарплатный',
  'mandatoryPayments': 'Обязательные платежи',
  'other': 'Другой',
};
Future<String?> openMobileAccountCreate(
  BuildContext context,
  BudgetController c,
) {
  final before = c.accounts.map((a) => a.id).toSet();
  return capitalPush(
    context,
    '/capital/account/create',
    MobileCapitalEditor(
      controller: c,
      title: 'Добавить счёт',
      fields: [
        const CapitalField('account-name-field', 'Название', required: true),
        const CapitalField(
          'account-balance-field',
          'Остаток',
          kind: CapitalInput.whole,
          required: true,
          allowNegative: true,
        ),
        const CapitalField(
          'type',
          'Тип',
          kind: CapitalInput.choice,
          options: accountTypeOptions,
        ),
        CapitalField(
          'currency',
          'Валюта',
          kind: CapitalInput.choice,
          options: {
            ...capitalCurrencies,
            c.user.defaultCurrency: c.user.defaultCurrency,
          },
        ),
      ],
      initial: {'type': 'bankCard', 'currency': c.user.defaultCurrency},
      saveKey: 'account-add-confirm',
      save: (d, w) async {
        await w.run([
          () async {
            await c.addAccount(
              title: d['account-name-field']!,
              balance: capitalWhole(d['account-balance-field']!),
              type: AccountType.values.byName(d['type']!),
              currency: d['currency'],
            );
          },
        ]);
        return c.accounts.where((a) => !before.contains(a.id)).firstOrNull?.id;
      },
    ),
  );
}

class MobileAccountsPage extends StatefulWidget {
  const MobileAccountsPage({
    required this.controller,
    required this.onOpenFilteredTransactions,
    this.initiallyHidden = false,
    super.key,
  });
  final BudgetController controller;
  final ValueChanged<List<String>> onOpenFilteredTransactions;
  final bool initiallyHidden;
  @override
  State<MobileAccountsPage> createState() => _MobileAccountsPageState();
}

class _MobileAccountsPageState extends State<MobileAccountsPage> {
  bool _showHidden = false;
  late bool _hidden = widget.initiallyHidden;
  void _detail(String id) => capitalPush(
    context,
    '/capital/account/$id',
    MobileAccountDetail(
      controller: widget.controller,
      accountId: id,
      initiallyHidden: _hidden,
      onOpenFilteredTransactions: widget.onOpenFilteredTransactions,
    ),
  );
  @override
  Widget build(BuildContext context) => CapitalPage(
    title: 'Счета',
    controller: widget.controller,
    actions: [
      capitalPrivacy(_hidden, () => setState(() => _hidden = !_hidden)),
    ],
    builder: (context) {
      final c = widget.controller;
      final rows = c.accounts
          .where(
            (a) =>
                a.type != AccountType.investment &&
                a.type != AccountType.liability &&
                a.id != 'local-default-account',
          )
          .where((a) => _showHidden || c.accountPreferencesFor(a.id).isVisible)
          .toList();
      final data = mobileLiquidity(c, CapitalPeriod.oneMonth);
      return CapitalRows(
        storageKey: 'mobile-accounts-scroll',
        items: [
          () => SwitchListTile(
            title: const Text('Показать скрытые'),
            value: _showHidden,
            onChanged: (v) => setState(() => _showHidden = v),
          ),
          () => FilledButton(
            onPressed: () async {
              final id = await openMobileAccountCreate(context, c);
              if (id != null && mounted) _detail(id);
            },
            child: const Text('Добавить счёт'),
          ),
          if (rows.isEmpty)
            () => capitalNote(
              'Счетов пока нет. Скрытые счета можно показать выше.',
            ),
          for (final a in rows)
            () {
              final p = c.accountPreferencesFor(a.id);
              final insight = data.accounts
                  .where((i) => i.account.id == a.id)
                  .firstOrNull;
              return MobileSection(
                title: a.title,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (a.id.startsWith('sber-unassigned-'))
                      const Text('Остаток неизвестен · технический счёт')
                    else
                      CapitalExactMoney(
                        a.balanceMinor,
                        a.currency,
                        hidden: _hidden,
                      ),
                    capitalLink(
                      'Подробнее',
                      () => _detail(a.id),
                      key: Key('capital-account-${a.id}'),
                      subtitle:
                          '${accountTypeOptions[a.type.name] ?? a.type.name} · ${accountRoleOptions[p.role.name]}${p.includeInEmergencyFund ? ' · Подушка' : ''}${p.isClosed ? ' · Закрыт' : ''}',
                    ),
                    if (insight != null)
                      Text(
                        'Данные: ${capitalStatus(insight.status.name)}${insight.lastUpdatedAt == null ? '' : ' · ${formatDate(insight.lastUpdatedAt!)}'}',
                      ),
                  ],
                ),
              );
            },
        ],
      );
    },
  );
}

class MobileAccountDetail extends StatefulWidget {
  const MobileAccountDetail({
    required this.controller,
    required this.accountId,
    required this.onOpenFilteredTransactions,
    this.initiallyHidden = false,
    super.key,
  });
  final BudgetController controller;
  final String accountId;
  final ValueChanged<List<String>> onOpenFilteredTransactions;
  final bool initiallyHidden;
  @override
  State<MobileAccountDetail> createState() => _MobileAccountDetailState();
}

class _MobileAccountDetailState extends State<MobileAccountDetail> {
  late bool _hidden = widget.initiallyHidden;
  CapitalPeriod _period = CapitalPeriod.oneMonth;
  @override
  Widget build(BuildContext context) => CapitalPage(
    title: 'Счёт',
    controller: widget.controller,
    actions: [
      capitalPrivacy(_hidden, () => setState(() => _hidden = !_hidden)),
    ],
    builder: (context) {
      final c = widget.controller;
      final a = c.accounts.where((a) => a.id == widget.accountId).firstOrNull;
      if (a == null) {
        return const Center(child: Text('Счёт больше не доступен'));
      }
      final p = c.accountPreferencesFor(a.id);
      final insight = mobileLiquidity(
        c,
        _period,
      ).accounts.where((i) => i.account.id == a.id).firstOrNull;
      return CapitalRows(
        storageKey: 'account-${a.id}',
        items: [
          () => MobileSection(
            title: a.title,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (a.id.startsWith('sber-unassigned-'))
                  const Text('Остаток неизвестен')
                else
                  CapitalExactMoney(
                    a.balanceMinor,
                    a.currency,
                    hidden: _hidden,
                  ),
                Text(
                  '${accountTypeOptions[a.type.name] ?? a.type.name} · ${accountRoleOptions[p.role.name]}',
                ),
              ],
            ),
          ),
          () => capitalLink(
            'Роль и настройки',
            () => openMobileAccountSettings(context, c, a.id),
            key: const Key('capital-account-settings'),
          ),
          if (insight != null)
            () => TextButton(
              onPressed: () async {
                final v = await mobileChoice(context, 'Период счёта', {
                  for (final p in CapitalPeriod.values) p.name: p.label,
                }, _period.name);
                if (v != null && mounted) {
                  setState(() => _period = CapitalPeriod.values.byName(v));
                }
              },
              child: Text('История: ${_period.label}'),
            ),
          if (insight != null)
            () => MobileSection(
              title: 'История',
              child: MobileCapitalHistory(
                points: [
                  for (final v in insight.history)
                    (date: v.date, amount: v.balance, confirmed: v.isConfirmed),
                ],
                currency: c.user.defaultCurrency,
                hidden: _hidden,
              ),
            ),
          if (insight != null)
            () => MobileSection(
              title: 'Движение по счёту',
              child: Column(
                children: [
                  MobileValueRow(
                    title: 'Поступления',
                    amount: insight.inflow,
                    currency: c.user.defaultCurrency,
                    hidden: _hidden,
                  ),
                  MobileValueRow(
                    title: 'Списания',
                    amount: insight.outflow,
                    currency: c.user.defaultCurrency,
                    hidden: _hidden,
                  ),
                  MobileValueRow(
                    title: 'Внутренние переводы',
                    amount: insight.internalTransfers,
                    currency: c.user.defaultCurrency,
                    hidden: _hidden,
                  ),
                  Text('Статус: ${capitalStatus(insight.status.name)}'),
                ],
              ),
            ),
          () => capitalLink(
            'Операции счёта',
            () => widget.onOpenFilteredTransactions(
              c.transactions
                  .where((t) => t.accountId == a.id)
                  .map((t) => t.id)
                  .toList(),
            ),
          ),
          () => capitalNote(
            'Удаление счёта не поддерживается текущей моделью. Видимость и учёт настраиваются отдельно.',
          ),
        ],
      );
    },
  );
}

Future<String?> openMobileAccountSettings(
  BuildContext context,
  BudgetController c,
  String id,
) {
  final p = c.accountPreferencesFor(id);
  return capitalPush(
    context,
    '/capital/account/$id/settings',
    MobileCapitalEditor(
      controller: c,
      title: 'Роль и настройки',
      fields: const [
        CapitalField(
          'role',
          'Роль',
          kind: CapitalInput.choice,
          options: accountRoleOptions,
        ),
        CapitalField(
          'total',
          'Учитывать в ликвидности',
          kind: CapitalInput.toggle,
        ),
        CapitalField('net', 'Учитывать в капитале', kind: CapitalInput.toggle),
        CapitalField('reserve', 'Счёт подушки', kind: CapitalInput.toggle),
        CapitalField('visible', 'Показывать счёт', kind: CapitalInput.toggle),
        CapitalField(
          'analytics',
          'Операции в аналитике',
          kind: CapitalInput.toggle,
        ),
        CapitalField('closed', 'Счёт закрыт', kind: CapitalInput.toggle),
      ],
      initial: {
        'role': p.role.name,
        'total': '${p.includeInTotal}',
        'net': '${p.includeInNetWorth}',
        'reserve': '${p.includeInEmergencyFund}',
        'visible': '${p.isVisible}',
        'analytics': '${p.includeTransactionsInAnalytics}',
        'closed': '${p.isClosed}',
      },
      save: (d, w) async {
        await w.run([
          () => c.updateAccountPreferences(
            p.copyWith(
              role: QestoAccountRole.values.byName(d['role']!),
              includeInTotal: capitalBool(d, 'total'),
              includeInNetWorth: capitalBool(d, 'net'),
              includeInEmergencyFund: capitalBool(d, 'reserve'),
              isVisible: capitalBool(d, 'visible'),
              includeTransactionsInAnalytics: capitalBool(d, 'analytics'),
              isClosed: capitalBool(d, 'closed'),
            ),
          ),
        ]);
        return id;
      },
    ),
  );
}

class MobileReservePage extends StatelessWidget {
  const MobileReservePage({
    required this.controller,
    this.initiallyHidden = false,
    super.key,
  });
  final BudgetController controller;
  final bool initiallyHidden;
  @override
  Widget build(BuildContext context) => CapitalPage(
    title: 'Подушка безопасности',
    controller: controller,
    builder: (context) {
      final d = mobileLiquidity(controller, CapitalPeriod.oneMonth);
      return CapitalRows(
        items: [
          () => MobileSection(
            title: 'Резерв на выбранных счетах',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MobileMoney(
                  d.emergencyFundAmount,
                  currency: d.baseCurrency,
                  hidden: initiallyHidden,
                ),
                Text('Счетов: ${d.emergencyAccountCount}'),
                if (d.emergencyFundMonths != null && !initiallyHidden)
                  Text(
                    'Покрытие: ${d.emergencyFundMonths!.toStringAsFixed(1)} мес.',
                  ),
                if (d.emergencyGoal case final g?) ...[
                  MobileValueRow(
                    title: 'Целевая сумма',
                    amount: g.targetAmount,
                    currency: g.currency,
                    hidden: initiallyHidden,
                  ),
                  capitalProgress(
                    g.targetAmount > 0
                        ? d.emergencyFundAmount / g.targetAmount
                        : 0,
                    hidden: initiallyHidden,
                  ),
                ] else
                  const Text('Цель подушки не задана'),
                FilledButton(
                  key: const Key('mobile-reserve-edit'),
                  onPressed: () => openMobileReserveEditor(context, controller),
                  child: const Text('Настроить резерв'),
                ),
              ],
            ),
          ),
          () => capitalNote(
            'Подушка — существующие деньги на выбранных счетах, не отдельный дополнительный актив.',
          ),
          for (final a in d.accounts.where(
            (a) => a.preferences.includeInEmergencyFund,
          ))
            () => MobileValueRow(
              title: a.account.title,
              amount: a.account.balance,
              currency: a.account.currency,
              hidden: initiallyHidden,
            ),
        ],
      );
    },
  );
}

Future<String?> openMobileReserveEditor(
  BuildContext context,
  BudgetController c,
) {
  final data = mobileLiquidity(c, CapitalPeriod.oneMonth);
  final g = data.emergencyGoal;
  final before = c.savingsGoals.map((g) => g.id).toSet();
  return capitalPush(
    context,
    '/capital/reserve/edit',
    MobileCapitalEditor(
      controller: c,
      title: 'Настроить резерв',
      note:
          'Сумма цели хранится в существующей модели. Количество месяцев — способ заполнить сумму, не новая финансовая настройка.',
      fields: [
        if (data.averageEssentialMonthlyExpenses != null)
          const CapitalField(
            'reserve-months',
            'Месяцев расходов (1–60)',
            kind: CapitalInput.positive,
          ),
        const CapitalField(
          'reserve-target',
          'Целевая сумма',
          kind: CapitalInput.positive,
          required: true,
        ),
        for (final a in data.accounts)
          CapitalField(
            'reserve-${a.account.id}',
            a.account.title,
            kind: CapitalInput.toggle,
          ),
      ],
      initial: {
        'reserve-target':
            g?.targetAmount.toString() ??
            (data.averageEssentialMonthlyExpenses == null
                ? ''
                : '${data.averageEssentialMonthlyExpenses! * 6}'),
        for (final a in data.accounts)
          'reserve-${a.account.id}': '${a.preferences.includeInEmergencyFund}',
      },
      onDraftChanged: (d, id) {
        if (id == 'reserve-months') {
          final months = int.tryParse(d[id] ?? '');
          if (months != null && months > 0 && months <= 60) {
            d['reserve-target'] =
                '${data.averageEssentialMonthlyExpenses! * months}';
          }
        }
      },
      validate: (d) {
        if ((capitalOptionalWhole(d['reserve-months']) ?? 1) > 60) {
          return 'Укажите от 1 до 60 месяцев';
        }
        return data.accounts.any(
              (a) => capitalBool(d, 'reserve-${a.account.id}'),
            )
            ? null
            : 'Выберите хотя бы один счёт подушки';
      },
      save: (d, w) async {
        final amount = capitalWhole(d['reserve-target']!);
        await w.run([
          for (final a in data.accounts)
            if (a.preferences.includeInEmergencyFund !=
                capitalBool(d, 'reserve-${a.account.id}'))
              () => c.updateAccountPreferences(
                a.preferences.copyWith(
                  includeInEmergencyFund: capitalBool(
                    d,
                    'reserve-${a.account.id}',
                  ),
                ),
              ),
          () async {
            if (g == null) {
              await c.addSavingsGoal(
                title: 'Подушка безопасности',
                category: 'Финансовая подушка',
                targetAmount: amount,
                savedAmount: math.min(data.emergencyFundAmount, amount),
                targetDate: DateTime.now().add(const Duration(days: 365)),
                currency: data.baseCurrency,
              );
            } else {
              await c.updateSavingsGoal(
                g.copyWith(
                  targetAmount: amount,
                  savedAmount: math.min(data.emergencyFundAmount, amount),
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
