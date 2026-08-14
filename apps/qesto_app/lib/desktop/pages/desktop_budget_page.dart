import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/services/category_budget_calculation_service.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/budget/widgets/budget_category_icon.dart';
import '../widgets/desktop_components.dart';

class DesktopBudgetPage extends StatefulWidget {
  const DesktopBudgetPage({required this.controller, super.key});
  final BudgetController controller;

  @override
  State<DesktopBudgetPage> createState() => _DesktopBudgetPageState();
}

class _DesktopBudgetPageState extends State<DesktopBudgetPage> {
  late int _periodIndex = _initialPeriodIndex();

  int _initialPeriodIndex() {
    final index = widget.controller.periods.indexWhere(
      (item) => item.contains(widget.controller.referenceDate),
    );
    return index < 0 ? widget.controller.periods.length - 1 : index;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (widget.controller.periods.isEmpty) {
          return const DesktopEmptyState(
            title: 'Бюджет пока не настроен',
            message: 'Создайте период и распределите лимиты по категориям.',
            icon: Icons.pie_chart_outline_rounded,
          );
        }
        _periodIndex = _periodIndex.clamp(
          0,
          widget.controller.periods.length - 1,
        );
        final period = widget.controller.periods[_periodIndex];
        final summary = widget.controller.summaryFor(period);
        final statuses = widget.controller.categoryPlansFor(period);
        final planned = statuses.fold<int>(
          0,
          (sum, item) => sum + item.plannedAmount,
        );
        final forecast = widget.controller.forecastFor(period);
        final forecastTotal = forecast.projectedPoints.isEmpty
            ? summary.currentExpense
            : forecast.projectedPoints.last.amount.round();
        final unallocated = period.totalPlan - planned;
        return Padding(
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 28),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton.outlined(
                    tooltip: 'Предыдущий месяц',
                    onPressed: _periodIndex > 0
                        ? () => setState(() => _periodIndex--)
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    capitalize(
                      formatBudgetPeriod(
                        period.month,
                        period.year,
                        includeYear: true,
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.outlined(
                    tooltip: 'Следующий месяц',
                    onPressed:
                        _periodIndex < widget.controller.periods.length - 1
                        ? () => setState(() => _periodIndex++)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    key: const Key('desktop-customize-categories'),
                    onPressed: _openCategoryAppearance,
                    icon: const Icon(Icons.palette_outlined, size: 18),
                    label: const Text('Вид категорий'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: QestoColors.text,
                      side: const BorderSide(color: QestoColors.border),
                      backgroundColor: QestoColors.surface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  DesktopPill(
                    label: !period.hasAssignedBudget
                        ? 'Бюджет не назначен'
                        : forecast.state ==
                              BudgetForecastState.projectedOverLimit
                        ? 'Риск превышения'
                        : forecast.state == BudgetForecastState.exceeded
                        ? 'Лимит превышен'
                        : 'Темп в норме',
                    icon: !period.hasAssignedBudget
                        ? Icons.account_balance_wallet_outlined
                        : forecast.state == BudgetForecastState.underPlan
                        ? Icons.check_circle_outline_rounded
                        : Icons.query_stats_rounded,
                    color: !period.hasAssignedBudget
                        ? QestoColors.secondaryText
                        : forecast.state == BudgetForecastState.underPlan
                        ? QestoColors.positive
                        : forecast.state == BudgetForecastState.noForecast
                        ? QestoColors.secondaryText
                        : QestoColors.warning,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 830;
                    final table = DesktopCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          const _BudgetHeader(),
                          const Divider(height: 1),
                          Expanded(
                            child: statuses.isEmpty
                                ? const DesktopEmptyState(
                                    title: 'Нет категорий бюджета',
                                    message:
                                        'Добавьте лимит категории, чтобы увидеть план и факт.',
                                    icon: Icons.category_outlined,
                                  )
                                : ListView.separated(
                                    itemCount: statuses.length,
                                    separatorBuilder: (_, _) => const Divider(
                                      height: 1,
                                      indent: 18,
                                      endIndent: 18,
                                    ),
                                    itemBuilder: (context, index) => _BudgetRow(
                                      controller: widget.controller,
                                      period: period,
                                      status: statuses[index],
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    );
                    final summaryCard = _BudgetSummaryCard(
                      currency: period.currency,
                      hasBudget: period.hasAssignedBudget,
                      income:
                          widget
                              .controller
                              .financialState
                              .monthlyIncome
                              .minorUnits ~/
                          100,
                      totalPlan: period.totalPlan,
                      planned: planned,
                      spent: summary.currentExpense,
                      forecast: forecastTotal,
                      unallocated: unallocated,
                      onEditBudget: () => _editTotalBudget(period),
                    );
                    if (stacked) {
                      return Column(
                        children: [
                          Expanded(child: table),
                          const SizedBox(height: 14),
                          SizedBox(height: 210, child: summaryCard),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: table),
                        const SizedBox(width: 16),
                        SizedBox(width: 310, child: summaryCard),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openCategoryAppearance() async {
    final selection = await showDialog<_CategoryAppearanceSelection>(
      context: context,
      builder: (context) =>
          _CategoryAppearanceDialog(categories: widget.controller.categories),
    );
    if (selection == null) return;
    await widget.controller.updateCategoryAppearance(
      categoryId: selection.categoryId,
      name: selection.name,
      iconKey: selection.iconKey,
      colorValue: selection.colorValue,
    );
  }

  Future<void> _editTotalBudget(BudgetPeriod period) async {
    var draft = period.hasAssignedBudget ? period.totalPlan.toString() : '';
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('total-budget-dialog'),
        title: Text(
          period.hasAssignedBudget
              ? 'Изменить общий бюджет'
              : 'Назначить бюджет',
        ),
        content: TextFormField(
          key: const Key('total-budget-input'),
          initialValue: draft,
          onChanged: (value) => draft = value,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Лимит на период',
            helperText: 'Ноль означает, что бюджет не назначен',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('save-total-budget'),
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(draft.trim())),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (value == null) return;
    await widget.controller.setTotalBudget(period: period, totalPlan: value);
  }
}

class _CategoryAppearanceSelection {
  const _CategoryAppearanceSelection({
    required this.categoryId,
    required this.name,
    required this.iconKey,
    required this.colorValue,
  });

  final String categoryId;
  final String name;
  final String iconKey;
  final int colorValue;
}

class _CategoryAppearanceDialog extends StatefulWidget {
  const _CategoryAppearanceDialog({required this.categories});

  final List<BudgetCategory> categories;

  @override
  State<_CategoryAppearanceDialog> createState() =>
      _CategoryAppearanceDialogState();
}

class _CategoryAppearanceDialogState extends State<_CategoryAppearanceDialog> {
  static const _colors = <int>[
    0xFF3478F6,
    0xFF5B8DEF,
    0xFF2EC4B6,
    0xFF55C96F,
    0xFF8DBF42,
    0xFFFFB347,
    0xFFFF8A65,
    0xFFFF6B5F,
    0xFFEF5DA8,
    0xFFD96BD8,
    0xFF8D63F6,
    0xFF6C63FF,
    0xFF4CA6A8,
    0xFF457B9D,
    0xFF6C757D,
    0xFF264653,
  ];
  static const _icons = <String>[
    'home',
    'cart',
    'cafe',
    'transport',
    'car',
    'health',
    'shopping',
    'subscriptions',
    'fun',
    'travel',
    'education',
    'pets',
    'gift',
    'business',
    'savings',
    'investment',
    'fitness',
    'music',
    'book',
    'camera',
    'other',
  ];

  late BudgetCategory selected = widget.categories.first;
  late final TextEditingController name = TextEditingController(
    text: selected.name,
  );
  late int colorValue = selected.colorValue;
  late String iconKey = selected.iconKey;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  void _select(BudgetCategory category) {
    setState(() {
      selected = category;
      name.text = category.name;
      colorValue = category.colorValue;
      iconKey = category.iconKey;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('category-appearance-dialog'),
    title: const Text('Оформление категорий'),
    contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
    content: SizedBox(
      width: 780,
      height: 510,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 250,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: QestoColors.surfaceSecondary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: widget.categories.length,
                itemBuilder: (context, index) {
                  final category = widget.categories[index];
                  final active = category.id == selected.id;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Material(
                      color: active ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: ListTile(
                        key: Key('category-style-${category.id}'),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        onTap: () => _select(category),
                        leading: BudgetCategoryIcon(
                          iconKey: category.iconKey,
                          color: Color(category.colorValue),
                          size: 32,
                        ),
                        title: Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: active
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      BudgetCategoryIcon(
                        iconKey: iconKey,
                        color: Color(colorValue),
                        size: 58,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name.text.trim().isEmpty
                                  ? selected.name
                                  : name.text.trim(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Text(
                              'Так категория выглядит во всех графиках Qesto',
                              style: TextStyle(
                                color: QestoColors.secondaryText,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    key: const Key('category-appearance-name'),
                    controller: name,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Название категории',
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Цвет',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: [
                      for (final value in _colors)
                        InkWell(
                          key: Key('category-color-$value'),
                          borderRadius: BorderRadius.circular(99),
                          onTap: () => setState(() => colorValue = value),
                          child: Container(
                            width: 31,
                            height: 31,
                            decoration: BoxDecoration(
                              color: Color(value),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colorValue == value
                                    ? QestoColors.text
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                            child: colorValue == value
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 17,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Иконка',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final value in _icons)
                        InkWell(
                          key: Key('category-icon-$value'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() => iconKey = value),
                          child: Container(
                            width: 39,
                            height: 39,
                            decoration: BoxDecoration(
                              color: iconKey == value
                                  ? Color(colorValue).withValues(alpha: 0.14)
                                  : QestoColors.surfaceSecondary,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: iconKey == value
                                    ? Color(colorValue)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Icon(
                              budgetCategoryIcon(value),
                              size: 20,
                              color: iconKey == value
                                  ? Color(colorValue)
                                  : QestoColors.secondaryText,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Отмена'),
      ),
      FilledButton.icon(
        key: const Key('save-category-appearance'),
        onPressed: () => Navigator.of(context).pop(
          _CategoryAppearanceSelection(
            categoryId: selected.id,
            name: name.text,
            iconKey: iconKey,
            colorValue: colorValue,
          ),
        ),
        icon: const Icon(Icons.check_rounded, size: 18),
        label: const Text('Сохранить'),
      ),
    ],
  );
}

class _BudgetHeader extends StatelessWidget {
  const _BudgetHeader();
  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 46,
    child: Row(
      children: [
        SizedBox(width: 20),
        Expanded(flex: 3, child: _HeaderText('КАТЕГОРИЯ')),
        SizedBox(width: 120, child: _HeaderText('ПЛАН', alignRight: true)),
        SizedBox(width: 120, child: _HeaderText('ФАКТ', alignRight: true)),
        SizedBox(width: 120, child: _HeaderText('ОСТАЛОСЬ', alignRight: true)),
        SizedBox(width: 24),
      ],
    ),
  );
}

class _HeaderText extends StatelessWidget {
  const _HeaderText(this.value, {this.alignRight = false});
  final String value;
  final bool alignRight;
  @override
  Widget build(BuildContext context) => Align(
    alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
    child: Text(
      value,
      style: const TextStyle(
        color: QestoColors.secondaryText,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    ),
  );
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.controller,
    required this.period,
    required this.status,
  });
  final BudgetController controller;
  final BudgetPeriod period;
  final CategoryPlanStatus status;

  @override
  Widget build(BuildContext context) {
    final color = Color(status.category.colorValue);
    final hasBudget = status.hasAssignedBudget;
    return InkWell(
      onTap: () => _editBudget(context),
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            const SizedBox(width: 20),
            Expanded(
              flex: 3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status.category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DesktopProgressBar(
                    value: status.progress,
                    color: !hasBudget
                        ? QestoColors.secondaryText
                        : status.isExceeded
                        ? QestoColors.negative
                        : color,
                    height: 5,
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                hasBudget
                    ? formatMoney(status.plannedAmount, period.currency)
                    : 'Не назначен',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                formatMoney(status.spentAmount, period.currency),
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(
                hasBudget
                    ? formatMoney(
                        status.remaining,
                        period.currency,
                        showSign: status.remaining < 0,
                      )
                    : '—',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: !hasBudget
                      ? QestoColors.secondaryText
                      : status.isExceeded
                      ? QestoColors.negative
                      : QestoColors.positive,
                ),
              ),
            ),
            const SizedBox(width: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _editBudget(BuildContext context) async {
    final text = TextEditingController(text: status.plannedAmount.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('План · ${status.category.name}'),
        content: TextField(
          controller: text,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Сумма на месяц'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(text.text)),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    text.dispose();
    if (value == null) return;
    await controller.setCategoryBudget(
      period: period,
      categoryId: status.category.id,
      plannedAmount: value,
    );
  }
}

class _BudgetSummaryCard extends StatelessWidget {
  const _BudgetSummaryCard({
    required this.currency,
    required this.hasBudget,
    required this.income,
    required this.totalPlan,
    required this.planned,
    required this.spent,
    required this.forecast,
    required this.unallocated,
    required this.onEditBudget,
  });
  final String currency;
  final bool hasBudget;
  final int income;
  final int totalPlan;
  final int planned;
  final int spent;
  final int forecast;
  final int unallocated;
  final VoidCallback onEditBudget;

  @override
  Widget build(BuildContext context) => DesktopCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                hasBudget ? 'Осталось распределить' : 'Бюджет не назначен',
                style: const TextStyle(
                  color: QestoColors.secondaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              key: const Key('edit-total-budget'),
              onPressed: onEditBudget,
              child: Text(hasBudget ? 'Изменить' : 'Назначить'),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          hasBudget ? formatMoney(unallocated, currency) : '—',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.7,
            color: unallocated < 0 ? QestoColors.negative : QestoColors.text,
          ),
        ),
        const SizedBox(height: 12),
        _SummaryLine('Доход', income, currency),
        _SummaryLine(
          'Общий лимит',
          totalPlan,
          currency,
          valueLabel: hasBudget ? null : 'Не назначен',
        ),
        _SummaryLine('По категориям', planned, currency),
        _SummaryLine('Потрачено', spent, currency),
        _SummaryLine(
          'Прогноз',
          forecast,
          currency,
          strong: true,
          valueLabel: hasBudget ? null : 'Без бюджета',
        ),
        const Spacer(),
        DesktopProgressBar(
          value: totalPlan <= 0 ? 0 : spent / totalPlan,
          color: hasBudget && spent > totalPlan
              ? QestoColors.negative
              : hasBudget
              ? QestoColors.primary
              : QestoColors.secondaryText,
          height: 8,
        ),
        const SizedBox(height: 8),
        Text(
          totalPlan <= 0
              ? 'Задайте месячный лимит'
              : '${(spent / totalPlan * 100).round()}% месячного лимита использовано',
          style: const TextStyle(
            color: QestoColors.secondaryText,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine(
    this.label,
    this.value,
    this.currency, {
    this.strong = false,
    this.valueLabel,
  });
  final String label;
  final int value;
  final String currency;
  final bool strong;
  final String? valueLabel;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: strong ? QestoColors.text : QestoColors.secondaryText,
              fontSize: 11,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
        Text(
          valueLabel ?? formatMoney(value, currency),
          style: TextStyle(
            fontSize: 11,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
