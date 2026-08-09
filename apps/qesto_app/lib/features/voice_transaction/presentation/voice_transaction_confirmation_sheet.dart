import 'package:flutter/material.dart';

import '../../../core/formatters/qesto_formatters.dart';
import '../../../core/theme/qesto_theme.dart';
import '../../../core/widgets/qesto_card.dart';
import '../../../core/widgets/qesto_elements.dart';
import '../../../data/models/qesto_models.dart';
import '../../budget/state/budget_controller.dart';
import '../domain/voice_transaction_models.dart';

Future<bool?> showVoiceTransactionConfirmation({
  required BuildContext context,
  required BudgetController controller,
  required BudgetPeriod period,
  required VoiceTransactionDraft draft,
  required bool recognizedOnDevice,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: QestoColors.surface,
  builder: (_) => VoiceTransactionConfirmationSheet(
    controller: controller,
    period: period,
    draft: draft,
    recognizedOnDevice: recognizedOnDevice,
  ),
);

class VoiceTransactionConfirmationSheet extends StatefulWidget {
  const VoiceTransactionConfirmationSheet({
    required this.controller,
    required this.period,
    required this.draft,
    required this.recognizedOnDevice,
    super.key,
  });

  final BudgetController controller;
  final BudgetPeriod period;
  final VoiceTransactionDraft draft;
  final bool recognizedOnDevice;

  @override
  State<VoiceTransactionConfirmationSheet> createState() =>
      _VoiceTransactionConfirmationSheetState();
}

class _VoiceTransactionConfirmationSheetState
    extends State<VoiceTransactionConfirmationSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _titleController;
  late VoiceTransactionKind _kind;
  BudgetCategory? _category;
  late String _sourceAccountId;
  String? _destinationAccountId;
  bool _saving = false;

  List<QestoAccount> get _accounts => widget.controller.accounts
      .where((account) => account.type != AccountType.liability)
      .toList();

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.draft.amount.toString(),
    );
    _titleController = TextEditingController(text: widget.draft.title);
    _kind = widget.draft.kind;
    _category = widget.controller.categories
        .where((item) => item.id == widget.draft.categoryId)
        .firstOrNull;
    if (_kind == VoiceTransactionKind.expense && _category == null) {
      _category = widget.controller.categories
          .where((item) => item.id == 'other')
          .firstOrNull;
    }
    _sourceAccountId =
        _accounts
            .where((item) => item.id == widget.draft.sourceAccountId)
            .firstOrNull
            ?.id ??
        _accounts.first.id;
    _destinationAccountId = _accounts
        .where(
          (item) =>
              item.id == widget.draft.destinationAccountId &&
              item.id != _sourceAccountId,
        )
        .firstOrNull
        ?.id;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    if (_kind == VoiceTransactionKind.expense && _category == null) {
      _showError('Выберите категорию расхода');
      return;
    }
    if (_kind == VoiceTransactionKind.transfer &&
        _destinationAccountId == _sourceAccountId) {
      _showError('Счета перевода должны отличаться');
      return;
    }

    setState(() => _saving = true);
    final amount = int.parse(
      _amountController.text.replaceAll(RegExp(r'\s+'), ''),
    );
    final source = widget.controller.accountById(_sourceAccountId);
    final destination = _destinationAccountId == null
        ? null
        : widget.controller.accountById(_destinationAccountId!);
    final title = _titleController.text.trim().isEmpty
        ? _defaultTitle(_kind)
        : _titleController.text.trim();
    final date = widget.period.contains(DateTime.now())
        ? DateTime.now()
        : widget.controller.activeDateFor(widget.period);
    final details = [
      'Распознано из речи: «${widget.draft.rawText}»',
      if (destination != null) 'Получатель: ${destination.title}',
    ].join('\n');

    await widget.controller.addImportedTransactions([
      BudgetTransaction(
        id: 'voice-${DateTime.now().microsecondsSinceEpoch}',
        userId: widget.period.userId,
        accountId: source.id,
        date: date,
        amount: amount,
        currency: widget.period.currency,
        type: switch (_kind) {
          VoiceTransactionKind.expense => TransactionType.expense,
          VoiceTransactionKind.income => TransactionType.income,
          VoiceTransactionKind.transfer => TransactionType.transfer,
        },
        categoryId: _kind == VoiceTransactionKind.expense
            ? _category?.id
            : null,
        merchant: title,
        title: title,
        description: 'Добавлено голосом',
        comment: details,
        normalizedMerchant: _normalizeMerchant(title),
        transferDirection: _kind == VoiceTransactionKind.transfer
            ? TransferDirection.outgoing
            : null,
        tags: const ['voice-input'],
      ),
    ], actionTitle: 'Операция добавлена голосом');
    if (mounted) Navigator.of(context).pop(true);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Проверьте операцию',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              QestoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Распознано',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '«${widget.draft.rawText}»',
                      key: const Key('voice-recognized-text'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.recognizedOnDevice
                          ? 'Распознано на устройстве'
                          : 'Распознано системным сервисом Android',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<VoiceTransactionKind>(
                key: const Key('voice-kind-field'),
                isExpanded: true,
                initialValue: _kind,
                decoration: const InputDecoration(
                  labelText: 'Тип операции',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final kind in VoiceTransactionKind.values)
                    DropdownMenuItem(
                      value: kind,
                      child: Text(_kindLabel(kind)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _kind = value;
                    if (_kind == VoiceTransactionKind.expense &&
                        _category == null) {
                      _category = widget.controller.categories
                          .where((item) => item.id == 'other')
                          .firstOrNull;
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const Key('voice-amount-field'),
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Сумма',
                  suffixText: currencySymbol(widget.period.currency),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final amount = int.tryParse(
                    (value ?? '').replaceAll(RegExp(r'\s+'), ''),
                  );
                  return amount == null || amount <= 0
                      ? 'Введите сумму больше нуля'
                      : null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const Key('voice-title-field'),
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Название',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_kind == VoiceTransactionKind.expense) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: const Key('voice-category-field'),
                  isExpanded: true,
                  initialValue: _category?.id,
                  decoration: const InputDecoration(
                    labelText: 'Категория',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final category in widget.controller.categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _category = widget.controller.categories
                        .where((item) => item.id == value)
                        .firstOrNull;
                  }),
                ),
              ],
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: const Key('voice-source-account-field'),
                isExpanded: true,
                initialValue: _sourceAccountId,
                decoration: InputDecoration(
                  labelText: _kind == VoiceTransactionKind.transfer
                      ? 'Счёт списания'
                      : 'Счёт',
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final account in _accounts)
                    DropdownMenuItem(
                      value: account.id,
                      child: Text(account.title),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _sourceAccountId = value;
                    if (_destinationAccountId == value) {
                      _destinationAccountId = null;
                    }
                  });
                },
              ),
              if (_kind == VoiceTransactionKind.transfer) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  key: const Key('voice-destination-account-field'),
                  isExpanded: true,
                  initialValue: _destinationAccountId,
                  decoration: const InputDecoration(
                    labelText: 'Счёт зачисления (необязательно)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Другой счёт'),
                    ),
                    for (final account in _accounts)
                      if (account.id != _sourceAccountId)
                        DropdownMenuItem<String?>(
                          value: account.id,
                          child: Text(account.title),
                        ),
                  ],
                  onChanged: (value) =>
                      setState(() => _destinationAccountId = value),
                ),
              ],
              const SizedBox(height: 14),
              QestoButton(
                key: const Key('save-voice-transaction'),
                label: _saving ? 'Сохраняем…' : 'Добавить операцию',
                icon: Icons.check_circle_rounded,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _kindLabel(VoiceTransactionKind kind) => switch (kind) {
  VoiceTransactionKind.expense => 'Расход',
  VoiceTransactionKind.income => 'Доход',
  VoiceTransactionKind.transfer => 'Перевод',
};

String _defaultTitle(VoiceTransactionKind kind) => switch (kind) {
  VoiceTransactionKind.expense => 'Расход',
  VoiceTransactionKind.income => 'Доход',
  VoiceTransactionKind.transfer => 'Перевод между счетами',
};

String _normalizeMerchant(String value) => value
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
    .trim();
