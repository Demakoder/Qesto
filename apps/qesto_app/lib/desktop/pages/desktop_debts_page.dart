import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/capital/domain/debt_analytics_service.dart';
import '../widgets/desktop_components.dart';

class DesktopDebtsPage extends StatefulWidget {
  const DesktopDebtsPage({required this.controller, super.key});

  final BudgetController controller;

  @override
  State<DesktopDebtsPage> createState() => _DesktopDebtsPageState();
}

class _DesktopDebtsPageState extends State<DesktopDebtsPage> {
  static const _service = DebtAnalyticsService();

  DebtAnalyticsPeriod _period = DebtAnalyticsPeriod.threeMonths;
  String? _openedDebtId;
  int _extraMonthlyPayment = 0;
  final _oneTimeController = TextEditingController(text: '100000');

  @override
  void dispose() {
    _oneTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final data = _service.calculate(
        debts: widget.controller.debts,
        balanceSnapshots: widget.controller.debtBalanceSnapshots,
        debtPayments: widget.controller.debtPayments,
        transactions: widget.controller.transactions,
        asOf: widget.controller.referenceDate,
        period: _period,
        baseCurrency: widget.controller.user.defaultCurrency,
      );
      final opened = data.debts
          .where((item) => item.debt.id == _openedDebtId)
          .firstOrNull;
      if (opened != null) {
        return _DebtDetails(
          insight: opened,
          snapshots: widget.controller.debtBalanceSnapshots
              .where((item) => item.debtId == opened.debt.id)
              .toList(growable: false),
          asOf: widget.controller.referenceDate,
          extraMonthlyPayment: _extraMonthlyPayment,
          oneTimeController: _oneTimeController,
          onBack: () => setState(() => _openedDebtId = null),
          onEdit: () => _openDebtEditor(context, debt: opened.debt),
          onArchive: () => _archive(context, opened.debt),
          onExtraChanged: (value) =>
              setState(() => _extraMonthlyPayment = value),
        );
      }
      return _overview(context, data);
    },
  );

  Widget _overview(BuildContext context, DebtPortfolioSnapshot data) {
    if (data.debts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(26, 20, 26, 30),
        children: [
          _DebtsHeader(onAdd: () => _openDebtEditor(context)),
          const SizedBox(height: 16),
          DesktopEmptyState(
            title: 'Долгов нет',
            message:
                'Когда Qesto обнаружит кредит, ипотеку, кредитную карту или рассрочку, они появятся здесь. Пока долг можно добавить вручную.',
            icon: Icons.check_circle_outline_rounded,
            action: FilledButton.icon(
              key: const Key('debt-add-empty'),
              onPressed: () => _openDebtEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить долг вручную'),
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
          _DebtsHeader(onAdd: () => _openDebtEditor(context)),
          const SizedBox(height: 16),
          _DebtOverviewCard(
            data: data,
            period: _period,
            onPeriodChanged: (value) => setState(() => _period = value),
          ),
          const SizedBox(height: 14),
          _DebtMetrics(data: data),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final vertical = constraints.maxWidth < 930;
              if (vertical) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DebtStructureCard(data: data),
                    const SizedBox(height: 14),
                    _UpcomingDebtPaymentsCard(data: data),
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _DebtStructureCard(data: data)),
                    const SizedBox(width: 14),
                    Expanded(child: _UpcomingDebtPaymentsCard(data: data)),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 22),
          const Text(
            'Ваши долги',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 11),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1180
                  ? 3
                  : constraints.maxWidth >= 600
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 14) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final insight in data.debts)
                    SizedBox(
                      width: width,
                      child: _DebtCard(
                        insight: insight,
                        onOpen: () => setState(() {
                          _openedDebtId = insight.debt.id;
                          _extraMonthlyPayment = 0;
                        }),
                      ),
                    ),
                ],
              );
            },
          ),
          if (data.hasUnconvertedCurrencies) ...[
            const SizedBox(height: 14),
            const Text(
              'Часть валютных долгов не вошла в итог: для валюты нет курса пересчёта.',
              style: TextStyle(color: QestoColors.warning, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openDebtEditor(
    BuildContext context, {
    DebtAccount? debt,
  }) async {
    final title = TextEditingController(text: debt?.name ?? '');
    final creditor = TextEditingController(text: debt?.institutionName ?? '');
    final balance = TextEditingController(
      text: debt == null ? '' : debt.currentBalance.toString(),
    );
    final original = TextEditingController(
      text: debt?.originalPrincipal?.toString() ?? '',
    );
    final rate = TextEditingController(
      text: debt?.interestRate?.toString().replaceAll('.', ',') ?? '',
    );
    final payment = TextEditingController(
      text: debt?.monthlyPayment?.toString() ?? '',
    );
    final paymentDay = TextEditingController(
      text: debt?.paymentDay?.toString() ?? '',
    );
    final creditLimit = TextEditingController(
      text: debt?.creditCardDetails?.creditLimit?.toString() ?? '',
    );
    final minimumPayment = TextEditingController(
      text: debt?.creditCardDetails?.minimumPayment?.toString() ?? '',
    );
    final gracePayment = TextEditingController(
      text: debt?.creditCardDetails?.gracePaymentAmount?.toString() ?? '',
    );
    var type = debt?.type ?? DebtType.personalLoan;
    var paymentType = debt?.paymentType ?? DebtPaymentType.unknown;
    var currency = debt?.currency ?? widget.controller.user.defaultCurrency;
    var nextPaymentDate = debt?.nextPaymentDate;
    var plannedEndDate = debt?.plannedEndDate;
    String? error;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          key: const Key('debt-editor-dialog'),
          title: Text(debt == null ? 'Добавить долг' : 'Редактировать долг'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('debt-name-field'),
                          controller: title,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Название *',
                            prefixIcon: Icon(Icons.account_balance_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const Key('debt-creditor-field'),
                          controller: creditor,
                          decoration: const InputDecoration(
                            labelText: 'Банк или кредитор',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<DebtType>(
                          key: const Key('debt-type-field'),
                          isExpanded: true,
                          initialValue: type,
                          decoration: const InputDecoration(labelText: 'Тип'),
                          items: [
                            for (final item in DebtType.values)
                              DropdownMenuItem(
                                value: item,
                                child: Text(_debtTypeLabel(item)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => type = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const Key('debt-balance-field'),
                          controller: balance,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: 'Текущий остаток *',
                            suffixText: currency,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 105,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
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
                    children: [
                      Expanded(
                        child: _OptionalNumberField(
                          controller: original,
                          label: 'Первоначальная сумма',
                          suffix: currency,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: rate,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9,.]'),
                            ),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Ставка',
                            suffixText: '% годовых',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _OptionalNumberField(
                          key: const Key('debt-payment-field'),
                          controller: payment,
                          label: 'Платёж в месяц',
                          suffix: currency,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _OptionalNumberField(
                          controller: paymentDay,
                          label: 'День платежа',
                          suffix: '1–31',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<DebtPaymentType>(
                          isExpanded: true,
                          initialValue: paymentType,
                          decoration: const InputDecoration(
                            labelText: 'График',
                          ),
                          items: [
                            for (final item in DebtPaymentType.values)
                              DropdownMenuItem(
                                value: item,
                                child: Text(_paymentTypeLabel(item)),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => paymentType = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _DateInput(
                          label: 'Следующий платёж',
                          value: nextPaymentDate,
                          onChanged: (value) =>
                              setDialogState(() => nextPaymentDate = value),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DateInput(
                          label: 'Плановое закрытие',
                          value: plannedEndDate,
                          onChanged: (value) =>
                              setDialogState(() => plannedEndDate = value),
                        ),
                      ),
                    ],
                  ),
                  if (type == DebtType.creditCard) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'Кредитная карта',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _OptionalNumberField(
                            controller: creditLimit,
                            label: 'Кредитный лимит',
                            suffix: currency,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _OptionalNumberField(
                            controller: minimumPayment,
                            label: 'Минимальный платёж',
                            suffix: currency,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _OptionalNumberField(
                            controller: gracePayment,
                            label: 'Для грейс-периода',
                            suffix: currency,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: const TextStyle(color: QestoColors.danger),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Text(
                    '* Для создания достаточно названия и текущего остатка. Неизвестные поля останутся пустыми.',
                    style: TextStyle(
                      color: QestoColors.secondaryText,
                      fontSize: 10,
                    ),
                  ),
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
              key: const Key('debt-save-button'),
              onPressed: () {
                final parsedBalance = _integer(balance.text);
                final day = _integerOrNull(paymentDay.text);
                if (title.text.trim().isEmpty || parsedBalance == null) {
                  setDialogState(
                    () => error = 'Укажите название и текущий остаток',
                  );
                  return;
                }
                if (day != null && (day < 1 || day > 31)) {
                  setDialogState(
                    () => error = 'День платежа должен быть от 1 до 31',
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      final cardDetails = type == DebtType.creditCard
          ? CreditCardDebtDetails(
              creditLimit: _integerOrNull(creditLimit.text),
              minimumPayment: _integerOrNull(minimumPayment.text),
              gracePaymentAmount: _integerOrNull(gracePayment.text),
              graceDeadline: nextPaymentDate,
              interestRateAfterGrace: _decimalOrNull(rate.text),
            )
          : null;
      if (debt == null) {
        await widget.controller.addDebt(
          name: title.text,
          institutionName: creditor.text,
          currentBalance: _integer(balance.text)!,
          originalPrincipal: _integerOrNull(original.text),
          type: type,
          currency: currency,
          interestRate: _decimalOrNull(rate.text),
          monthlyPayment: _integerOrNull(payment.text),
          paymentDay: _integerOrNull(paymentDay.text),
          nextPaymentDate: nextPaymentDate,
          plannedEndDate: plannedEndDate,
          paymentType: paymentType,
          creditCardDetails: cardDetails,
        );
      } else {
        await widget.controller.updateDebt(
          DebtAccount(
            id: debt.id,
            userId: debt.userId,
            name: title.text,
            type: type,
            currency: currency,
            currentBalance: _integer(balance.text)!,
            status: debt.status,
            source: debt.source,
            dataQuality: debt.dataQuality,
            confidence: debt.confidence,
            createdAt: debt.createdAt,
            updatedAt: DateTime.now(),
            institutionId: debt.institutionId,
            institutionName: creditor.text.trim().isEmpty
                ? null
                : creditor.text.trim(),
            linkedAccountId: debt.linkedAccountId,
            originalPrincipal: _integerOrNull(original.text),
            currentPrincipal: _integer(balance.text),
            accruedInterest: debt.accruedInterest,
            interestRate: _decimalOrNull(rate.text),
            effectiveRate: debt.effectiveRate,
            monthlyPayment: _integerOrNull(payment.text),
            paymentDay: _integerOrNull(paymentDay.text),
            nextPaymentDate: nextPaymentDate,
            startDate: debt.startDate,
            plannedEndDate: plannedEndDate,
            paymentType: paymentType,
            creditCardDetails: cardDetails,
          ),
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    for (final controller in [
      title,
      creditor,
      balance,
      original,
      rate,
      payment,
      paymentDay,
      creditLimit,
      minimumPayment,
      gracePayment,
    ]) {
      controller.dispose();
    }
  }

  Future<void> _archive(BuildContext context, DebtAccount debt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Архивировать долг?'),
        content: Text(
          '«${debt.name}» исчезнет из активных долгов, но история останется.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('В архив'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.archiveDebt(debt.id);
      if (mounted) setState(() => _openedDebtId = null);
    }
  }
}

class _DebtsHeader extends StatelessWidget {
  const _DebtsHeader({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Долги',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 4),
            Text(
              'Обязательства, их стоимость и путь к погашению',
              style: TextStyle(color: QestoColors.secondaryText),
            ),
          ],
        ),
      ),
      FilledButton.icon(
        key: const Key('debt-add-button'),
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Добавить долг'),
      ),
    ],
  );
}

class _DebtOverviewCard extends StatelessWidget {
  const _DebtOverviewCard({
    required this.data,
    required this.period,
    required this.onPeriodChanged,
  });

  final DebtPortfolioSnapshot data;
  final DebtAnalyticsPeriod period;
  final ValueChanged<DebtAnalyticsPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final change = data.change;
    final positive = change != null && change < 0;
    return DesktopCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopAdaptiveRow(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Общий долг',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      formatMoney(data.totalDebt, data.baseCurrency),
                      key: const Key('total-debt'),
                      style: context.qestoTypography.display(
                        const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                        numeric: true,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      change == null
                          ? 'История начнёт формироваться после обновления остатка'
                          : '${positive ? 'Долг уменьшился' : 'Долг вырос'} на ${formatMoney(change.abs(), data.baseCurrency)}${data.changePercent == null ? '' : ' · ${data.changePercent!.abs().toStringAsFixed(1)}%'}',
                      style: TextStyle(
                        color: change == null
                            ? QestoColors.secondaryText
                            : positive
                            ? QestoColors.positive
                            : QestoColors.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              SegmentedButton<DebtAnalyticsPeriod>(
                segments: [
                  for (final item in DebtAnalyticsPeriod.values)
                    ButtonSegment(value: item, label: Text(item.label)),
                ],
                selected: {period},
                showSelectedIcon: false,
                onSelectionChanged: (value) => onPeriodChanged(value.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: 190,
            child: _DebtTrendChart(
              points: data.trend,
              currency: data.baseCurrency,
            ),
          ),
        ],
      ),
    );
  }
}

class _DebtMetrics extends StatelessWidget {
  const _DebtMetrics({required this.data});
  final DebtPortfolioSnapshot data;

  @override
  Widget build(BuildContext context) {
    final next = data.nextPayments.firstOrNull;
    final values = <Widget>[
      _DebtMetricCard(
        icon: Icons.event_repeat_outlined,
        label: 'Обязательные платежи',
        value: data.monthlyDebtPayments == 0
            ? 'Нет данных'
            : '${formatMoney(data.monthlyDebtPayments, data.baseCurrency)} / мес.',
        detail: data.hasCompletePaymentData
            ? null
            : 'Учтены только известные платежи',
      ),
      _DebtMetricCard(
        icon: Icons.percent_rounded,
        label: 'Доля дохода на долги',
        value: data.debtPaymentToIncomeRatio == null
            ? 'Недостаточно данных'
            : formatPercent(data.debtPaymentToIncomeRatio!, decimals: 1),
        detail: data.averageMonthlyIncome == null
            ? null
            : 'Средний доход ${formatMoney(data.averageMonthlyIncome!, data.baseCurrency)}',
      ),
      _DebtMetricCard(
        icon: Icons.payments_outlined,
        label: 'Проценты',
        value: data.monthlyInterestCost == null
            ? 'Нет данных'
            : '≈${formatMoney(data.monthlyInterestCost!, data.baseCurrency)} / мес.',
        detail: data.hasCompleteInterestData ? null : 'Не все ставки известны',
      ),
      _DebtMetricCard(
        icon: Icons.calendar_today_outlined,
        label: 'Ближайший платёж',
        value: next == null
            ? 'Нет данных'
            : formatMoney(next.amount, next.currency),
        detail: next == null
            ? null
            : '${next.title} · ${formatDate(next.date)}',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 42) / 4;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final item in values)
              SizedBox(width: math.max(210, width), child: item),
          ],
        );
      },
    );
  }
}

class _DebtMetricCard extends StatelessWidget {
  const _DebtMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });
  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) => DesktopCard(
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: QestoColors.primarySoft,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: QestoColors.primary),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: QestoColors.secondaryText,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(
                  detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: QestoColors.secondaryText,
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _DebtStructureCard extends StatelessWidget {
  const _DebtStructureCard({required this.data});
  final DebtPortfolioSnapshot data;

  @override
  Widget build(BuildContext context) => DesktopCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Структура долга',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        if (data.structure.isEmpty)
          const Text(
            'Нет задолженности',
            style: TextStyle(color: QestoColors.secondaryText),
          )
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (final item in data.structure)
                    Expanded(
                      flex: math.max(1, (item.share * 1000).round()),
                      child: ColoredBox(color: _debtTypeColor(item.type)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),
          for (final item in data.structure)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _debtTypeColor(item.type),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _debtTypeLabel(item.type),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${formatMoney(item.amount, data.baseCurrency)} · ${(item.share * 100).round()}%',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
        ],
      ],
    ),
  );
}

class _UpcomingDebtPaymentsCard extends StatelessWidget {
  const _UpcomingDebtPaymentsCard({required this.data});
  final DebtPortfolioSnapshot data;

  @override
  Widget build(BuildContext context) => DesktopCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Ближайшие платежи',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
            if (data.nextPayments.isNotEmpty)
              Text(
                '30 дней · ${formatMoney(data.next30DaysDebtPayments, data.baseCurrency)}',
                style: const TextStyle(
                  color: QestoColors.secondaryText,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (data.nextPayments.isEmpty)
          const Text(
            'Даты или суммы платежей пока не указаны.',
            style: TextStyle(color: QestoColors.secondaryText, fontSize: 11),
          )
        else
          for (final item in data.nextPayments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 58,
                    child: Text(
                      formatDate(item.date),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _debtTypeColor(item.type).withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      _debtTypeIcon(item.type),
                      size: 17,
                      color: _debtTypeColor(item.type),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          item.creditor ?? _debtTypeLabel(item.type),
                          style: const TextStyle(
                            color: QestoColors.secondaryText,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatMoney(item.amount, item.currency),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
      ],
    ),
  );
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({required this.insight, required this.onOpen});
  final DebtAccountInsight insight;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final debt = insight.debt;
    final payment = debt.type == DebtType.creditCard
        ? debt.creditCardDetails?.minimumPayment ?? debt.monthlyPayment
        : debt.monthlyPayment;
    return DesktopCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _debtTypeColor(debt.type).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  _debtTypeIcon(debt.type),
                  color: _debtTypeColor(debt.type),
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      debt.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      debt.institutionName ?? _debtTypeLabel(debt.type),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: QestoColors.secondaryText,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              _DebtQualityPill(quality: debt.dataQuality),
            ],
          ),
          const SizedBox(height: 17),
          Text(
            formatMoney(debt.currentBalance, debt.currency),
            style: context.qestoTypography.display(
              const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
              numeric: true,
            ),
          ),
          const Text(
            'осталось',
            style: TextStyle(color: QestoColors.secondaryText, fontSize: 10),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _InlineDebtValue(
                  label: 'Ставка',
                  value: debt.interestRate == null
                      ? 'Нет данных'
                      : '${debt.interestRate!.toStringAsFixed(1)}%',
                ),
              ),
              Expanded(
                child: _InlineDebtValue(
                  label: 'Платёж',
                  value: payment == null
                      ? 'Нет данных'
                      : formatMoney(payment, debt.currency),
                ),
              ),
            ],
          ),
          if (debt.nextPaymentDate != null) ...[
            const SizedBox(height: 11),
            Text(
              'Следующий платёж · ${formatDate(debt.nextPaymentDate!, includeYear: true)}',
              style: const TextStyle(
                color: QestoColors.secondaryText,
                fontSize: 10,
              ),
            ),
          ],
          if (insight.utilization != null) ...[
            const SizedBox(height: 11),
            DesktopProgressBar(
              value: insight.utilization!.clamp(0, 1),
              color: insight.utilization! > 0.8
                  ? QestoColors.warning
                  : QestoColors.primary,
            ),
            const SizedBox(height: 5),
            Text(
              'Использовано ${(insight.utilization! * 100).toStringAsFixed(1)}% лимита',
              style: const TextStyle(
                color: QestoColors.secondaryText,
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InlineDebtValue extends StatelessWidget {
  const _InlineDebtValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: QestoColors.secondaryText, fontSize: 9),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _DebtDetails extends StatelessWidget {
  const _DebtDetails({
    required this.insight,
    required this.snapshots,
    required this.asOf,
    required this.extraMonthlyPayment,
    required this.oneTimeController,
    required this.onBack,
    required this.onEdit,
    required this.onArchive,
    required this.onExtraChanged,
  });

  final DebtAccountInsight insight;
  final List<DebtBalanceSnapshot> snapshots;
  final DateTime asOf;
  final int extraMonthlyPayment;
  final TextEditingController oneTimeController;
  final VoidCallback onBack;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final ValueChanged<int> onExtraChanged;

  static const _service = DebtAnalyticsService();

  @override
  Widget build(BuildContext context) {
    final debt = insight.debt;
    final history = snapshots.toList()
      ..sort((left, right) => left.date.compareTo(right.date));
    final points = [
      for (final item in history)
        DebtTrendPoint(
          date: item.date,
          totalBalance: item.totalBalance,
          isConfirmed: true,
        ),
      if (history.isEmpty || history.last.totalBalance != debt.currentBalance)
        DebtTrendPoint(
          date: asOf,
          totalBalance: debt.currentBalance,
          isConfirmed: true,
        ),
    ];
    final extra = _service.simulateExtraMonthlyPayment(
      debt,
      asOf: asOf,
      extraMonthlyPayment: extraMonthlyPayment,
    );
    final oneTimeAmount = int.tryParse(oneTimeController.text) ?? 0;
    final oneTime = _service.simulateOneTimePrepayment(
      debt,
      asOf: asOf,
      amount: oneTimeAmount,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 18, 26, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton.outlined(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Назад к долгам',
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      debt.name,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${debt.institutionName ?? 'Кредитор не указан'} · ${_debtTypeLabel(debt.type)}',
                      style: const TextStyle(color: QestoColors.secondaryText),
                    ),
                  ],
                ),
              ),
              _DebtQualityPill(quality: debt.dataQuality),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Изменить'),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                onPressed: onArchive,
                icon: const Icon(Icons.archive_outlined),
                tooltip: 'В архив',
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final vertical = constraints.maxWidth < 940;
              final summary = _DebtSummaryCard(insight: insight);
              final chart = DesktopCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Динамика остатка',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 230,
                      child: _DebtTrendChart(
                        points: points,
                        currency: debt.currency,
                      ),
                    ),
                    Text(
                      points.length < 2
                          ? 'Пока известен только текущий остаток — Qesto не достраивает прошлое.'
                          : 'Сплошная линия показывает сохранённые снимки остатка.',
                      style: const TextStyle(
                        color: QestoColors.secondaryText,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              );
              if (vertical) {
                return Column(
                  children: [summary, const SizedBox(height: 14), chart],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 360, child: summary),
                    const SizedBox(width: 14),
                    Expanded(child: chart),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          _ExtraPaymentCard(
            debt: debt,
            simulation: extra,
            selectedExtra: extraMonthlyPayment,
            onChanged: onExtraChanged,
          ),
          const SizedBox(height: 14),
          _OneTimePaymentCard(
            debt: debt,
            controller: oneTimeController,
            simulation: oneTime,
            onRefresh: () => onExtraChanged(extraMonthlyPayment),
          ),
          const SizedBox(height: 10),
          const Text(
            'Расчёты приблизительные. Фактический график зависит от условий банка, комиссий, страховок и правил досрочного погашения.',
            style: TextStyle(color: QestoColors.secondaryText, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _DebtSummaryCard extends StatelessWidget {
  const _DebtSummaryCard({required this.insight});
  final DebtAccountInsight insight;

  @override
  Widget build(BuildContext context) {
    final debt = insight.debt;
    return DesktopCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Осталось',
            style: TextStyle(color: QestoColors.secondaryText, fontSize: 11),
          ),
          const SizedBox(height: 5),
          Text(
            formatMoney(debt.currentBalance, debt.currency),
            style: context.qestoTypography.display(
              const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              numeric: true,
            ),
          ),
          const SizedBox(height: 16),
          _DetailLine(
            'Первоначальная сумма',
            debt.originalPrincipal == null
                ? 'Нет данных'
                : formatMoney(debt.originalPrincipal!, debt.currency),
          ),
          _DetailLine(
            'Погашено основного долга',
            insight.paidPrincipal == null
                ? 'Нет данных'
                : formatMoney(insight.paidPrincipal!, debt.currency),
          ),
          _DetailLine(
            'Ставка',
            debt.interestRate == null
                ? 'Нет данных'
                : '${debt.interestRate!.toStringAsFixed(2)}%',
          ),
          _DetailLine(
            'Платёж',
            debt.monthlyPayment == null
                ? 'Нет данных'
                : '${formatMoney(debt.monthlyPayment!, debt.currency)} / месяц',
          ),
          _DetailLine(
            'Следующий платёж',
            debt.nextPaymentDate == null
                ? 'Нет данных'
                : formatDate(debt.nextPaymentDate!, includeYear: true),
          ),
          _DetailLine(
            'Плановое закрытие',
            insight.payoff == null
                ? 'Нет данных'
                : formatBudgetPeriod(
                    insight.payoff!.payoffDate.month,
                    insight.payoff!.payoffDate.year,
                    includeYear: true,
                  ),
          ),
          if (debt.type == DebtType.creditCard &&
              debt.creditCardDetails != null) ...[
            const Divider(height: 22),
            _DetailLine(
              'Кредитный лимит',
              debt.creditCardDetails!.creditLimit == null
                  ? 'Нет данных'
                  : formatMoney(
                      debt.creditCardDetails!.creditLimit!,
                      debt.currency,
                    ),
            ),
            _DetailLine(
              'Использовано',
              insight.utilization == null
                  ? 'Нет данных'
                  : formatPercent(insight.utilization!, decimals: 1),
            ),
            _DetailLine(
              'Чтобы не платить проценты',
              debt.creditCardDetails!.gracePaymentAmount == null
                  ? 'Нет данных'
                  : formatMoney(
                      debt.creditCardDetails!.gracePaymentAmount!,
                      debt.currency,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: QestoColors.secondaryText,
              fontSize: 10,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class _ExtraPaymentCard extends StatelessWidget {
  const _ExtraPaymentCard({
    required this.debt,
    required this.simulation,
    required this.selectedExtra,
    required this.onChanged,
  });
  final DebtAccount debt;
  final DebtPrepaymentSimulation? simulation;
  final int selectedExtra;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DesktopCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Что если платить больше?',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        const Text(
          'Дополнительный ежемесячный платёж',
          style: TextStyle(color: QestoColors.secondaryText, fontSize: 10),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in const [0, 1000, 5000, 10000, 20000])
              ChoiceChip(
                label: Text(
                  value == 0
                      ? 'Текущий план'
                      : '+${formatMoney(value, debt.currency)}',
                ),
                selected: selectedExtra == value,
                onSelected: (_) => onChanged(value),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (simulation == null)
          const Text(
            'Для прогноза укажите ежемесячный платёж. Для оценки процентов также нужна ставка.',
            style: TextStyle(color: QestoColors.secondaryText, fontSize: 11),
          )
        else
          Row(
            children: [
              Expanded(
                child: _SimulationValue(
                  label: 'Погашение',
                  value: capitalize(
                    formatBudgetPeriod(
                      simulation!.payoffDate.month,
                      simulation!.payoffDate.year,
                      includeYear: true,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _SimulationValue(
                  label: 'Раньше на',
                  value: simulation!.monthsSaved == null
                      ? 'Нет данных'
                      : '${simulation!.monthsSaved} мес.',
                ),
              ),
              Expanded(
                child: _SimulationValue(
                  label: 'Экономия процентов',
                  value: simulation!.interestSaved == null
                      ? 'Нет данных'
                      : '≈${formatMoney(simulation!.interestSaved!, debt.currency)}',
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class _OneTimePaymentCard extends StatelessWidget {
  const _OneTimePaymentCard({
    required this.debt,
    required this.controller,
    required this.simulation,
    required this.onRefresh,
  });
  final DebtAccount debt;
  final TextEditingController controller;
  final OneTimePrepaymentSimulation? simulation;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => DesktopCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Разовый досрочный платёж',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                key: const Key('one-time-payment-field'),
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Внести дополнительно',
                  suffixText: debt.currency,
                ),
                onSubmitted: (_) => onRefresh(),
              ),
            ),
            const SizedBox(width: 9),
            FilledButton(onPressed: onRefresh, child: const Text('Рассчитать')),
          ],
        ),
        const SizedBox(height: 14),
        if (simulation == null)
          const Text(
            'Для модельного расчёта нужен известный ежемесячный платёж.',
            style: TextStyle(color: QestoColors.secondaryText, fontSize: 11),
          )
        else
          Row(
            children: [
              Expanded(
                child: _ScenarioBox(
                  title: 'Уменьшить срок',
                  lines: [
                    'Закрытие: ${capitalize(formatBudgetPeriod(simulation!.reduceTerm.payoffDate.month, simulation!.reduceTerm.payoffDate.year, includeYear: true))}',
                    'Раньше на ${simulation!.reduceTerm.monthsSaved ?? 0} мес.',
                    simulation!.reduceTerm.interestSaved == null
                        ? 'Проценты: нет данных'
                        : 'Экономия ≈${formatMoney(simulation!.reduceTerm.interestSaved!, debt.currency)}',
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ScenarioBox(
                  title: 'Уменьшить платёж',
                  lines: [
                    'Новый платёж: ${formatMoney(simulation!.reducePayment.monthlyPayment, debt.currency)}',
                    'Срок: ${simulation!.reducePayment.months} мес.',
                    simulation!.reducePayment.interestSaved == null
                        ? 'Проценты: нет данных'
                        : 'Экономия ≈${formatMoney(simulation!.reducePayment.interestSaved!, debt.currency)}',
                  ],
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class _SimulationValue extends StatelessWidget {
  const _SimulationValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: QestoColors.secondaryText, fontSize: 10),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _ScenarioBox extends StatelessWidget {
  const _ScenarioBox({required this.title, required this.lines});
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: QestoColors.surfaceSecondary,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 7),
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              line,
              style: const TextStyle(
                color: QestoColors.secondaryText,
                fontSize: 10,
              ),
            ),
          ),
      ],
    ),
  );
}

class _OptionalNumberField extends StatelessWidget {
  const _OptionalNumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    super.key,
  });
  final TextEditingController controller;
  final String label;
  final String suffix;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(labelText: label, suffixText: suffix),
  );
}

class _DateInput extends StatelessWidget {
  const _DateInput({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: value ?? DateTime.now().add(const Duration(days: 30)),
        firstDate: DateTime(2000),
        lastDate: DateTime.now().add(const Duration(days: 36500)),
      );
      if (picked != null) onChanged(picked);
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: value == null
            ? const Icon(Icons.event_outlined)
            : IconButton(
                onPressed: () => onChanged(null),
                icon: const Icon(Icons.close_rounded, size: 17),
              ),
      ),
      child: Text(
        value == null ? 'Не указано' : formatDate(value!, includeYear: true),
      ),
    ),
  );
}

class _DebtQualityPill extends StatelessWidget {
  const _DebtQualityPill({required this.quality});
  final DebtDataQuality quality;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (quality) {
      DebtDataQuality.verified => ('Подтверждено', QestoColors.positive),
      DebtDataQuality.estimated => ('Расчёт', QestoColors.info),
      DebtDataQuality.manual => ('Вручную', QestoColors.primary),
      DebtDataQuality.stale => ('Устарело', QestoColors.warning),
      DebtDataQuality.incomplete => (
        'Не все данные',
        QestoColors.secondaryText,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DebtTrendChart extends StatelessWidget {
  const _DebtTrendChart({required this.points, required this.currency});
  final List<DebtTrendPoint> points;
  final String currency;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DebtTrendPainter(points: points, currency: currency),
    child: const SizedBox.expand(),
  );
}

class _DebtTrendPainter extends CustomPainter {
  const _DebtTrendPainter({required this.points, required this.currency});
  final List<DebtTrendPoint> points;
  final String currency;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 58.0;
    const right = 10.0;
    const top = 12.0;
    const bottom = 25.0;
    final rect = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    final values = points.map((item) => item.totalBalance.toDouble()).toList();
    final maxValue = values.isEmpty
        ? 1.0
        : math.max(1.0, values.reduce(math.max) * 1.08);
    final minRaw = values.isEmpty ? 0.0 : values.reduce(math.min);
    final minValue = math.max(0.0, minRaw * 0.92);
    final span = math.max(1.0, maxValue - minValue);
    final gridPaint = Paint()..color = QestoColors.border;
    for (var index = 0; index <= 3; index++) {
      final y = rect.bottom - rect.height * index / 3;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
      _paintText(
        canvas,
        formatCompactMoney(minValue + span * index / 3, currency),
        Offset(0, y - 6),
        54,
      );
    }
    if (points.isEmpty) return;
    double x(int index) => points.length <= 1
        ? rect.center.dx
        : rect.left + rect.width * index / (points.length - 1);
    double y(int value) =>
        rect.bottom - rect.height * (value - minValue) / span;
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final offset = Offset(x(index), y(points[index].totalBalance));
      if (index == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    if (points.length > 1) {
      final area = Path.from(path)
        ..lineTo(x(points.length - 1), rect.bottom)
        ..lineTo(x(0), rect.bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x223478F6), Color(0x003478F6)],
          ).createShader(rect),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = QestoColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (var index = 0; index < points.length; index++) {
      final offset = Offset(x(index), y(points[index].totalBalance));
      canvas.drawCircle(offset, 3.5, Paint()..color = Colors.white);
      canvas.drawCircle(offset, 2.4, Paint()..color = QestoColors.primary);
    }
    _paintText(
      canvas,
      formatDate(points.first.date),
      Offset(rect.left, rect.bottom + 8),
      80,
    );
    if (points.length > 1) {
      _paintText(
        canvas,
        formatDate(points.last.date),
        Offset(rect.right - 65, rect.bottom + 8),
        65,
        align: TextAlign.right,
      );
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset offset,
    double width, {
    TextAlign align = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: QestoColors.secondaryText, fontSize: 8),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _DebtTrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.currency != currency;
}

int? _integer(String value) {
  final clean = value.replaceAll(RegExp(r'[^0-9]'), '');
  return clean.isEmpty ? null : int.tryParse(clean);
}

int? _integerOrNull(String value) => _integer(value);

double? _decimalOrNull(String value) {
  final clean = value.trim().replaceAll(',', '.');
  return clean.isEmpty ? null : double.tryParse(clean);
}

String _debtTypeLabel(DebtType type) => switch (type) {
  DebtType.mortgage => 'Ипотека',
  DebtType.personalLoan => 'Потребительский кредит',
  DebtType.creditCard => 'Кредитная карта',
  DebtType.autoLoan => 'Автокредит',
  DebtType.installment => 'Рассрочка',
  DebtType.other => 'Другой долг',
};

String _paymentTypeLabel(DebtPaymentType type) => switch (type) {
  DebtPaymentType.annuity => 'Аннуитетный',
  DebtPaymentType.differentiated => 'Дифференцированный',
  DebtPaymentType.unknown => 'Неизвестно',
};

IconData _debtTypeIcon(DebtType type) => switch (type) {
  DebtType.mortgage => Icons.home_outlined,
  DebtType.personalLoan => Icons.account_balance_outlined,
  DebtType.creditCard => Icons.credit_card_outlined,
  DebtType.autoLoan => Icons.directions_car_outlined,
  DebtType.installment => Icons.calendar_view_month_outlined,
  DebtType.other => Icons.receipt_long_outlined,
};

Color _debtTypeColor(DebtType type) => switch (type) {
  DebtType.mortgage => const Color(0xFF3478F6),
  DebtType.personalLoan => const Color(0xFF8D63F6),
  DebtType.creditCard => const Color(0xFFFF8A65),
  DebtType.autoLoan => const Color(0xFF2DB6A3),
  DebtType.installment => const Color(0xFFFFB347),
  DebtType.other => const Color(0xFF8A93A3),
};
