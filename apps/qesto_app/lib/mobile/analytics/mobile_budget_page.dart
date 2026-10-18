import 'package:flutter/material.dart';
import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../desktop/desktop_destination.dart';
import '../../features/budget/category_details_screen.dart';
import '../../features/budget/services/category_budget_calculation_service.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/statistics/domain/models/statistics_models.dart';
import 'mobile_analysis_page.dart';
import 'mobile_financial_widgets.dart';
import 'mobile_statistics_controls.dart';
import 'mobile_upcoming_page.dart';

class MobileBudgetPage extends StatefulWidget {
  const MobileBudgetPage({
    required this.controller,
    required this.onOpenFilteredTransactions,
    super.key,
  });
  final BudgetController controller;
  final ValueChanged<List<String>> onOpenFilteredTransactions;
  @override
  State<MobileBudgetPage> createState() => _MobileBudgetPageState();
}

class _MobileBudgetPageState extends State<MobileBudgetPage> {
  late String _periodId =
      (widget.controller.periods
                  .where((p) => p.contains(widget.controller.referenceDate))
                  .firstOrNull ??
              widget.controller.periods.last)
          .id;
  bool _hidden = false;
  BudgetPeriod get period =>
      widget.controller.periods.where((p) => p.id == _periodId).firstOrNull ??
      widget.controller.periods.last;
  Future<void> _period() async {
    final selected = await mobileChoice(context, 'Бюджетный период', {
      for (final p in widget.controller.periods.reversed)
        p.id:
            '${mobileBudgetPeriodLabel(p)} · ${formatDate(p.startDate)} — ${formatDate(p.endDate)}',
    }, period.id);
    if (selected != null && mounted) setState(() => _periodId = selected);
  }

