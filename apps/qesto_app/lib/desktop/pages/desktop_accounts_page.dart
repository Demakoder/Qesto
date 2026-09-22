import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/capital/domain/account_capital_service.dart';
import '../desktop_financial_helpers.dart';
import '../widgets/desktop_charts.dart';
import '../widgets/desktop_components.dart';

class DesktopAccountsPage extends StatefulWidget {
  const DesktopAccountsPage({required this.controller, super.key});

  final BudgetController controller;

  @override
  State<DesktopAccountsPage> createState() => _DesktopAccountsPageState();
}

class _DesktopAccountsPageState extends State<DesktopAccountsPage> {
  static const _service = AccountCapitalService();

  CapitalPeriod _period = CapitalPeriod.oneMonth;
  String? _openedAccountId;
  bool _showHidden = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final data = _service.calculate(
          accounts: widget.controller.accounts,
          accountPreferences: widget.controller.accountPreferences,
          transactions: widget.controller.transactions,
          upcomingExpenses: widget.controller.upcomingExpenses,
          savingsGoals: widget.controller.savingsGoals,
          goalAllocations: widget.controller.goalAllocations,
          debts: widget.controller.debts,
          synoballState: widget.controller.synoballState,
          asOf: widget.controller.referenceDate,
          period: _period,
          baseCurrency: widget.controller.user.defaultCurrency,
        );
        if (data.accounts.isEmpty) {
          return _EmptyAccounts(
            onAdd: () => _showAddAccount(context),
            hasNonLiquidAccounts: data.excludedNonLiquidAccounts > 0,
          );
        }
        final opened = data.accounts
            .where((item) => item.account.id == _openedAccountId)
            .firstOrNull;
        return Padding(
          padding: QestoSpacing.workspace(context),
          child: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LiquidityCard(
                        data: data,
                        period: _period,
                        onPeriodChanged: (value) =>
                            setState(() => _period = value),
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final vertical = constraints.maxWidth < 920;
                          if (vertical) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _EmergencyFundCard(
                                  data: data,
                                  onEditGoal: () =>
                                      _showEmergencyGoal(context, data),
                                ),
                                const SizedBox(height: 16),
                                _ForecastCard(data: data),
                              ],
                            );
                          }
                          return IntrinsicHeight(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _EmergencyFundCard(
                                    data: data,
                                    onEditGoal: () =>
                                        _showEmergencyGoal(context, data),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(child: _ForecastCard(data: data)),
                              ],
                            ),
                          );
                        },
                      ),
                      if (data.lowBalanceRisk == LowBalanceRisk.attention ||
                          data.lowBalanceRisk == LowBalanceRisk.critical) ...[
                        const SizedBox(height: 16),
                        _LowBalanceInsight(data: data),
                      ],
                      const SizedBox(height: 24),
                      _AccountsHeader(
                        data: data,
                        showHidden: _showHidden,
                        onToggleHidden: () =>
                            setState(() => _showHidden = !_showHidden),
                        onAdd: () => _showAddAccount(context),
                      ),
                      const SizedBox(height: 12),
                      _AccountGrid(
                        data: data,
                        showHidden: _showHidden,
                        onOpen: (id) => setState(() => _openedAccountId = id),
                      ),
                      if (data.excludedNonLiquidAccounts > 0) ...[
                        const SizedBox(height: 13),
                        _ExcludedCapitalNote(
                          count: data.excludedNonLiquidAccounts,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (opened != null)
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: math.min(440, MediaQuery.sizeOf(context).width),
                  child: _AccountDrawer(
                    controller: widget.controller,
                    insight: opened,
                    baseCurrency: data.baseCurrency,
                    period: _period,
                    onClose: () => setState(() => _openedAccountId = null),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddAccount(BuildContext context) async {
    final name = TextEditingController();
    final balance = TextEditingController();
    var type = AccountType.bankCard;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Добавить денежный счёт'),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('account-name-field'),
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('account-balance-field'),
                  controller: balance,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^-?[0-9]*')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Текущий остаток',
                    suffixText: widget.controller.user.defaultCurrency,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AccountType>(
                  key: const Key('account-type-field'),
                  isExpanded: true,
                  initialValue: type,
                  items: const [
                    DropdownMenuItem(
                      value: AccountType.bankCard,
                      child: Text('Карта или текущий счёт'),
                    ),
                    DropdownMenuItem(
                      value: AccountType.savings,
                      child: Text('Накопительный счёт'),
                    ),
                    DropdownMenuItem(
                      value: AccountType.deposit,
                      child: Text('Ликвидный вклад'),
                    ),
                    DropdownMenuItem(
                      value: AccountType.cash,
                      child: Text('Наличные'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => type = value);
                  },
                  decoration: const InputDecoration(labelText: 'Тип'),
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
              key: const Key('account-add-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    if (result == true && name.text.trim().isNotEmpty) {
      await widget.controller.addAccount(
        title: name.text.trim(),
        balance: int.tryParse(balance.text) ?? 0,
        type: type,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    name.dispose();
    balance.dispose();
  }

  Future<void> _showEmergencyGoal(
    BuildContext context,
    AccountCapitalSnapshot data,
  ) async {
    final goal = data.emergencyGoal;
    final target = TextEditingController(
      text:
          goal?.targetAmount.toString() ??
          (data.averageEssentialMonthlyExpenses == null
              ? ''
              : (data.averageEssentialMonthlyExpenses! * 6).toString()),
    );
    var months = data.averageEssentialMonthlyExpenses == null || goal == null
        ? 6
        : (goal.targetAmount / data.averageEssentialMonthlyExpenses!)
              .round()
              .clamp(1, 60);
    final selected = <String>{
      for (final item in data.accounts)
        if (item.preferences.includeInEmergencyFund) item.account.id,
    };
    String? error;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          key: const Key('emergency-goal-dialog'),
          title: const Text('Цель финансовой подушки'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Сколько месяцев базовых расходов вы хотите держать в запасе?',
                    style: TextStyle(color: context.qestoColors.secondaryText),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final value in const [3, 6, 9, 12])
                        ChoiceChip(
                          label: Text('$value мес.'),
                          selected: months == value,
                          onSelected: (_) {
                            setDialogState(() {
                              months = value;
                              final monthly =
                                  data.averageEssentialMonthlyExpenses;
                              if (monthly != null) {
                                target.text = (monthly * value).toString();
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('emergency-target-field'),
                    controller: target,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Сумма цели',
                      suffixText: data.baseCurrency,
                      helperText: data.averageEssentialMonthlyExpenses == null
                          ? 'Истории базовых расходов пока недостаточно — укажите сумму вручную'
                          : 'Средние базовые расходы: ${formatMoney(data.averageEssentialMonthlyExpenses!, data.baseCurrency)} в месяц',
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Какие счета входят в подушку',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  for (final item in data.accounts)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.account.title),
                      subtitle: Text(
                        formatMoney(
                          item.account.balance,
                          item.account.currency,
                        ),
                      ),
                      value: selected.contains(item.account.id),
                      onChanged: (value) => setDialogState(() {
                        if (value == true) {
                          selected.add(item.account.id);
                        } else {
                          selected.remove(item.account.id);
                        }
                      }),
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
              key: const Key('emergency-goal-save'),
              onPressed: () {
                final amount = int.tryParse(target.text) ?? 0;
                if (amount <= 0 || selected.isEmpty) {
                  setDialogState(() {
                    error = amount <= 0
                        ? 'Укажите сумму цели больше нуля'
                        : 'Выберите хотя бы один счёт подушки';
                  });
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Сохранить цель'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      for (final item in data.accounts) {
        final shouldInclude = selected.contains(item.account.id);
        if (item.preferences.includeInEmergencyFund != shouldInclude) {
          await widget.controller.updateAccountPreferences(
            item.preferences.copyWith(includeInEmergencyFund: shouldInclude),
          );
        }
      }
      final amount = int.parse(target.text);
      if (goal == null) {
        await widget.controller.addSavingsGoal(
          title: 'Подушка безопасности',
          category: 'Финансовая подушка',
          targetAmount: amount,
          savedAmount: math.min(data.emergencyFundAmount, amount),
          targetDate: DateTime.now().add(const Duration(days: 365)),
          currency: data.baseCurrency,
        );
      } else {
        await widget.controller.updateSavingsGoal(
          goal.copyWith(
            targetAmount: amount,
            savedAmount: math.min(data.emergencyFundAmount, amount),
          ),
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    target.dispose();
  }
}

class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts({
    required this.onAdd,
    required this.hasNonLiquidAccounts,
  });

  final VoidCallback onAdd;
  final bool hasNonLiquidAccounts;

  @override
  Widget build(BuildContext context) => DesktopEmptyState(
    title: 'Денежных счетов пока нет',
    message: hasNonLiquidAccounts
        ? 'Инвестиции и долги не входят в этот раздел. Добавьте карту, накопительный счёт, вклад или наличные.'
        : 'Подключите банк или добавьте ручной счёт, чтобы увидеть ликвидный остаток и запас денег.',
    icon: Icons.account_balance_wallet_outlined,
    action: FilledButton.icon(
      onPressed: onAdd,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Добавить счёт'),
    ),
  );
}

class _LiquidityCard extends StatelessWidget {
  const _LiquidityCard({
    required this.data,
    required this.period,
    required this.onPeriodChanged,
  });

  final AccountCapitalSnapshot data;
  final CapitalPeriod period;
  final ValueChanged<CapitalPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) => DesktopCard(
    padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Деньги на счетах',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatMoney(data.totalLiquidAssets, data.baseCurrency),
                    key: const Key('total-liquid-assets'),
                    style: context.qestoTypography.display(
                      const TextStyle(
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                      numeric: true,
                    ),
                  ),
                  const SizedBox(height: 9),
                  _TrendLabel(
                    amount: data.change,
                    percent: data.changePercent,
                    currency: data.baseCurrency,
                    suffix: 'за период',
                  ),
                ],
              ),
            ),
            _PeriodSelector(value: period, onChanged: onPeriodChanged),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 190,
          child: data.history.length < 2
              ? const _ChartEmptyState()
              : _BalanceChart(
                  points: data.history,
                  currency: data.baseCurrency,
                ),
        ),
        const SizedBox(height: 12),
        DesktopAdaptiveRow(
          children: [
            DesktopPill(
              label: data.isHistoryReconstructed
                  ? 'История рассчитана по операциям'
                  : 'Недостаточно истории',
              icon: data.isHistoryReconstructed
                  ? Icons.calculate_outlined
                  : Icons.info_outline_rounded,
              color: data.isHistoryReconstructed
                  ? context.qestoColors.info
                  : context.qestoColors.secondaryText,
            ),
            if (data.hasUnconvertedCurrencies) ...[
              const SizedBox(width: 8),
              DesktopPill(
                label: 'Часть валют не пересчитана',
                icon: Icons.currency_exchange_rounded,
                color: context.qestoColors.warning,
              ),
            ],
            const Spacer(),
            if (data.averageDailyBalance case final value?)
              Text(
                'Средний остаток ${formatMoney(value, data.baseCurrency)}',
                style: TextStyle(
                  color: context.qestoColors.secondaryText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        if (data.distribution.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 16),
          _Distribution(data: data),
        ],
      ],
    ),
  );
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.value, required this.onChanged});

  final CapitalPeriod value;
  final ValueChanged<CapitalPeriod> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: context.qestoColors.surfaceSecondary,
      borderRadius: QestoGeometry.control,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in CapitalPeriod.values)
          InkWell(
            key: Key('capital-period-${item.name}'),
            onTap: () => onChanged(item),
            borderRadius: QestoGeometry.control,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: item == value
                    ? context.qestoColors.surface
                    : Colors.transparent,
                borderRadius: QestoGeometry.control,
                boxShadow: item == value
                    ? const [
                        BoxShadow(
                          color: Color(0x0D000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                item.label,
                style: TextStyle(
                  color: item == value
                      ? context.qestoColors.text
                      : context.qestoColors.secondaryText,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Distribution extends StatelessWidget {
  const _Distribution({required this.data});

  final AccountCapitalSnapshot data;

  @override
  Widget build(BuildContext context) {
    final denominator = math.max(
      1,
      data.distribution.fold<int>(0, (sum, item) => sum + item.amount.abs()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Как распределены деньги',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 9,
            child: Row(
              children: [
                for (final item in data.distribution)
                  Expanded(
                    flex: math.max(
                      1,
                      (item.amount.abs() / denominator * 1000).round(),
                    ),
                    child: ColoredBox(color: Color(item.colorValue)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 22,
          runSpacing: 10,
          children: [
            for (final item in data.distribution)
              _DistributionLegend(
                item: item,
                total: denominator,
                currency: data.baseCurrency,
              ),
          ],
        ),
      ],
    );
  }
}

class _DistributionLegend extends StatelessWidget {
  const _DistributionLegend({
    required this.item,
    required this.total,
    required this.currency,
  });

  final AccountDistributionItem item;
  final int total;
  final String currency;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Color(item.colorValue),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 7),
      Text(
        '${item.label}  ${formatMoney(item.amount, currency)} · ${(item.amount.abs() / total * 100).round()}%',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _EmergencyFundCard extends StatelessWidget {
  const _EmergencyFundCard({required this.data, required this.onEditGoal});

  final AccountCapitalSnapshot data;
  final VoidCallback onEditGoal;

  @override
  Widget build(BuildContext context) {
    final goal = data.emergencyGoal;
    final progress = goal == null || goal.targetAmount <= 0
        ? null
        : (data.emergencyFundAmount / goal.targetAmount).clamp(0.0, 1.0);
    final missing = goal == null
        ? null
        : math.max(0, goal.targetAmount - data.emergencyFundAmount);
    return DesktopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: context.qestoColors.primarySoft,
                  borderRadius: QestoGeometry.control,
                ),
                child: Icon(
                  Icons.health_and_safety_outlined,
                  color: context.qestoColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  'Подушка безопасности',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                key: const Key('emergency-goal-button'),
                onPressed: onEditGoal,
                icon: Icon(
                  goal == null ? Icons.add_rounded : Icons.tune_rounded,
                  size: 16,
                ),
                label: Text(goal == null ? 'Цель' : 'Изменить цель'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            data.emergencyAccountCount == 0
                ? 'Счета не выбраны'
                : formatMoney(data.emergencyFundAmount, data.baseCurrency),
            key: const Key('emergency-fund-amount'),
            style: context.qestoTypography.display(
              const TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
              numeric: true,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.emergencyAccountCount == 0
                ? 'Выберите счета, которые составляют резерв'
                : data.emergencyFundMonths == null
                ? 'Недостаточно истории базовых расходов'
                : '${_decimal(data.emergencyFundMonths!)} месяца базовых расходов',
            style: TextStyle(
              color: context.qestoColors.secondaryText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),
          if (goal == null)
            Text(
              'Назначьте цель и выберите счета, которые составляют ваш резерв.',
              style: TextStyle(
                color: context.qestoColors.secondaryText,
                fontSize: 11,
                height: 1.45,
              ),
            )
          else ...[
            DesktopProgressBar(
              value: progress!,
              color: context.qestoColors.positive,
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: Text(
                    missing == 0
                        ? 'Подушка сформирована'
                        : 'Не хватает ${formatMoney(missing!, data.baseCurrency)}',
                    style: TextStyle(
                      color: missing == 0
                          ? context.qestoColors.positive
                          : context.qestoColors.secondaryText,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'цель ${formatMoney(goal.targetAmount, goal.currency)}',
                  style: TextStyle(
                    color: context.qestoColors.secondaryText,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.data});

  final AccountCapitalSnapshot data;

  @override
  Widget build(BuildContext context) => DesktopCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopAdaptiveRow(
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 20,
              color: context.qestoColors.purple,
            ),
            SizedBox(width: 9),
            Text(
              'До следующего дохода',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _SmallMoneyStat(
                label: 'На счетах',
                amount: data.totalLiquidAssets,
                currency: data.baseCurrency,
              ),
            ),
            Expanded(
              child: _SmallMoneyStat(
                label: 'Зарезервировано',
                amount: data.reservedCash,
                currency: data.baseCurrency,
                color: context.qestoColors.warning,
              ),
            ),
            Expanded(
              child: _SmallMoneyStat(
                label: 'Свободно',
                amount: data.availableCash,
                currency: data.baseCurrency,
                color: data.availableCash < 0
                    ? context.qestoColors.danger
                    : context.qestoColors.positive,
              ),
            ),
          ],
        ),
        const SizedBox(height: 17),
        if (data.debtPaymentsReserved > 0) ...[
          Text(
            'В резерв включено ${formatMoney(data.debtPaymentsReserved, data.baseCurrency)} обязательных платежей по долгам.',
            style: TextStyle(
              color: context.qestoColors.secondaryText,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 12),
        ],
        const Divider(height: 1),
        const SizedBox(height: 14),
        if (data.nextExpectedIncome case final income?) ...[
          Text(
            'Ожидаемый доход: ${formatDate(income.date, includeYear: true)}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '${income.title} · около ${formatMoney(income.amount, data.baseCurrency)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: context.qestoColors.secondaryText,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            data.minimumProjectedBalance == null
                ? 'Недостаточно истории для прогноза остатка'
                : 'Ожидаемый минимум: ${formatMoney(data.minimumProjectedBalance!, data.baseCurrency)}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ] else
          Text(
            'Недостаточно повторяющейся истории, чтобы надёжно определить следующий доход.',
            style: TextStyle(
              color: context.qestoColors.secondaryText,
              fontSize: 11,
              height: 1.45,
            ),
          ),
      ],
    ),
  );
}

class _SmallMoneyStat extends StatelessWidget {
  const _SmallMoneyStat({
    required this.label,
    required this.amount,
    required this.currency,
    this.color,
  });

  final String label;
  final int amount;
  final String currency;
  final Color? color;

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
      const SizedBox(height: 5),
      Text(
        formatMoney(amount, currency),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: color ?? context.qestoColors.text,
        ),
      ),
    ],
  );
}

class _LowBalanceInsight extends StatelessWidget {
  const _LowBalanceInsight({required this.data});

  final AccountCapitalSnapshot data;

  @override
  Widget build(BuildContext context) {
    final critical = data.lowBalanceRisk == LowBalanceRisk.critical;
    final color = critical
        ? context.qestoColors.danger
        : context.qestoColors.warning;
    return DesktopCard(
      color: color.withValues(alpha: 0.055),
      borderColor: color.withValues(alpha: 0.2),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Icon(Icons.water_drop_outlined, color: color, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  critical
                      ? 'Возможен критически низкий остаток'
                      : 'Остаток может стать ниже обычного',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'До следующего ожидаемого дохода прогнозируется около ${formatMoney(data.minimumProjectedBalance ?? 0, data.baseCurrency)}. Расчёт основан на вашем среднем дневном расходе.',
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
    );
  }
}

class _AccountsHeader extends StatelessWidget {
  const _AccountsHeader({
    required this.data,
    required this.showHidden,
    required this.onToggleHidden,
    required this.onAdd,
  });

  final AccountCapitalSnapshot data;
  final bool showHidden;
  final VoidCallback onToggleHidden;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final hidden = data.accounts
        .where(
          (item) => !item.preferences.isVisible || item.preferences.isClosed,
        )
        .length;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ваши счета',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 3),
              Text(
                'Карты, накопительные счета, вклады и наличные',
                style: TextStyle(
                  color: context.qestoColors.secondaryText,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (hidden > 0)
          TextButton.icon(
            key: const Key('toggle-hidden-accounts'),
            onPressed: onToggleHidden,
            icon: Icon(
              showHidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 17,
            ),
            label: Text(showHidden ? 'Скрыть архив' : 'Скрытые ($hidden)'),
          ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Добавить счёт'),
        ),
      ],
    );
  }
}

class _AccountGrid extends StatelessWidget {
  const _AccountGrid({
    required this.data,
    required this.showHidden,
    required this.onOpen,
  });

  final AccountCapitalSnapshot data;
  final bool showHidden;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final accounts = data.accounts
        .where(
          (item) =>
              showHidden ||
              (item.preferences.isVisible && !item.preferences.isClosed),
        )
        .toList();
    if (accounts.isEmpty) {
      return DesktopCard(
        child: Text(
          showHidden
              ? 'Счетов в архиве нет'
              : 'Все счета скрыты. Откройте архив, чтобы изменить настройки.',
          style: TextStyle(color: context.qestoColors.secondaryText),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1120
            ? 3
            : constraints.maxWidth > 700
            ? 2
            : 1;
        const gap = 13.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in accounts)
              SizedBox(
                width: width,
                height: 215,
                child: _AccountCard(
                  insight: item,
                  baseCurrency: data.baseCurrency,
                  onTap: () => onOpen(item.account.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.insight,
    required this.baseCurrency,
    required this.onTap,
  });

  final AccountCapitalAccountInsight insight;
  final String baseCurrency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final account = insight.account;
    return DesktopCard(
      onTap: onTap,
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _accountColor(
                    context.qestoColors,
                    account.type,
                  ).withValues(alpha: 0.1),
                  borderRadius: QestoGeometry.control,
                ),
                child: Icon(
                  _accountIcon(account.type),
                  size: 18,
                  color: _accountColor(context.qestoColors, account.type),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_typeLabel(account.type)} · ${account.currency}',
                      style: TextStyle(
                        color: context.qestoColors.secondaryText,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: context.qestoColors.secondaryText,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            formatMoney(account.balance, account.currency),
            style: context.qestoTypography.display(
              TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: account.balance < 0
                    ? context.qestoColors.negative
                    : context.qestoColors.text,
              ),
              numeric: true,
            ),
          ),
          const SizedBox(height: 5),
          _TrendLabel(
            amount: insight.change,
            percent: insight.changePercent,
            currency: baseCurrency,
            suffix: 'за период',
            compact: true,
          ),
          const Spacer(),
          SizedBox(
            height: 26,
            child: insight.history.length < 2
                ? const SizedBox.shrink()
                : DesktopSparkline(
                    values: insight.history
                        .map((item) => item.balance.toDouble())
                        .toList(),
                    color: insight.change != null && insight.change! < 0
                        ? context.qestoColors.danger
                        : context.qestoColors.primary,
                  ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              _StatusDot(status: insight.status),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _freshnessLabel(insight.status, insight.lastUpdatedAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.qestoColors.secondaryText,
                    fontSize: 9,
                  ),
                ),
              ),
              Text(
                _roleLabel(insight.preferences.role),
                style: TextStyle(
                  color: context.qestoColors.secondaryText,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExcludedCapitalNote extends StatelessWidget {
  const _ExcludedCapitalNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: context.qestoColors.surfaceSecondary,
      borderRadius: QestoGeometry.control,
    ),
    child: DesktopAdaptiveRow(
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 17,
          color: context.qestoColors.secondaryText,
        ),
        const SizedBox(width: 8),
        Text(
          '$count ${_plural(count, 'объект капитала исключён', 'объекта капитала исключены', 'объектов капитала исключены')} из этой суммы: инвестиции и долги учитываются отдельно.',
          style: TextStyle(
            color: context.qestoColors.secondaryText,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}

class _AccountDrawer extends StatelessWidget {
  const _AccountDrawer({
    required this.controller,
    required this.insight,
    required this.baseCurrency,
    required this.period,
    required this.onClose,
  });

  final BudgetController controller;
  final AccountCapitalAccountInsight insight;
  final String baseCurrency;
  final CapitalPeriod period;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final account = insight.account;
    return Material(
      elevation: 18,
      color: context.qestoColors.surface,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 60,
            child: Row(
              children: [
                const SizedBox(width: 20),
                const Expanded(
                  child: Text(
                    'Детали счёта',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _accountColor(
                          context.qestoColors,
                          account.type,
                        ).withValues(alpha: 0.1),
                        borderRadius: QestoGeometry.control,
                      ),
                      child: Icon(
                        _accountIcon(account.type),
                        color: _accountColor(context.qestoColors, account.type),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account.title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_typeLabel(account.type)} · ${account.currency}',
                            style: TextStyle(
                              color: context.qestoColors.secondaryText,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  formatMoney(account.balance, account.currency),
                  style: context.qestoTypography.display(
                    const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                    numeric: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _StatusDot(status: insight.status),
                    const SizedBox(width: 6),
                    Text(
                      _freshnessLabel(insight.status, insight.lastUpdatedAt),
                      style: TextStyle(
                        color: context.qestoColors.secondaryText,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                DesktopCard(
                  color: context.qestoColors.surfaceSecondary,
                  borderColor: Colors.transparent,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            'История · ${period.label}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          if (insight.isHistoryReconstructed)
                            DesktopPill(
                              label: 'Расчётно',
                              icon: Icons.calculate_outlined,
                              color: context.qestoColors.info,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 90,
                        child: insight.history.length < 2
                            ? const _ChartEmptyState(compact: true)
                            : _BalanceChart(
                                points: insight.history,
                                currency: baseCurrency,
                                compact: true,
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _FlowGrid(insight: insight, currency: baseCurrency),
                if (insight.minimumBalance != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MetricLine(
                          label: 'Минимальный остаток',
                          value: formatMoney(
                            insight.minimumBalance!,
                            baseCurrency,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MetricLine(
                          label: 'Максимальный остаток',
                          value: formatMoney(
                            insight.maximumBalance!,
                            baseCurrency,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                const Text(
                  'Роль и настройки',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<QestoAccountRole>(
                  key: Key('account-role-${account.id}'),
                  initialValue: insight.preferences.role,
                  decoration: const InputDecoration(labelText: 'Роль счёта'),
                  items: [
                    for (final role in QestoAccountRole.values)
                      DropdownMenuItem(
                        value: role,
                        child: Text(_roleLabel(role)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      controller.updateAccountPreferences(
                        insight.preferences.copyWith(role: value),
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                _AccountSettingSwitch(
                  title: 'Включать в сумму счетов',
                  value: insight.preferences.includeInTotal,
                  onChanged: (value) => controller.updateAccountPreferences(
                    insight.preferences.copyWith(includeInTotal: value),
                  ),
                ),
                _AccountSettingSwitch(
                  title: 'Включать в чистый капитал',
                  value: insight.preferences.includeInNetWorth,
                  onChanged: (value) => controller.updateAccountPreferences(
                    insight.preferences.copyWith(includeInNetWorth: value),
                  ),
                ),
                _AccountSettingSwitch(
                  title: 'Включать в финансовую подушку',
                  value: insight.preferences.includeInEmergencyFund,
                  onChanged: (value) => controller.updateAccountPreferences(
                    insight.preferences.copyWith(includeInEmergencyFund: value),
                  ),
                ),
                _AccountSettingSwitch(
                  title: 'Показывать в списке',
                  value: insight.preferences.isVisible,
                  onChanged: (value) => controller.updateAccountPreferences(
                    insight.preferences.copyWith(isVisible: value),
                  ),
                ),
                _AccountSettingSwitch(
                  title: 'Учитывать операции в аналитике',
                  value: insight.preferences.includeTransactionsInAnalytics,
                  onChanged: (value) => controller.updateAccountPreferences(
                    insight.preferences.copyWith(
                      includeTransactionsInAnalytics: value,
                    ),
                  ),
                ),
                _AccountSettingSwitch(
                  title: 'Счёт закрыт',
                  value: insight.preferences.isClosed,
                  onChanged: (value) => controller.updateAccountPreferences(
                    insight.preferences.copyWith(isClosed: value),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Последние операции',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${insight.transactions.length}',
                      style: TextStyle(
                        color: context.qestoColors.secondaryText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (insight.transactions.isEmpty)
                  Text(
                    'Операций по этому счёту пока нет',
                    style: TextStyle(
                      color: context.qestoColors.secondaryText,
                      fontSize: 11,
                    ),
                  )
                else
                  for (final transaction in insight.transactions.take(8))
                    _DrawerTransaction(transaction: transaction),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowGrid extends StatelessWidget {
  const _FlowGrid({required this.insight, required this.currency});

  final AccountCapitalAccountInsight insight;
  final String currency;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 9,
    runSpacing: 9,
    children: [
      _FlowMetric(
        label: 'Получено',
        amount: insight.inflow,
        currency: currency,
        color: context.qestoColors.positive,
      ),
      _FlowMetric(
        label: 'Потрачено',
        amount: -insight.outflow,
        currency: currency,
        color: context.qestoColors.danger,
      ),
      _FlowMetric(
        label: 'Свои счета',
        amount: insight.internalTransfers,
        currency: currency,
        color: context.qestoColors.info,
      ),
      _FlowMetric(
        label: 'Изменение',
        amount: insight.netChange,
        currency: currency,
        color: insight.netChange < 0
            ? context.qestoColors.danger
            : context.qestoColors.positive,
      ),
    ],
  );
}

class _FlowMetric extends StatelessWidget {
  const _FlowMetric({
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
  });

  final String label;
  final int amount;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 191,
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: context.qestoColors.surfaceSecondary,
      borderRadius: QestoGeometry.control,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.qestoColors.secondaryText,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          formatMoney(amount, currency, showSign: true),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(color: context.qestoColors.secondaryText, fontSize: 9),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _AccountSettingSwitch extends StatelessWidget {
  const _AccountSettingSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(
      title,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    ),
    value: value,
    onChanged: onChanged,
  );
}

class _DrawerTransaction extends StatelessWidget {
  const _DrawerTransaction({required this.transaction});

  final BudgetTransaction transaction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: context.qestoColors.surfaceSecondary,
            borderRadius: QestoGeometry.control,
          ),
          child: Icon(
            Icons.receipt_long_outlined,
            size: 15,
            color: context.qestoColors.secondaryText,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                desktopTransactionTitle(transaction),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatDate(transaction.date, includeYear: true),
                style: TextStyle(
                  color: context.qestoColors.secondaryText,
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ),
        Text(
          formatMoney(
            desktopSignedAmount(transaction),
            transaction.currency,
            showSign: true,
          ),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: desktopAmountColor(transaction, colors: context.qestoColors),
          ),
        ),
      ],
    ),
  );
}

class _TrendLabel extends StatelessWidget {
  const _TrendLabel({
    required this.amount,
    required this.percent,
    required this.currency,
    required this.suffix,
    this.compact = false,
  });

  final int? amount;
  final double? percent;
  final String currency;
  final String suffix;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (amount == null) {
      return Text(
        'Недостаточно истории для сравнения',
        style: TextStyle(
          color: context.qestoColors.secondaryText,
          fontSize: compact ? 9 : 11,
        ),
      );
    }
    final color = amount! < 0
        ? context.qestoColors.danger
        : amount! > 0
        ? context.qestoColors.positive
        : context.qestoColors.secondaryText;
    final percentage = percent == null
        ? ''
        : ' · ${percent! >= 0 ? '+' : ''}${percent!.toStringAsFixed(1)}%';
    return Text(
      '${formatMoney(amount!, currency, showSign: true)}$percentage $suffix',
      style: TextStyle(
        color: color,
        fontSize: compact ? 9 : 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final AccountDataStatus status;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: switch (status) {
        AccountDataStatus.current => context.qestoColors.positive,
        AccountDataStatus.needsUpdate => context.qestoColors.warning,
        AccountDataStatus.partial => context.qestoColors.warning,
        AccountDataStatus.manual => context.qestoColors.info,
      },
    ),
  );
}

class _ChartEmptyState extends StatelessWidget {
  const _ChartEmptyState({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      'История появится после новых операций или снимков баланса',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: context.qestoColors.secondaryText,
        fontSize: compact ? 9 : 11,
      ),
    ),
  );
}

class _BalanceChart extends StatefulWidget {
  const _BalanceChart({
    required this.points,
    required this.currency,
    this.compact = false,
  });

  final List<AccountBalancePoint> points;
  final String currency;
  final bool compact;

  @override
  State<_BalanceChart> createState() => _BalanceChartState();
}

class _BalanceChartState extends State<_BalanceChart> {
  int? _hovered;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return MouseRegion(
        onExit: (_) => setState(() => _hovered = null),
        onHover: (event) {
          final count = widget.points.length;
          if (count < 2) return;
          final ratio =
              (event.localPosition.dx / math.max(1, constraints.maxWidth))
                  .clamp(0.0, 1.0);
          final value = (ratio * (count - 1)).round();
          if (value != _hovered) setState(() => _hovered = value);
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _BalancePainter(
                  c: context.qestoColors,
                  points: widget.points,
                  hovered: _hovered,
                  compact: widget.compact,
                ),
              ),
            ),
            if (_hovered case final index?)
              Positioned(
                left: _tooltipLeft(index, constraints.maxWidth),
                top: widget.compact ? 2 : 8,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF171B1E),
                      borderRadius: QestoGeometry.control,
                    ),
                    child: Text(
                      '${formatDate(widget.points[index].date)} · ${formatMoney(widget.points[index].balance, widget.currency)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  double _tooltipLeft(int index, double width) {
    final ratio = index / math.max(1, widget.points.length - 1);
    return (ratio * width - 62).clamp(0, math.max(0, width - 150));
  }
}

class _BalancePainter extends CustomPainter {
  final QestoSemanticColors c;
  const _BalancePainter({
    required this.c,
    required this.points,
    required this.hovered,
    required this.compact,
  });

  final List<AccountBalancePoint> points;
  final int? hovered;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final values = points.map((item) => item.balance.toDouble()).toList();
    var minimum = values.reduce(math.min);
    var maximum = values.reduce(math.max);
    if (minimum == maximum) {
      minimum -= 1;
      maximum += 1;
    }
    final padding = compact ? 5.0 : 12.0;
    final rect = Rect.fromLTRB(
      padding,
      padding,
      size.width - padding,
      size.height - padding,
    );
    if (!compact) {
      final grid = Paint()..color = c.border;
      for (var index = 0; index < 4; index++) {
        final y = rect.top + rect.height * index / 3;
        canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
      }
    }
    Offset pointAt(int index) {
      final x = rect.left + rect.width * index / (points.length - 1);
      final normalized = (values[index] - minimum) / (maximum - minimum);
      return Offset(x, rect.bottom - rect.height * normalized);
    }

    final first = pointAt(0);
    final line = Path()..moveTo(first.dx, first.dy);
    for (var index = 1; index < points.length; index++) {
      final point = pointAt(index);
      line.lineTo(point.dx, point.dy);
    }
    if (!compact) {
      final fill = Path.from(line)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.left, rect.bottom)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.controlMid, c.surface],
          ).createShader(rect),
      );
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = c.primary
        ..strokeWidth = compact ? 1.8 : 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (hovered case final index?) {
      final point = pointAt(index);
      canvas.drawLine(
        Offset(point.dx, rect.top),
        Offset(point.dx, rect.bottom),
        Paint()..color = c.text.withValues(alpha: 0.12),
      );
      canvas.drawCircle(point, 4, Paint()..color = Colors.white);
      canvas.drawCircle(point, 3, Paint()..color = c.primary);
    }
  }

  @override
  bool shouldRepaint(covariant _BalancePainter oldDelegate) =>
      oldDelegate.c != c ||
      oldDelegate.points != points ||
      oldDelegate.hovered != hovered ||
      oldDelegate.compact != compact;
}

String _decimal(double value) =>
    value.toStringAsFixed(value >= 10 ? 0 : 1).replaceAll('.', ',');

String _freshnessLabel(AccountDataStatus status, DateTime? updatedAt) {
  final statusText = switch (status) {
    AccountDataStatus.current => 'Актуально',
    AccountDataStatus.needsUpdate => 'Требуется обновление',
    AccountDataStatus.partial => 'Данные частичные',
    AccountDataStatus.manual => 'Ручной счёт',
  };
  if (updatedAt == null) return statusText;
  return '$statusText · ${formatDate(updatedAt, includeYear: true)}';
}

String _roleLabel(QestoAccountRole role) => switch (role) {
  QestoAccountRole.everyday => 'Повседневный',
  QestoAccountRole.emergency => 'Подушка',
  QestoAccountRole.savings => 'Накопления',
  QestoAccountRole.salary => 'Зарплатный',
  QestoAccountRole.mandatoryPayments => 'Обязательные платежи',
  QestoAccountRole.other => 'Другое',
};

String _typeLabel(AccountType type) => switch (type) {
  AccountType.bankCard => 'Карта / счёт',
  AccountType.cash => 'Наличные',
  AccountType.savings => 'Накопительный',
  AccountType.deposit => 'Вклад',
  AccountType.investment => 'Инвестиции',
  AccountType.liability => 'Обязательство',
  AccountType.receivable => 'К получению',
  AccountType.other => 'Другой',
};

IconData _accountIcon(AccountType type) => switch (type) {
  AccountType.cash => Icons.payments_outlined,
  AccountType.bankCard => Icons.credit_card_outlined,
  AccountType.savings => Icons.savings_outlined,
  AccountType.deposit => Icons.account_balance_outlined,
  AccountType.investment => Icons.candlestick_chart_outlined,
  AccountType.liability => Icons.receipt_long_outlined,
  _ => Icons.account_balance_wallet_outlined,
};

Color _accountColor(QestoSemanticColors c, AccountType type) => switch (type) {
  AccountType.cash => c.warning,
  AccountType.savings => c.positive,
  AccountType.deposit => c.purple,
  _ => c.primary,
};

String _plural(int count, String one, String few, String many) {
  final mod100 = count % 100;
  final mod10 = count % 10;
  if (mod100 >= 11 && mod100 <= 14) return many;
  if (mod10 == 1) return one;
  if (mod10 >= 2 && mod10 <= 4) return few;
  return many;
}
