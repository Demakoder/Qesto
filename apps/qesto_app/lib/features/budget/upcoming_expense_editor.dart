import 'package:flutter/material.dart';
import '../classification/classification_actions.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../core/widgets/nested_screen_header.dart';
import '../../core/widgets/qesto_card.dart';
import '../../core/widgets/qesto_elements.dart';
import '../../data/models/qesto_models.dart';
import 'category_picker.dart';
import 'state/budget_controller.dart';

class UpcomingExpenseEditor extends StatefulWidget {
  const UpcomingExpenseEditor({
    required this.controller,
    required this.period,
    this.expense,
    super.key,
  });

  final BudgetController controller;
  final BudgetPeriod period;
  final UpcomingExpense? expense;

  @override
  State<UpcomingExpenseEditor> createState() => _UpcomingExpenseEditorState();
}

class _UpcomingExpenseEditorState extends State<UpcomingExpenseEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late DateTime _date;
  String? _categoryId;
  String? _accountId;
  String? _recurrenceRule;
  late String _currency;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    _titleController = TextEditingController(text: expense?.title ?? '');
    _amountController = TextEditingController(
      text: expense == null ? '' : expense.amount.toString(),
    );
    final now = DateTime.now();
    _date = expense?.plannedDate ?? DateTime(now.year, now.month, now.day + 1);
    _categoryId = expense?.categoryId;
    final availableAccounts = widget.controller.accounts
        .where(
          (item) =>
              item.userId == widget.controller.user.id &&
              item.type != AccountType.liability,
        )
        .toList();
    _accountId = availableAccounts.any((item) => item.id == expense?.accountId)
        ? expense?.accountId
        : null;
    _currency = expense?.currency ?? widget.period.currency;
    _recurrenceRule = expense?.isRecurring == true
        ? expense?.recurrenceRule ?? 'monthly'
        : null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _chooseCategory() async {
    final selected = await showBudgetCategoryPicker(
      context: context,
      categories: widget.controller.categories,
      recentCategoryIds: const [],
      onCreate: () => editCategory(context, widget.controller),
    );
    if (selected != null && mounted) setState(() => _categoryId = selected.id);
  }

  Future<void> _chooseDate() async {
    final today = DateTime.now();
    final firstDay = DateTime(today.year, today.month, today.day);
    final earliest = _date.isBefore(firstDay) ? _date : firstDay;
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: earliest,
      lastDate: DateTime(today.year + 20, 12, 31),
    );
    if (value != null && mounted) setState(() => _date = value);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = int.parse(_amountController.text.replaceAll(' ', ''));
    final current = widget.expense;
    final period = widget.controller.periodForOrCreate(_date);
    try {
      if (current == null) {
        await widget.controller.addUpcoming(
          UpcomingExpense(
            id: 'upcoming-${DateTime.now().microsecondsSinceEpoch}',
            userId: widget.controller.user.id,
            budgetPeriodId: period.id,
            title: _titleController.text.trim(),
            amount: amount,
            currency: _currency,
            plannedDate: _date,
            categoryId: _categoryId,
            accountId: _accountId,
            isRecurring: _recurrenceRule != null,
            recurrenceRule: _recurrenceRule,
            source: UpcomingExpenseSource.manual,
          ),
        );
      } else {
        await widget.controller.updateUpcoming(
          current.copyWith(
            budgetPeriodId: period.id,
            title: _titleController.text.trim(),
            amount: amount,
            currency: _currency,
            plannedDate: _date,
            categoryId: _categoryId,
            accountId: _accountId,
            clearAccountId: _accountId == null,
            isRecurring: _recurrenceRule != null,
            recurrenceRule: _recurrenceRule,
            clearRecurrenceRule: _recurrenceRule == null,
          ),
        );
      }
    } catch (error) {
      debugPrint('Upcoming expense save failed: ${error.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось сохранить платёж. Попробуйте ещё раз.'),
          ),
        );
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить предстоящий расход?'),
        content: const Text(
          'План исчезнет, фактические операции не изменятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await widget.controller.deleteUpcoming(widget.expense!.id);
        if (mounted) Navigator.of(context).pop();
      } catch (error) {
        debugPrint('Upcoming expense delete failed: ${error.runtimeType}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось удалить платёж. Попробуйте ещё раз.'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = _categoryId == null
        ? null
        : widget.controller.categoryById(_categoryId!);
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text(
          widget.expense == null
              ? 'Новая предстоящая трата'
              : 'Предстоящая трата',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
          children: [
            QestoCard(
              child: Column(
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Название',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Введите название'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Сумма',
                      suffixText: currencySymbol(_currency),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final amount = int.tryParse(
                        (value ?? '').replaceAll(' ', ''),
                      );
                      return amount == null || amount <= 0
                          ? 'Введите сумму'
                          : null;
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(
                      labelText: 'Валюта',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final currency in {
                        'RUB',
                        'USD',
                        'EUR',
                        'CNY',
                        widget.controller.user.defaultCurrency,
                        ...widget.controller.accounts.map(
                          (account) => account.currency,
                        ),
                        _currency,
                      })
                        DropdownMenuItem(
                          value: currency,
                          child: Text(currency),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _currency = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: _chooseDate,
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: const Text('Дата'),
                    subtitle: Text(formatDate(_date, includeYear: true)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: _chooseCategory,
                    leading: const Icon(Icons.category_outlined),
                    title: const Text('Категория'),
                    subtitle: Text(category?.name ?? 'Не выбрана'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                  DropdownButtonFormField<String?>(
                    initialValue: _accountId,
                    decoration: const InputDecoration(
                      labelText: 'Счёт',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Не выбран'),
                      ),
                      for (final account in widget.controller.accounts)
                        if (account.userId == widget.controller.user.id &&
                            account.type != AccountType.liability)
                          DropdownMenuItem(
                            value: account.id,
                            child: Text(account.title),
                          ),
                    ],
                    onChanged: (value) => setState(() => _accountId = value),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: _recurrenceRule,
                    decoration: const InputDecoration(
                      labelText: 'Повторение',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('Не повторять'),
                      ),
                      DropdownMenuItem(
                        value: 'weekly',
                        child: Text('Еженедельно'),
                      ),
                      DropdownMenuItem(
                        value: 'biweekly',
                        child: Text('Раз в две недели'),
                      ),
                      DropdownMenuItem(
                        value: 'monthly',
                        child: Text('Ежемесячно'),
                      ),
                      DropdownMenuItem(
                        value: 'bimonthly',
                        child: Text('Раз в два месяца'),
                      ),
                      DropdownMenuItem(
                        value: 'quarterly',
                        child: Text('Ежеквартально'),
                      ),
                      DropdownMenuItem(
                        value: 'halfYearly',
                        child: Text('Раз в полгода'),
                      ),
                      DropdownMenuItem(
                        value: 'yearly',
                        child: Text('Ежегодно'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _recurrenceRule = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            QestoButton(
              label: 'Сохранить',
              icon: Icons.check_circle_rounded,
              onPressed: _save,
            ),
            if (widget.expense != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Удалить'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.qestoColors.danger,
                  minimumSize: const Size.fromHeight(54),
                ),
              ),
              if (widget.expense!.source == UpcomingExpenseSource.subscription)
                TextButton(
                  onPressed: () {
                    widget.controller.updateUpcoming(
                      widget.expense!.copyWith(isCancelled: true),
                    );
                    Navigator.of(context).pop();
                  },
                  child: const Text('Отметить подписку отменённой'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