  void _edit([BudgetCategory? category]) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: const RouteSettings(name: '/budget/limit'),
      builder: (_) => MobileBudgetLimitEditor(
        controller: widget.controller,
        periodId: period.id,
        categoryId: category?.id,
      ),
    ),
  );
  void _category(BudgetCategory category) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      settings: RouteSettings(name: '/budget/category/${category.id}'),
      builder: (_) => MobileBudgetCategoryPage(
        controller: widget.controller,
        periodId: period.id,
        categoryId: category.id,
        hidden: _hidden,
        onOpenFilteredTransactions: widget.onOpenFilteredTransactions,
      ),
    ),
  );
  void _analysis(DesktopDestination destination) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          settings: RouteSettings(name: '/analytics/${destination.name}'),
          builder: (_) => destination == DesktopDestination.recurring
              ? MobileUpcomingPage(
                  controller: widget.controller,
                  initiallyHidden: _hidden,
                  onOpenFilteredTransactions: widget.onOpenFilteredTransactions,
                )
              : MobileAnalysisPage(
                  controller: widget.controller,
                  section: switch (destination) {
                    DesktopDestination.cashFlow => StatisticsSection.cashFlow,
                    DesktopDestination.rhythm => StatisticsSection.rhythm,
                    _ => StatisticsSection.expenses,
                  },
                  initialRange: StatisticsDateRange(
                    period.startDate,
                    widget.controller.activeDateFor(period),
                  ),
                  initiallyHidden: _hidden,
                  onOpenFilteredTransactions: widget.onOpenFilteredTransactions,
                ),
        ),
      );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final p = period;
      final summary = widget.controller.summaryFor(p);
      final categories = widget.controller.categoryPlansFor(p);
      return ListView(
        key: const PageStorageKey('mobile-budget-scroll'),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  key: const Key('mobile-budget-period'),
                  onPressed: _period,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(mobileBudgetPeriodLabel(p), maxLines: 2),
                ),
              ),
              IconButton(
                tooltip: _hidden ? 'Показать суммы' : 'Скрыть суммы',
                onPressed: () => setState(() => _hidden = !_hidden),
                icon: const Icon(Icons.visibility_outlined),
              ),
            ],
          ),
          MobileSection(
            title: 'План и факт',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (summary.hasAssignedBudget) ...[
                  MobileValueRow(
                    title: 'Лимит периода',
                    amount: p.totalPlan,
                    currency: p.currency,
                    hidden: _hidden,
                  ),
                  MobileValueRow(
                    title: 'Потрачено',
                    amount: summary.currentExpense,
                    currency: p.currency,
                    hidden: _hidden,
                    progress: summary.progress,
                    color: summary.remainingAmount < 0
                        ? context.qestoColors.negative
                        : QestoColors.primary,
                  ),
                  MobileValueRow(
                    title: summary.remainingAmount < 0
                        ? 'Превышение'
                        : 'Осталось в бюджете',
                    amount: summary.remainingAmount.abs(),
                    currency: p.currency,
                    hidden: _hidden,
                    color: summary.remainingAmount < 0
                        ? context.qestoColors.negative
                        : null,
                  ),
                ] else ...[
                  const Text(
                    'Общий лимит пока не назначен. Расходы уже доступны; остаток бюджета не рассчитывается.',
                  ),
                  MobileValueRow(
                    title: 'Фактические расходы',
                    amount: summary.currentExpense,
                    currency: p.currency,
                    hidden: _hidden,
                  ),
                ],
                FilledButton(
                  key: const Key('mobile-budget-edit-total'),
                  onPressed: _edit,
                  child: Text(
                    summary.hasAssignedBudget
                        ? 'Изменить общий лимит'
                        : 'Назначить бюджет',
                  ),
                ),
              ],
            ),
          ),
          MobileSection(
            title: 'Лимиты категорий',
            child: Column(
              children: [
                if (categories.isEmpty)
                  const Text(
                    'В этом периоде нет расходов и назначенных лимитов категорий. Лимит можно добавить ниже.',
                  ),
                for (final row in categories)
                  MobileValueRow(
                    title: row.category.name,
                    amount: row.spentAmount,
                    currency: p.currency,
                    hidden: _hidden,
                    caption: _hidden
                        ? 'Суммы скрыты'
                        : row.hasAssignedBudget
                        ? 'Лимит ${formatMoney(row.plannedAmount, p.currency)} · ${row.isExceeded ? 'превышен на' : 'осталось'} ${formatMoney(row.remaining.abs(), p.currency)}'
                        : 'Без лимита',
                    color: row.isExceeded
                        ? context.qestoColors.negative
                        : Color(row.category.colorValue),
                    progress: row.hasAssignedBudget ? row.progress : null,
                    onTap: () => _category(row.category),
                  ),
                TextButton(
                  onPressed: () async {
                    final id = await mobileChoice(
                      context,
                      'Категория для лимита',
                      {
                        for (final c in widget.controller.categories)
                          c.id: c.name,
                      },
                      '',
                    );
                    if (id != null && context.mounted) {
                      _edit(
                        widget.controller.categories.firstWhere(
                          (c) => c.id == id,
                        ),
                      );
                    }
                  },
                  child: const Text('Назначить лимит категории'),
                ),
              ],
            ),
          ),
          MobileSection(
            title: 'Аналитика и предстоящие',
            child: Column(
              children: [
                for (final destination in const [
                  DesktopDestination.expenses,
                  DesktopDestination.cashFlow,
                  DesktopDestination.rhythm,
                  DesktopDestination.recurring,
                ])
                  ListTile(
                    key: Key('mobile-destination-${destination.name}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(destination.icon),
                    title: Text(destination.label),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _analysis(destination),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class MobileBudgetCategoryPage extends StatelessWidget {
  const MobileBudgetCategoryPage({
    required this.controller,
    required this.periodId,
    required this.categoryId,
    required this.onOpenFilteredTransactions,
    this.hidden = false,
    super.key,
  });
  final BudgetController controller;
  final String periodId;
  final String categoryId;
  final bool hidden;
  final ValueChanged<List<String>> onOpenFilteredTransactions;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final p = controller.periods.where((p) => p.id == periodId).firstOrNull;
      final category = controller.categories
          .where((c) => c.id == categoryId)
          .firstOrNull;
      if (p == null || category == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Категория')),
          body: const Center(
            child: Text('Категория или период больше не доступны'),
          ),
        );
      }
      final status =
          controller
              .categoryPlansFor(p)
              .where((s) => s.category.id == categoryId)
              .firstOrNull ??
          CategoryPlanStatus(
            category: category,
            spentAmount: 0,
            plannedAmount: 0,
          );
      return Scaffold(
        appBar: AppBar(title: Text(category.name)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${mobileBudgetPeriodLabel(p)} · ${formatDate(p.startDate)} — ${formatDate(controller.activeDateFor(p))}',
            ),
            MobileSection(
              title: 'План и факт категории',
              child: Column(
                children: [
                  MobileValueRow(
                    title: 'Расходы',
                    amount: status.spentAmount,
                    currency: p.currency,
                    hidden: hidden,
                  ),
                  if (status.hasAssignedBudget) ...[
                    MobileValueRow(
                      title: 'Лимит',
                      amount: status.plannedAmount,
                      currency: p.currency,
                      hidden: hidden,
                    ),
                    MobileValueRow(
                      title: status.isExceeded ? 'Превышение' : 'Осталось',
                      amount: status.remaining.abs(),
                      currency: p.currency,
                      hidden: hidden,
                      progress: status.progress,
                    ),
                  ] else
                    const Text('Лимит не назначен'),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => MobileBudgetLimitEditor(
                          controller: controller,
                          periodId: p.id,
                          categoryId: categoryId,
                        ),
                      ),
                    ),
                    child: const Text('Изменить лимит'),
                  ),
                ],
              ),
            ),
            FilledButton(
              key: const Key('mobile-budget-category-operations'),
              onPressed: () => onOpenFilteredTransactions(
                controller
                    .transactionsForCategory(p, categoryId)
                    .map((t) => t.id)
                    .toList(),
              ),
              child: const Text('Операции категории'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => CategoryDetailsScreen(
                    controller: controller,
                    period: p,
                    categoryId: categoryId,
                  ),
                ),
              ),
              child: const Text('Подробная аналитика категории'),
            ),
          ],
        ),
      );
    },
  );
}

