import 'package:flutter/material.dart';

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
  late String _accountId;
  late bool _recurring;

  @override
  void initState() {
    super.initState();
    final expense = widget.expense;
    _titleController = TextEditingController(text: expense?.title ?? '');
    _amountController = TextEditingController(
      text: expense == null ? '' : expense.amount.toString(),
    );
    _date =
        expense?.plannedDate ??
        widget.controller
            .activeDateFor(widget.period)
            .add(const Duration(days: 1));
    if (_date.isAfter(widget.period.endDate)) _date = widget.period.endDate;
    _categoryId = expense?.categoryId;
    _accountId = expense?.accountId ?? widget.controller.accounts.first.id;
    _recurring = expense?.isRecurring ?? false;
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
    );
    if (selected != null && mounted) setState(() => _categoryId = selected.id);
  }

  Future<void> _chooseDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: widget.period.startDate,
      lastDate: widget.period.endDate,
    );
    if (value != null && mounted) setState(() => _date = value);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final amount = int.parse(_amountController.text.replaceAll(' ', ''));
    final current = widget.expense;
    if (current == null) {
      widget.controller.addUpcoming(
        UpcomingExpense(
          id: 'upcoming-${DateTime.now().microsecondsSinceEpoch}',
          userId: widget.period.userId,
          budgetPeriodId: widget.period.id,
          title: _titleController.text.trim(),
          amount: amount,
          currency: widget.period.currency,
          plannedDate: _date,
          categoryId: _categoryId,
          accountId: _accountId,
          isRecurring: _recurring,
          recurrenceRule: _recurring ? 'monthly' : null,
          source: UpcomingExpenseSource.manual,
        ),
      );
    } else {
      widget.controller.updateUpcoming(
        current.copyWith(
          title: _titleController.text.trim(),
          amount: amount,
          plannedDate: _date,
          categoryId: _categoryId,
          accountId: _accountId,
          isRecurring: _recurring,
          recurrenceRule: _recurring ? 'monthly' : null,
        ),
      );
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить предстоящий расход?'),
        content: const Text('Он исчезнет из списка текущего периода.'),
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
      widget.controller.deleteUpcoming(widget.expense!.id);
      Navigator.of(context).pop();
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
                      suffixText: currencySymbol(widget.period.currency),
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
                  DropdownButtonFormField<String>(
                    initialValue: _accountId,
                    decoration: const InputDecoration(
                      labelText: 'Счёт',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final account in widget.controller.accounts)
                        if (account.type != AccountType.liability)
                          DropdownMenuItem(
                            value: account.id,
                            child: Text(account.title),
                          ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _accountId = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _recurring,
                    onChanged: (value) => setState(() => _recurring = value),
                    title: const Text('Регулярный платёж'),
                    subtitle: const Text('Например, подписка или аренда'),
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
