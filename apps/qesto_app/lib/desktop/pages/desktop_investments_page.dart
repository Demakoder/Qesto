import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../design_system/qesto_window.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/capital/domain/investment_analytics_service.dart';
import '../widgets/desktop_components.dart';

class DesktopInvestmentsPage extends StatefulWidget {
  const DesktopInvestmentsPage({
    required this.controller,
    this.freshnessDate,
    super.key,
  });

  final BudgetController controller;

  /// Fixed only by screenshot tests; the installed app uses the current date.
  final DateTime? freshnessDate;

  @override
  State<DesktopInvestmentsPage> createState() => _DesktopInvestmentsPageState();
}

class _DesktopInvestmentsPageState extends State<DesktopInvestmentsPage> {
  static const _analytics = InvestmentAnalyticsService();
  InvestmentPeriod _period = InvestmentPeriod.threeMonths;
  String? _selectedAccountId;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final selected = widget.controller.investmentAccounts
          .where((item) => item.id == _selectedAccountId)
          .firstOrNull;
      if (selected != null) return _buildAccountDetails(context, selected);
      return _buildOverview(context);
    },
  );

  Widget _buildOverview(BuildContext context) {
    final data = _analytics.calculate(
      accounts: widget.controller.investmentAccounts,
      balanceSnapshots: widget.controller.investmentBalanceSnapshots,
      contributions: widget.controller.investmentContributions,
      asOf: widget.controller.referenceDate,
      period: _period,
      baseCurrency: widget.controller.user.defaultCurrency,
    );
    final hasAccounts = widget.controller.investmentAccounts.any(
      (item) => item.status != InvestmentAccountStatus.archived,
    );
    return ListView(
      key: const Key('investments-overview'),
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 30),
      children: [
        _InvestmentHeader(onAdd: () => _openAccountEditor(context)),
        const SizedBox(height: 16),
        if (!hasAccounts)
          DesktopEmptyState(
            title: 'Инвестиционных счетов пока нет',
            message:
                'Добавьте счёт вручную, чтобы видеть инвестиционный капитал, историю стоимости и регулярность пополнений. Подключение брокеров появится позже.',
            icon: Icons.candlestick_chart_outlined,
            action: FilledButton.icon(
              key: const Key('investment-empty-add-button'),
              onPressed: () => _openAccountEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить инвестиционный счёт'),
            ),
          )
        else ...[
          _InvestmentHero(data: data),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 900;
              final chart = _InvestmentValueCard(
                data: data,
                period: _period,
                onPeriodChanged: (value) => setState(() => _period = value),
              );
              final flow = _InvestmentFlowCard(data: data);
              if (stacked) {
                return Column(
                  children: [chart, const SizedBox(height: 14), flow],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: chart),
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: flow),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Ваши инвестиционные счета',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _openAccountEditor(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Добавить счёт'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final insight in data.accounts)
                SizedBox(
                  width: 350,
                  child: _InvestmentAccountCard(
                    insight: insight,
                    freshnessDate: widget.freshnessDate,
                    onTap: () =>
                        setState(() => _selectedAccountId = insight.account.id),
                  ),
                ),
            ],
          ),
          if (data.hasUnconvertedCurrencies) ...[
            const SizedBox(height: 14),
            const _InvestmentNote(
              icon: Icons.currency_exchange_rounded,
              text:
                  'Часть значений не удалось пересчитать в основную валюту. Исходные суммы и валюты сохранены.',
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildAccountDetails(BuildContext context, InvestmentAccount account) {
    final data = _analytics.calculate(
      accounts: [account],
      balanceSnapshots: widget.controller.investmentBalanceSnapshots,
      contributions: widget.controller.investmentContributions,
      asOf: widget.controller.referenceDate,
      period: _period,
      baseCurrency: account.currency,
    );
    final insight = data.accounts.first;
    final snapshots =
        widget.controller.investmentBalanceSnapshots
            .where((item) => item.investmentAccountId == account.id)
            .toList()
          ..sort((left, right) => right.date.compareTo(left.date));
    final contributions =
        widget.controller.investmentContributions
            .where((item) => item.investmentAccountId == account.id)
            .toList()
          ..sort((left, right) => right.date.compareTo(left.date));
    return ListView(
      key: const Key('investment-account-details'),
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 30),
      children: [
        DesktopAdaptiveRow(
          children: [
            IconButton(
              tooltip: 'Назад к инвестициям',
              onPressed: () => setState(() => _selectedAccountId = null),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${_investmentTypeLabel(account.type)} · ${account.brokerName ?? 'ручной счёт'}',
                    style: TextStyle(color: context.qestoColors.secondaryText),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _openAccountEditor(context, account: account),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Настроить'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const Key('investment-update-balance-button'),
              onPressed: () => _openBalanceEditor(context, account),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Обновить стоимость'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _InvestmentMetric(
              label: 'Текущая стоимость',
              value: formatMoney(account.currentBalance, account.currency),
              icon: Icons.account_balance_wallet_outlined,
            ),
            _InvestmentMetric(
              label: 'Пополнено',
              value: formatMoney(insight.contributions, account.currency),
              icon: Icons.south_west_rounded,
              accent: context.qestoColors.positive,
            ),
            _InvestmentMetric(
              label: 'Выведено',
              value: formatMoney(insight.withdrawals, account.currency),
              icon: Icons.north_east_rounded,
              accent: context.qestoColors.warning,
            ),
            _InvestmentMetric(
              label: 'Чистые пополнения',
              value: formatMoney(insight.netContributions, account.currency),
              icon: Icons.swap_vert_rounded,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _InvestmentValueCard(
          data: data,
          period: _period,
          onPeriodChanged: (value) => setState(() => _period = value),
          title: 'История стоимости счёта',
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final history = _InvestmentHistoryCard(
              title: 'Движение денег',
              emptyText: 'Пополнений и выводов пока нет',
              action: FilledButton.tonalIcon(
                key: const Key('investment-add-contribution-button'),
                onPressed: () => _openContributionEditor(context, account),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Добавить операцию'),
              ),
              children: [
                for (final item in contributions.take(8))
                  _InvestmentHistoryRow(
                    icon: item.type == InvestmentContributionType.contribution
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    title: item.type == InvestmentContributionType.contribution
                        ? 'Пополнение'
                        : 'Вывод',
                    subtitle:
                        '${formatDate(item.date, includeYear: true)} · ${_investmentSourceLabel(item.source)}',
                    value:
                        '${item.type == InvestmentContributionType.contribution ? '+' : '−'}${formatMoney(item.amount, item.currency)}',
                    color: item.type == InvestmentContributionType.contribution
                        ? context.qestoColors.positive
                        : context.qestoColors.warning,
                  ),
              ],
            );
            final updates = _InvestmentHistoryCard(
              title: 'Обновления стоимости',
              emptyText: 'История появится после обновления стоимости',
              children: [
                for (final item in snapshots.take(8))
                  _InvestmentHistoryRow(
                    icon: Icons.timeline_rounded,
                    title: formatMoney(item.balance, item.currency),
                    subtitle:
                        '${formatDate(item.date, includeYear: true)} · ${_investmentSourceLabel(item.source)}',
                  ),
              ],
            );
            if (constraints.maxWidth < 850) {
              return Column(
                children: [history, const SizedBox(height: 14), updates],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: history),
                const SizedBox(width: 14),
                Expanded(child: updates),
              ],
            );
          },
        ),
        if (insight.differenceFromRecordedFlows != null) ...[
          const SizedBox(height: 14),
          _InvestmentNote(
            icon: Icons.info_outline_rounded,
            text:
                'Разница стоимости относительно записанного начального значения и чистых пополнений: ${formatMoney(insight.differenceFromRecordedFlows!, account.currency)}. Это не точная инвестиционная доходность.',
          ),
        ],
      ],
    );
  }

  Future<void> _openAccountEditor(
    BuildContext context, {
    InvestmentAccount? account,
  }) async {
    final name = TextEditingController(text: account?.name ?? '');
    final broker = TextEditingController(text: account?.brokerName ?? '');
    final balance = TextEditingController(
      text: account == null ? '' : account.currentBalance.toString(),
    );
    final comment = TextEditingController(text: account?.comment ?? '');
    final planAmount = TextEditingController(
      text: account?.plan?.amount.toString() ?? '',
    );
    final planDay = TextEditingController(
      text: account?.plan?.preferredDay?.toString() ?? '12',
    );
    var type = account?.type ?? InvestmentAccountType.brokerage;
    var currency = account?.currency ?? widget.controller.user.defaultCurrency;
    var includeInTotal = account?.includeInTotal ?? true;
    var planEnabled = account?.plan?.enabled ?? false;
    var reminderEnabled = account?.plan?.reminderEnabled ?? false;
    var status = account?.status ?? InvestmentAccountStatus.active;
    String? error;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          key: const Key('investment-account-editor'),
          title: Text(
            account == null ? 'Новый инвестиционный счёт' : 'Настроить счёт',
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('investment-name-field'),
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                      prefixIcon: Icon(Icons.account_balance_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: broker,
                    decoration: const InputDecoration(labelText: 'Брокер'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('investment-balance-field'),
                          controller: balance,
                          enabled: account == null,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: account == null
                                ? 'Текущая стоимость'
                                : 'Стоимость меняется отдельной кнопкой',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 105,
                        child: DropdownButtonFormField<String>(
                          initialValue: currency,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Валюта',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'RUB', child: Text('RUB')),
                            DropdownMenuItem(value: 'USD', child: Text('USD')),
                            DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                            DropdownMenuItem(value: 'CNY', child: Text('CNY')),
                          ],
                          onChanged: account == null
                              ? (value) {
                                  if (value != null) {
                                    setDialogState(() => currency = value);
                                  }
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<InvestmentAccountType>(
                          initialValue: type,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Тип счёта',
                          ),
                          items: [
                            for (final item in InvestmentAccountType.values)
                              DropdownMenuItem(
                                value: item,
                                child: Text(_investmentTypeLabel(item)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => type = value);
                            }
                          },
                        ),
                      ),
                      if (account != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child:
                              DropdownButtonFormField<InvestmentAccountStatus>(
                                initialValue: status,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Статус',
                                ),
                                items: [
                                  for (final item
                                      in InvestmentAccountStatus.values)
                                    DropdownMenuItem(
                                      value: item,
                                      child: Text(_investmentStatusLabel(item)),
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
                    ],
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Учитывать в инвестиционном капитале'),
                    value: includeInTotal,
                    onChanged: (value) =>
                        setDialogState(() => includeInTotal = value),
                  ),
                  const Divider(),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ежемесячный план'),
                    subtitle: const Text('Необязательно'),
                    value: planEnabled,
                    onChanged: (value) =>
                        setDialogState(() => planEnabled = value),
                  ),
                  if (planEnabled) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: planAmount,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Сумма в месяц',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 140,
                          child: TextField(
                            controller: planDay,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'День месяца',
                            ),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Сохранить настройку напоминания'),
                      subtitle: const Text(
                        'Будет использована системой уведомлений',
                      ),
                      value: reminderEnabled,
                      onChanged: (value) =>
                          setDialogState(() => reminderEnabled = value),
                    ),
                  ],
                  TextField(
                    controller: comment,
                    maxLines: 2,
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              key: const Key('investment-save-button'),
              onPressed: () {
                final amount = _amount(balance.text);
                final planned = _amount(planAmount.text);
                final day = _amount(planDay.text);
                if (name.text.trim().isEmpty || amount < 0) {
                  setDialogState(() => error = 'Укажите название и стоимость');
                } else if (planEnabled &&
                    (planned <= 0 || day < 1 || day > 31)) {
                  setDialogState(
                    () => error = 'Для плана укажите сумму и день от 1 до 31',
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
    if (save == true) {
      final plan = planEnabled
          ? InvestmentPlan(
              amount: _amount(planAmount.text),
              preferredDay: _amount(planDay.text),
              reminderEnabled: reminderEnabled,
            )
          : null;
      if (account == null) {
        await widget.controller.addInvestmentAccount(
          name: name.text,
          currentBalance: _amount(balance.text),
          brokerName: broker.text,
          type: type,
          currency: currency,
          comment: comment.text,
          includeInTotal: includeInTotal,
          plan: plan,
        );
      } else {
        await widget.controller.updateInvestmentAccount(
          account.copyWith(
            name: name.text,
            brokerName: broker.text,
            type: type,
            comment: comment.text,
            includeInTotal: includeInTotal,
            status: status,
            plan: plan,
            clearBrokerName: broker.text.trim().isEmpty,
            clearComment: comment.text.trim().isEmpty,
            clearPlan: plan == null,
          ),
        );
        if (status == InvestmentAccountStatus.archived && mounted) {
          setState(() => _selectedAccountId = null);
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose();
    broker.dispose();
    balance.dispose();
    comment.dispose();
    planAmount.dispose();
    planDay.dispose();
  }

  Future<void> _openBalanceEditor(
    BuildContext context,
    InvestmentAccount account,
  ) async {
    final amount = TextEditingController(
      text: account.currentBalance.toString(),
    );
    var date = DateTime.now();
    String? error;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Обновить стоимость'),
          content: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('investment-new-balance-field'),
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Новая стоимость, ${account.currency}',
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Дата оценки'),
                  subtitle: Text(formatDate(date, includeYear: true)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: account.createdAt,
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: context.qestoColors.danger),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (_amount(amount.text) < 0) {
                  setDialogState(
                    () => error = 'Стоимость не может быть отрицательной',
                  );
                } else {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Сохранить snapshot'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      await widget.controller.updateInvestmentBalance(
        investmentAccountId: account.id,
        balance: _amount(amount.text),
        date: date,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    amount.dispose();
  }

  Future<void> _openContributionEditor(
    BuildContext context,
    InvestmentAccount account,
  ) async {
    final amount = TextEditingController();
    final comment = TextEditingController();
    var type = InvestmentContributionType.contribution;
    var date = DateTime.now();
    var adjustBalance = false;
    String? error;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Движение денег'),
          content: SizedBox(
            width: 410,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<InvestmentContributionType>(
                  segments: const [
                    ButtonSegment(
                      value: InvestmentContributionType.contribution,
                      label: Text('Пополнение'),
                      icon: Icon(Icons.south_west_rounded),
                    ),
                    ButtonSegment(
                      value: InvestmentContributionType.withdrawal,
                      label: Text('Вывод'),
                      icon: Icon(Icons.north_east_rounded),
                    ),
                  ],
                  selected: {type},
                  onSelectionChanged: (value) =>
                      setDialogState(() => type = value.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('investment-contribution-amount-field'),
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Сумма, ${account.currency}',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(formatDate(date, includeYear: true)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: account.createdAt,
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setDialogState(() => date = picked);
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Также изменить текущую стоимость'),
                  subtitle: const Text(
                    'Включите, если сумма уже не учтена в последней оценке счёта',
                  ),
                  value: adjustBalance,
                  onChanged: (value) =>
                      setDialogState(() => adjustBalance = value ?? false),
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
              key: const Key('investment-contribution-save-button'),
              onPressed: () {
                if (_amount(amount.text) <= 0) {
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
      await widget.controller.addInvestmentContribution(
        investmentAccountId: account.id,
        amount: _amount(amount.text),
        type: type,
        date: date,
        comment: comment.text,
        adjustBalance: adjustBalance,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    amount.dispose();
    comment.dispose();
  }

  int _amount(String value) =>
      int.tryParse(value.replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
}

class _InvestmentHeader extends StatelessWidget {
  const _InvestmentHeader({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Инвестиции', style: QestoTypography.sectionTitle),
            SizedBox(height: 4),
            Text(
              'Стоимость, пополнения и регулярность — без выдуманной доходности',
              style: TextStyle(color: context.qestoColors.secondaryText),
            ),
          ],
        ),
      ),
      FilledButton.icon(
        key: const Key('investment-add-button'),
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Добавить счёт'),
      ),
    ],
  );
}

class _InvestmentHero extends StatelessWidget {
  const _InvestmentHero({required this.data});
  final InvestmentPortfolioSnapshot data;

  @override
  Widget build(BuildContext context) => DesktopCard(
    color: context.qestoColors.surface,
    borderColor: context.qestoColors.primary.withValues(alpha: 0.15),
    child: Wrap(
      spacing: 42,
      runSpacing: 18,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 310,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Инвестиционный капитал',
                style: TextStyle(
                  color: context.qestoColors.secondaryText,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 7),
              QestoHeroMoney(
                formatMoney(data.totalBalance, data.baseCurrency),
                large: false,
              ),
              const SizedBox(height: 6),
              Text(
                data.change == null
                    ? 'Недостаточно истории для сравнения'
                    : '${data.change! >= 0 ? '+' : '−'}${formatMoney(data.change!.abs(), data.baseCurrency)} · изменение стоимости',
                style: TextStyle(
                  color: data.change == null
                      ? context.qestoColors.secondaryText
                      : data.change! >= 0
                      ? context.qestoColors.positive
                      : context.qestoColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        _HeroValue(
          label: 'В этом месяце',
          value: formatMoney(data.investedThisMonth, data.baseCurrency),
        ),
        _HeroValue(
          label: 'За 3 месяца',
          value: formatMoney(data.contributedThreeMonths, data.baseCurrency),
        ),
        _HeroValue(
          label: 'За 12 месяцев',
          value: formatMoney(data.contributedTwelveMonths, data.baseCurrency),
        ),
        _HeroValue(
          label: 'В среднем',
          value:
              '${formatMoney(data.averageMonthlyContribution, data.baseCurrency)} / мес',
        ),
      ],
    ),
  );
}

class _HeroValue extends StatelessWidget {
  const _HeroValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 145,
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
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _InvestmentValueCard extends StatelessWidget {
  const _InvestmentValueCard({
    required this.data,
    required this.period,
    required this.onPeriodChanged,
    this.title = 'Стоимость инвестиций',
  });
  final InvestmentPortfolioSnapshot data;
  final InvestmentPeriod period;
  final ValueChanged<InvestmentPeriod> onPeriodChanged;
  final String title;

  @override
  Widget build(BuildContext context) => DesktopCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DesktopAdaptiveRow(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SegmentedButton<InvestmentPeriod>(
              showSelectedIcon: false,
              segments: [
                for (final item in InvestmentPeriod.values)
                  ButtonSegment(value: item, label: Text(item.label)),
              ],
              selected: {period},
              onSelectionChanged: (value) => onPeriodChanged(value.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 210,
          child: data.history.length < 2
              ? Center(
                  child: Text(
                    'Недостаточно истории для графика',
                    style: TextStyle(color: context.qestoColors.secondaryText),
                  ),
                )
              : CustomPaint(
                  painter: _InvestmentLinePainter(
                    context.qestoColors,
                    data.history,
                    Theme.of(context).brightness,
                  ),
                  size: Size.infinite,
                ),
        ),
      ],
    ),
  );
}

class _InvestmentFlowCard extends StatelessWidget {
  const _InvestmentFlowCard({required this.data});
  final InvestmentPortfolioSnapshot data;

  @override
  Widget build(BuildContext context) => DesktopCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Пополнения по месяцам',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Отдельно от изменения стоимости портфеля',
          style: TextStyle(
            color: context.qestoColors.secondaryText.withValues(alpha: 0.9),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 155,
          child: CustomPaint(
            painter: _InvestmentBarPainter(
              context.qestoColors,
              data.monthlyContributions,
            ),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 10),
        if (data.monthlyPlan <= 0)
          const _InvestmentNote(
            icon: Icons.event_repeat_outlined,
            text: 'Ежемесячный план не установлен',
          )
        else ...[
          Row(
            children: [
              const Expanded(
                child: Text(
                  'План месяца',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${formatMoney(data.investedThisMonth, data.baseCurrency)} / ${formatMoney(data.monthlyPlan, data.baseCurrency)}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DesktopProgressBar(value: data.monthlyPlanProgress, height: 7),
          const SizedBox(height: 6),
          Text(
            data.monthlyPlanRemaining == 0
                ? 'План выполнен'
                : 'Осталось ${formatMoney(data.monthlyPlanRemaining, data.baseCurrency)}',
            style: TextStyle(
              color: context.qestoColors.secondaryText,
              fontSize: 10,
            ),
          ),
        ],
      ],
    ),
  );
}

class _InvestmentAccountCard extends StatelessWidget {
  const _InvestmentAccountCard({
    required this.insight,
    required this.onTap,
    this.freshnessDate,
  });
  final InvestmentAccountInsight insight;
  final VoidCallback onTap;
  final DateTime? freshnessDate;

  @override
  Widget build(BuildContext context) {
    final account = insight.account;
    final freshness = _freshnessLabel(
      account,
      insight.freshness,
      now: freshnessDate,
    );
    return DesktopCard(
      onTap: onTap,
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
                  Icons.show_chart_rounded,
                  color: context.qestoColors.purple,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      _investmentTypeLabel(account.type),
                      style: TextStyle(
                        color: context.qestoColors.secondaryText,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.qestoColors.secondaryText,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            formatMoney(account.currentBalance, account.currency),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            insight.change == null
                ? 'История только началась'
                : '${insight.change! >= 0 ? '+' : '−'}${formatMoney(insight.change!.abs(), account.currency)} за период',
            style: TextStyle(
              color: insight.change == null
                  ? context.qestoColors.secondaryText
                  : insight.change! >= 0
                  ? context.qestoColors.positive
                  : context.qestoColors.danger,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Icon(
                insight.freshness == InvestmentFreshness.stale
                    ? Icons.schedule_rounded
                    : Icons.check_circle_outline_rounded,
                size: 15,
                color: insight.freshness == InvestmentFreshness.stale
                    ? context.qestoColors.warning
                    : context.qestoColors.secondaryText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  freshness,
                  style: TextStyle(
                    color: context.qestoColors.secondaryText,
                    fontSize: 10,
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

class _InvestmentMetric extends StatelessWidget {
  const _InvestmentMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 245,
    child: DesktopCard(
      child: Row(
        children: [
          Icon(icon, color: accent ?? context.qestoColors.primary),
          const SizedBox(width: 11),
          Expanded(
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
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

class _InvestmentHistoryCard extends StatelessWidget {
  const _InvestmentHistoryCard({
    required this.title,
    required this.emptyText,
    required this.children,
    this.action,
  });
  final String title;
  final String emptyText;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) => DesktopCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ...action == null ? const <Widget>[] : <Widget>[action!],
          ],
        ),
        const SizedBox(height: 12),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
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

class _InvestmentHistoryRow extends StatelessWidget {
  const _InvestmentHistoryRow({
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
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
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

class _InvestmentNote extends StatelessWidget {
  const _InvestmentNote({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.qestoColors.primarySoft.withValues(alpha: 0.45),
      borderRadius: QestoGeometry.control,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: context.qestoColors.primary),
        const SizedBox(width: 9),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 11, height: 1.4)),
        ),
      ],
    ),
  );
}

class _InvestmentLinePainter extends CustomPainter {
  final QestoSemanticColors c;
  _InvestmentLinePainter(this.c, this.points, this.brightness);
  final List<InvestmentBalancePoint> points;
  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final values = points.map((item) => item.balance.toDouble()).toList();
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final range = math.max(1, maxValue - minValue);
    const top = 12.0;
    final bottom = size.height - 18;
    final line = Path();
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? 0.0
          : size.width * index / (values.length - 1);
      final y = bottom - (values[index] - minValue) / range * (bottom - top);
      if (index == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
    }
    final fill = Path.from(line)
      ..lineTo(size.width, bottom)
      ..lineTo(0, bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            c.primary.withValues(alpha: 0.24),
            c.primary.withValues(alpha: 0.01),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = c.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final gridColor = brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.07)
        : c.border.withValues(alpha: 0.7);
    for (var index = 0; index < 4; index++) {
      final y = top + (bottom - top) * index / 3;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = gridColor
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _InvestmentLinePainter oldDelegate) =>
      oldDelegate.c != c ||
      oldDelegate.points != points ||
      oldDelegate.brightness != brightness;
}

class _InvestmentBarPainter extends CustomPainter {
  final QestoSemanticColors c;
  _InvestmentBarPainter(this.c, this.values);
  final List<InvestmentMonthlyContribution> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = values
        .map((item) => item.contributions.toDouble())
        .fold<double>(1, math.max);
    final slot = size.width / values.length;
    final width = math.max(4, slot * 0.48);
    for (var index = 0; index < values.length; index++) {
      final value = values[index].contributions;
      final height = value <= 0 ? 2.0 : (size.height - 18) * value / maxValue;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          slot * index + (slot - width) / 2,
          size.height - height,
          width.toDouble(),
          height,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = value <= 0 ? c.border : c.purple.withValues(alpha: 0.82),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _InvestmentBarPainter oldDelegate) =>
      oldDelegate.c != c || oldDelegate.values != values;
}

String _investmentTypeLabel(InvestmentAccountType type) => switch (type) {
  InvestmentAccountType.brokerage => 'Брокерский счёт',
  InvestmentAccountType.iis => 'ИИС',
  InvestmentAccountType.pension => 'Пенсионный счёт',
  InvestmentAccountType.crypto => 'Криптоактивы',
  InvestmentAccountType.other => 'Другой инвестиционный счёт',
};

String _investmentStatusLabel(InvestmentAccountStatus status) =>
    switch (status) {
      InvestmentAccountStatus.active => 'Активен',
      InvestmentAccountStatus.closed => 'Закрыт',
      InvestmentAccountStatus.archived => 'В архиве',
    };

String _investmentSourceLabel(InvestmentDataSource source) => switch (source) {
  InvestmentDataSource.manual => 'вручную',
  InvestmentDataSource.api => 'API',
  InvestmentDataSource.brokerStatement => 'отчёт брокера',
  InvestmentDataSource.calculated => 'импортировано',
  InvestmentDataSource.transaction => 'транзакция',
};

String _freshnessLabel(
  InvestmentAccount account,
  InvestmentFreshness freshness, {
  DateTime? now,
}) {
  final days = (now ?? DateTime.now())
      .difference(
        DateTime(
          account.lastBalanceUpdateAt.year,
          account.lastBalanceUpdateAt.month,
          account.lastBalanceUpdateAt.day,
        ),
      )
      .inDays;
  if (days <= 0) return 'Обновлено сегодня';
  if (freshness == InvestmentFreshness.stale) {
    return 'Обновлено $days дн. назад · стоимость может устареть';
  }
  return 'Обновлено $days дн. назад';
}