/// UI-only editor: delegates persistence, stable identity and validation bounds
/// to existing budget commands. Opening/cancelling never writes a period.
class MobileBudgetLimitEditor extends StatefulWidget {
  const MobileBudgetLimitEditor({
    required this.controller,
    required this.periodId,
    this.categoryId,
    super.key,
  });
  final BudgetController controller;
  final String periodId;
  final String? categoryId;
  @override
  State<MobileBudgetLimitEditor> createState() =>
      _MobileBudgetLimitEditorState();
}

class _MobileBudgetLimitEditorState extends State<MobileBudgetLimitEditor> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: _initial.toString());
  late final int _initial = widget.categoryId == null
      ? period.totalPlan
      : widget.controller
                .categoryPlansFor(period)
                .where((s) => s.category.id == widget.categoryId)
                .firstOrNull
                ?.plannedAmount ??
            0;
  bool _saving = false;
  bool _error = false;
  BudgetPeriod get period =>
      widget.controller.periods.firstWhere((p) => p.id == widget.periodId);
  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final amount = int.parse(_amount.text.trim());
    setState(() {
      _saving = true;
      _error = false;
    });
    try {
      if (widget.categoryId == null) {
        await widget.controller.setTotalBudget(
          period: period,
          totalPlan: amount,
        );
      } else {
        await widget.controller.setCategoryBudget(
          period: period,
          categoryId: widget.categoryId!,
          plannedAmount: amount,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Лимит бюджета')),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(mobileBudgetPeriodLabel(period)),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('mobile-budget-limit-amount'),
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Лимит, ${period.currency}',
                helperText: '0 — убрать лимит',
              ),
              validator: (value) {
                final n = int.tryParse(value?.trim() ?? '');
                return n == null || n < 0 || n > 1000000000
                    ? 'Введите целую сумму от 0 до 1 000 000 000'
                    : null;
              },
            ),
            if (_error)
              const Text(
                'Не удалось сохранить. Проверьте данные и повторите попытку.',
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('mobile-budget-limit-save'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Сохранение…' : 'Сохранить'),
            ),
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    ),
  );
}
