import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../core/widgets/nested_screen_header.dart';
import '../../core/widgets/qesto_card.dart';
import '../../core/widgets/qesto_elements.dart';
import '../../data/models/qesto_models.dart';
import 'category_picker.dart';
import 'state/budget_controller.dart';
import 'widgets/budget_category_icon.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({
    required this.controller,
    required this.period,
    this.initialTransaction,
    this.addInitialAsNew = false,
    super.key,
  });

  final BudgetController controller;
  final BudgetPeriod period;
  final BudgetTransaction? initialTransaction;
  final bool addInitialAsNew;

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _titleController;
  late final TextEditingController _commentController;
  late DateTime _date;
  late String _accountId;
  BudgetCategory? _category;
  String? _subcategory;

  bool get _editing =>
      widget.initialTransaction != null && !widget.addInitialAsNew;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTransaction;
    _amountController = TextEditingController(
      text: initial == null ? '' : initial.amount.toString(),
    );
    _titleController = TextEditingController(
      text: initial?.merchant ?? initial?.title ?? '',
    );
    _commentController = TextEditingController(text: initial?.comment ?? '');
    _date = initial?.date ?? widget.controller.activeDateFor(widget.period);
    _accountId = initial?.accountId ?? widget.controller.accounts.first.id;
    if (initial?.categoryId != null) {
      _category = widget.controller.categoryById(initial!.categoryId!);
      _subcategory = initial.subcategoryId;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _titleController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  List<String> get _recentCategoryIds {
    final result = <String>[];
    for (final transaction in widget.controller.transactions.reversed) {
      final id = transaction.categoryId;
      if (id != null && !result.contains(id)) result.add(id);
    }
    return result;
  }

  Future<void> _selectCategory() async {
    final selected = await showBudgetCategoryPicker(
      context: context,
      categories: widget.controller.categories,
      recentCategoryIds: _recentCategoryIds,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _category = selected;
      _subcategory = selected.subcategories.firstOrNull;
    });
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: widget.period.startDate,
      lastDate: widget.period.endDate,
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите категорию расхода')),
      );
      return;
    }
    final amount = int.parse(_amountController.text.replaceAll(' ', ''));
    final title = _titleController.text.trim().isEmpty
        ? _category!.name
        : _titleController.text.trim();
    final initial = widget.initialTransaction;
    if (initial == null || widget.addInitialAsNew) {
      widget.controller.addExpense(
        period: widget.period,
        amount: amount,
        date: _date,
        categoryId: _category!.id,
        accountId: _accountId,
        title: title,
        subcategoryId: _subcategory,
        comment: _commentController.text.trim(),
      );
    } else {
      widget.controller.updateTransaction(
        initial.copyWith(
          amount: amount,
          date: _date,
          categoryId: _category!.id,
          accountId: _accountId,
          merchant: title,
          title: title,
          subcategoryId: _subcategory,
          comment: _commentController.text.trim(),
        ),
      );
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final category = _category;
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text(
          _editing ? 'Редактировать расход' : 'Добавить расход',
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
                    key: const Key('expense-amount-field'),
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
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
                          ? 'Введите сумму больше нуля'
                          : null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: const Key('expense-title-field'),
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Магазин или название',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _FormTile(
                    title: 'Категория',
                    value: category?.name ?? 'Выбрать',
                    icon: category == null
                        ? const Icon(Icons.category_outlined)
                        : BudgetCategoryIcon(
                            iconKey: category.iconKey,
                            color: Color(category.colorValue),
                            size: 40,
                          ),
                    onTap: _selectCategory,
                  ),
                  if (category != null &&
                      category.subcategories.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _subcategory,
                      decoration: const InputDecoration(
                        labelText: 'Подкатегория',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final item in category.subcategories)
                          DropdownMenuItem(value: item, child: Text(item)),
                      ],
                      onChanged: (value) =>
                          setState(() => _subcategory = value),
                    ),
                  ],
                  const SizedBox(height: 10),
                  _FormTile(
                    title: 'Дата',
                    value: formatDate(_date, includeYear: true),
                    icon: const Icon(Icons.calendar_month_outlined),
                    onTap: _selectDate,
                  ),
                  const SizedBox(height: 10),
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
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _commentController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Комментарий',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            QestoButton(
              label: _editing ? 'Сохранить изменения' : 'Сохранить расход',
              icon: Icons.check_circle_rounded,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _FormTile extends StatelessWidget {
  const _FormTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String value;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.qestoColors.background,
      borderRadius: QestoGeometry.control,
      child: InkWell(
        onTap: onTap,
        borderRadius: QestoGeometry.control,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                SizedBox(width: 40, height: 40, child: Center(child: icon)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        value,
                        style: const TextStyle(fontWeight: FontWeight.w700),
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
          ),
        ),
      ),
    );
  }
}
