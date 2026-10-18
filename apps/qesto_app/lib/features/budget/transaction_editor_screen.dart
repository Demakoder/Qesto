import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../data/models/qesto_models.dart';
import '../../synoball/enrichment/category_policy.dart';
import '../classification/classification_actions.dart';
import 'state/budget_controller.dart';

/// Shared presentation over BudgetTransaction, not a second financial model.
/// Draft correction returns a value only; intake owns explicit confirmation.
class TransactionEditorScreen extends StatefulWidget {
  const TransactionEditorScreen({
    required this.controller,
    required this.initialTransaction,
    this.draftOnly = false,
    this.onSubmit,
    this.saveLabel = 'Сохранить',
    super.key,
  });

  final BudgetController controller;
  final BudgetTransaction initialTransaction;
  final bool draftOnly;
  final Future<void> Function(BudgetTransaction)? onSubmit;
  final String saveLabel;

  @override
  State<TransactionEditorScreen> createState() =>
      _TransactionEditorScreenState();
}

class _TransactionEditorScreenState extends State<TransactionEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: minorAmountInput(widget.initialTransaction.amountMinor),
  );
  late final _merchant = TextEditingController(
    text:
        widget.initialTransaction.merchant ??
        widget.initialTransaction.title ??
        '',
  );
  late final _comment = TextEditingController(
    text: widget.initialTransaction.comment ?? '',
  );
  late DateTime _date = widget.initialTransaction.date;
  late String _account = widget.initialTransaction.accountId;
  late String? _category = widget.initialTransaction.categoryId;
  late String? _subcategory = widget.initialTransaction.subcategoryId;
  late bool _reviewed = widget.initialTransaction.isConfirmed;
  late final Set<String> _tags = widget.initialTransaction.tags
      .where((tag) => tag.startsWith(userLabelPrefix))
      .toSet();
  bool _saving = false;
  bool _leaving = false;
  bool _askingDiscard = false;
  bool _confirmCategory = false;
  String? _error;

  bool get _bankPending => widget.initialTransaction.tags.any(
    (tag) => tag == 'sber-status-pending' || tag == 'status-pending',
  );

  bool get _dirty {
    final initial = widget.initialTransaction;
    // A new manual draft starts at zero (invalid for Save, but unchanged).
    // Invalid initial text alone must not trigger discard confirmation.
    return (_amount.text != minorAmountInput(initial.amountMinor) &&
            parseMinorAmount(_amount.text) != initial.amountMinor) ||
        _merchant.text != (initial.merchant ?? initial.title ?? '') ||
        _comment.text != (initial.comment ?? '') ||
        _date != initial.date ||
        _account != initial.accountId ||
        _category != initial.categoryId ||
        _subcategory != initial.subcategoryId ||
        _reviewed != initial.isConfirmed ||
        _confirmCategory ||
        !_tags.containsAll(
          initial.tags.where((tag) => tag.startsWith(userLabelPrefix)),
        ) ||
        _tags.length !=
            initial.tags.where((tag) => tag.startsWith(userLabelPrefix)).length;
  }

  @override
  void initState() {
    super.initState();
    for (final field in [_amount, _merchant, _comment]) {
      field.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _back() async {
    if (_saving || _askingDiscard || _leaving) return;
    if (_dirty) {
      _askingDiscard = true;
      final discard = await confirmClassification(
        context,
        'Отменить изменения?',
        'Несохранённые изменения будут потеряны.',
        action: 'Не сохранять',
      );
      _askingDiscard = false;
      if (!discard || !mounted) return;
    }
    if (mounted) {
      setState(() => _leaving = true);
      Navigator.of(context).pop();
    }
  }

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(
        () => _date = DateTime(
          selected.year,
          selected.month,
          selected.day,
          _date.hour,
          _date.minute,
          _date.second,
          _date.millisecond,
          _date.microsecond,
        ),
      );
    }
  }

  Future<void> _chooseTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (selected != null && mounted) {
      setState(
        () => _date = DateTime(
          _date.year,
          _date.month,
          _date.day,
          selected.hour,
          selected.minute,
          _date.second,
          _date.millisecond,
          _date.microsecond,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final validAccount = widget.controller.accounts.any(
      (a) => a.id == _account,
    );
    if (!validAccount) {
      setState(() => _error = 'Выберите доступный счёт операции');
      return;
    }
    if (widget.draftOnly && _category == null) {
      setState(() => _error = 'Для этого импорта выберите категорию');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Merge presentation changes into the latest canonical read model. Keep
      // bank/system tags, type, direction, receipt and identity untouched.
      final initial = widget.initialTransaction;
      final current = widget.draftOnly
          ? initial
          : widget.controller.transactions
                .where((t) => t.id == initial.id)
                .firstOrNull;
      if (current == null) {
        throw StateError('Операция удалена. Вернитесь к списку.');
      }
      if (current.type != initial.type ||
          current.transferDirection != initial.transferDirection) {
        throw StateError('Тип операции изменился. Откройте редактор заново.');
      }
      final minor = parseMinorAmount(_amount.text)!;
      final merchant = _merchant.text.trim();
      final categoryChanged = _category != initial.categoryId;
      final updated = BudgetTransaction(
        id: current.id,
        userId: current.userId,
        accountId: _account,
        date: _date,
        amount: (minor + 50) ~/ 100,
        exactAmountMinor: minor,
        currency: current.currency,
        type: current.type,
        transferDirection: current.transferDirection,
        categoryId: _category,
        subcategoryId: _subcategory,
        merchant: merchant,
        title: merchant,
        normalizedMerchant: merchant == (current.merchant ?? current.title)
            ? current.normalizedMerchant
            : merchant.toLowerCase(),
        description: current.description,
        comment: _comment.text.trim(),
        originalCategoryId: current.originalCategoryId,
        isLargePurchase: current.isLargePurchase,
        isRecurring: current.isRecurring,
        isPotentialDuplicate: current.isPotentialDuplicate,
        isConfirmed: _bankPending ? current.isConfirmed : _reviewed,
        classificationConfidence: categoryChanged || _confirmCategory
            ? 1
            : current.classificationConfidence,
        tags: [
          ...current.tags.where((tag) => !tag.startsWith(userLabelPrefix)),
          ..._tags,
        ],
        receipt: current.receipt,
      );
      if (widget.onSubmit case final submit?) {
        await submit(updated);
      } else if (!widget.draftOnly) {
        await widget.controller.updateTransaction(updated);
      }
      if (mounted) {
        setState(() => _leaving = true);
        Navigator.of(context).pop(updated);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is StateError
              ? error.message
              : 'Не удалось сохранить. Изменения оставлены, повторите попытку.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.controller.categories;
    final category = categories.where((c) => c.id == _category).firstOrNull;
    final accounts = widget.controller.accounts;
    return PopScope<BudgetTransaction>(
      canPop: _leaving || (!_dirty && !_saving),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        key: const Key('transaction-editor'),
        appBar: AppBar(
          leading: IconButton(
            key: const Key('transaction-editor-back'),
            onPressed: _saving ? null : _back,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            widget.draftOnly ? 'Проверить операцию' : 'Редактировать операцию',
          ),
        ),
        body: SafeArea(
          top: false,
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    title: Text(
                      transactionTypeLabel(widget.initialTransaction),
                    ),
                    subtitle: const Text(
                      'Тип и направление сохраняются без изменений',
                    ),
                    leading: const Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('transaction-amount'),
                  controller: _amount,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Сумма',
                    suffixText: widget.initialTransaction.currency,
                  ),
                  validator: (value) => parseMinorAmount(value ?? '') == null
                      ? 'Введите сумму больше нуля, максимум 2 знака после запятой'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('transaction-merchant'),
                  controller: _merchant,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Продавец / отправитель / получатель',
                  ),
                  validator: (value) => value?.trim().isEmpty != false
                      ? 'Укажите название'
                      : null,
                ),
                const SizedBox(height: 8),
                ListTile(
                  key: const Key('transaction-date'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Дата'),
                  subtitle: Text(formatDate(_date, includeYear: true)),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: _saving ? null : _chooseDate,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Время'),
                  subtitle: Text(
                    '${_date.hour.toString().padLeft(2, '0')}:${_date.minute.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.schedule),
                  onTap: _saving ? null : _chooseTime,
                ),
                DropdownButtonFormField<String>(
                  key: const Key('transaction-account'),
                  initialValue: accounts.any((a) => a.id == _account)
                      ? _account
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Счёт'),
                  items: [
                    for (final a in accounts)
                      DropdownMenuItem(
                        value: a.id,
                        child: Text(a.title, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _account = value);
                        },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey('transaction-category-$_category'),
                  initialValue: category?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Категория'),
                  items: [
                    if (widget.initialTransaction.categoryId == null)
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Без категории'),
                      ),
                    for (final c in categories)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _category = value == '' ? null : value;
                          _subcategory = null;
                        }),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'transaction-subcategory-$_category-$_subcategory',
                  ),
                  initialValue:
                      category?.subcategories.contains(_subcategory) == true
                      ? _subcategory
                      : '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Подкатегория'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Не указана'),
                    ),
                    for (final sub in category?.subcategories ?? <String>[])
                      DropdownMenuItem(value: sub, child: Text(sub)),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                          () => _subcategory = value == '' ? null : value,
                        ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('transaction-comment'),
                  controller: _comment,
                  enabled:
                      !_saving &&
                      (!widget.draftOnly || widget.onSubmit != null),
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Комментарий',
                    helperText: widget.draftOnly && widget.onSubmit == null
                        ? 'Доступен после импорта операции'
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                if (!widget.draftOnly) ...[
                  const Text('Теги'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final tag in widget.controller.classification.tags)
                        FilterChip(
                          label: Text(tag.name),
                          selected: _tags.contains('$userLabelPrefix${tag.id}'),
                          onSelected: _saving
                              ? null
                              : (selected) => setState(() {
                                  final id = '$userLabelPrefix${tag.id}';
                                  selected ? _tags.add(id) : _tags.remove(id);
                                }),
                        ),
                    ],
                  ),
                ],
                SwitchListTile(
                  key: const Key('transaction-reviewed'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Данные проверены'),
                  subtitle: _bankPending
                      ? const Text(
                          'Банковская обработка не подтверждается вручную',
                        )
                      : null,
                  value: _reviewed,
                  onChanged: _saving || _bankPending || widget.draftOnly
                      ? null
                      : (value) => setState(() => _reviewed = value),
                ),
                CheckboxListTile(
                  key: const Key('transaction-category-confirmed'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Категория определена верно'),
                  value: _confirmCategory,
                  onChanged: _saving || _category == null
                      ? null
                      : (value) =>
                            setState(() => _confirmCategory = value ?? false),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error!,
                        key: const Key('transaction-editor-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('transaction-save'),
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(_saving ? 'Сохраняем…' : widget.saveLabel),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

int? parseMinorAmount(String input) {
  final normalized = input
      .trim()
      .replaceAll(RegExp(r'[\s\u00a0\u202f]'), '')
      .replaceAll(',', '.');
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null || whole > 90000000000000) return null;
  final minor =
      whole * 100 +
      (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
  return minor > 0 ? minor : null;
}

String minorAmountInput(int minor) =>
    '${minor.abs() ~/ 100},${(minor.abs() % 100).toString().padLeft(2, '0')}';

String transactionTypeLabel(BudgetTransaction t) => switch (t.type) {
  TransactionType.expense => 'Расход',
  TransactionType.income => 'Доход',
  TransactionType.refund => 'Возврат',
  TransactionType.transfer => switch (t.transferDirection) {
    TransferDirection.incoming => 'Входящий перевод',
    TransferDirection.outgoing => 'Исходящий перевод',
    null => 'Перевод между счетами',
  },
  TransactionType.savingsTransfer => 'Перевод в накопления',
  TransactionType.investment => 'Инвестиционная операция',
};
