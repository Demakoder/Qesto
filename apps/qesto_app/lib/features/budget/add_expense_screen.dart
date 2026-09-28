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
import 'widgets/budget_category_icon.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({
    required this.controller,
    required this.period,
    this.initialTransaction,
    this.attentionReasons = const [],
    this.addInitialAsNew = false,
    super.key,
  });

  final BudgetController controller;
  final BudgetPeriod period;
  final BudgetTransaction? initialTransaction;
  final List<String> attentionReasons;
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
  String? _accountId;
  BudgetCategory? _category;
  String? _subcategory;
  late bool _reviewed;
  bool _confirmClassification = false;
  bool _saving = false;

  bool get _editing =>
      widget.initialTransaction != null && !widget.addInitialAsNew;

  bool get _bankPending =>
      widget.initialTransaction?.tags.contains('sber-status-pending') == true ||
      widget.initialTransaction?.tags.contains('status-pending') == true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialTransaction;
    _reviewed = initial?.isConfirmed ?? true;
    _amountController = TextEditingController(
      text: initial == null
          ? ''
          : initial.amountMinor % 100 == 0
          ? (initial.amountMinor ~/ 100).toString()
          : '${initial.amountMinor ~/ 100},${(initial.amountMinor % 100).toString().padLeft(2, '0')}',
    );
    _titleController = TextEditingController(
      text: initial?.merchant ?? initial?.title ?? '',
    );
    _commentController = TextEditingController(text: initial?.comment ?? '');
    _date = initial?.date ?? widget.controller.activeDateFor(widget.period);
    final selectableAccounts = widget.controller.accounts
        .where((account) => account.type != AccountType.liability)
        .toList();
    _accountId =
        selectableAccounts.any((account) => account.id == initial?.accountId)
        ? initial!.accountId
        : initial == null
        ? selectableAccounts.firstOrNull?.id
        : null;
    if (initial?.categoryId != null) {
      _category = widget.controller.categories
          .where((category) => category.id == initial!.categoryId)
          .firstOrNull;
      _subcategory = initial?.subcategoryId;
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
      onCreate: () => editCategory(context, widget.controller),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _category = selected;
      _subcategory = selected.subcategories.firstOrNull;
    });
  }

  Future<void> _selectDate() async {
    final firstDate = _date.isBefore(widget.period.startDate)
        ? _date
        : widget.period.startDate;
    final lastDate = _date.isAfter(widget.period.endDate)
        ? _date
        : widget.period.endDate;
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    final initial = widget.initialTransaction;
    if (_category == null &&
        (initial == null || initial.type == TransactionType.expense)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите категорию расхода')),
      );
      return;
    }
    if (_accountId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Выберите счёт операции')));
      return;
    }
    final amountMinor = _parseAmountMinor(_amountController.text)!;
    final amount = (amountMinor + 50) ~/ 100;
    final title = _titleController.text.trim().isEmpty
        ? _category?.name ?? initial?.title ?? 'Операция'
        : _titleController.text.trim();
    setState(() => _saving = true);
    try {
      if (initial == null || widget.addInitialAsNew) {
        await widget.controller.addExpense(
          period: widget.period,
          amount: amount,
          date: _date,
          categoryId: _category!.id,
          accountId: _accountId!,
          title: title,
          subcategoryId: _subcategory,
          comment: _commentController.text.trim(),
        );
      } else {
        await widget.controller.updateTransaction(
          initial.copyWith(
            amount: amount,
            exactAmountMinor: amountMinor,
            date: _date,
            categoryId: _category?.id,
            accountId: _accountId!,
            merchant: title,
            title: title,
            normalizedMerchant: title != (initial.merchant ?? initial.title)
                ? title.toLowerCase()
                : initial.normalizedMerchant,
            classificationConfidence:
                _confirmClassification || _category?.id != initial.categoryId
                ? 1
                : initial.classificationConfidence,
            isConfirmed: _reviewed,
            subcategoryId: _subcategory,
            comment: _commentController.text.trim(),
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить операцию')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = _category;
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text(
          _editing ? 'Редактировать операцию' : 'Добавить расход',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
          children: [
            if (widget.attentionReasons.isNotEmpty)
              QestoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Почему Qesto просит проверить операцию',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    for (final reason in widget.attentionReasons)
                      Text('• $reason'),
                  ],
                ),
              ),
            if (widget.attentionReasons.isNotEmpty) const SizedBox(height: 12),
            QestoCard(
              child: Column(
                children: [
                  TextFormField(
                    key: const Key('expense-amount-field'),
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Сумма',
                      suffixText: currencySymbol(
                        widget.initialTransaction?.currency ??
                            widget.period.currency,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final amount = _parseAmountMinor(value ?? '');
                      return amount == null || amount <= 0
                          ? 'Введите сумму больше нуля'
                          : !_editing && amount % 100 != 0
                          ? 'Для нового расхода укажите целую сумму'
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
                  if (_editing)
                    SwitchListTile.adaptive(
                      key: const Key('expense-review-switch'),
                      title: const Text('Операция проверена'),
                      subtitle: _bankPending
                          ? const Text('Ожидает проведения банком')
                          : null,
                      value: _reviewed,
                      onChanged: _bankPending
                          ? null
                          : (value) => setState(() => _reviewed = value),
                    ),
                  if (_editing &&
                      widget.initialTransaction!.classificationConfidence < 0.6)
                    SwitchListTile.adaptive(
                      key: const Key('expense-classification-confirm-switch'),
                      title: const Text('Категория проверена'),
                      subtitle: const Text('Подтвердите её после проверки'),
                      value: _confirmClassification,
                      onChanged: (value) =>
                          setState(() => _confirmClassification = value),
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

int? _parseAmountMinor(String raw) {
  final normalized = raw
      .replaceAll(RegExp(r'[\s\u00a0\u202f]'), '')
      .replaceAll(',', '.');
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final major = int.tryParse(parts[0]);
  if (major == null) return null;
  final cents = parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0;
  return major * 100 + cents;
}
