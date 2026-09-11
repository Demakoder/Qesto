import 'package:flutter/material.dart';

import '../../../core/theme/qesto_theme.dart';
import '../../../core/widgets/nested_screen_header.dart';
import '../../../data/models/qesto_models.dart';
import '../../budget/state/budget_controller.dart';
import '../../transaction_import/services/transaction_account_resolver.dart';
import '../data/bank_screenshot_scanner_service.dart';
import '../domain/bank_screenshot_models.dart';
import '../services/bank_screenshot_import_service.dart';
import '../services/bank_screenshot_identity.dart';

class BankScreenshotImportScreen extends StatefulWidget {
  const BankScreenshotImportScreen({
    required this.controller,
    this.scanner = const BankScreenshotScannerService(),
    this.importService = const BankScreenshotImportService(),
    super.key,
  });

  final BudgetController controller;
  final BankScreenshotScannerGateway scanner;
  final BankScreenshotImportService importService;

  @override
  State<BankScreenshotImportScreen> createState() =>
      _BankScreenshotImportScreenState();
}

class _BankScreenshotImportScreenState
    extends State<BankScreenshotImportScreen> {
  var _loading = false;
  var _saving = false;
  String? _error;
  List<String> _warnings = const [];
  List<BankScreenshotCandidate> _candidates = const [];
  String? _batchAccountId;

  List<QestoAccount> get _accounts => widget.controller.accounts
      .where((account) => account.type != AccountType.liability)
      .toList(growable: false);

  Future<void> _scan() async {
    if (_loading || !widget.scanner.isSupported) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final documents = await widget.scanner.pickAndRecognize();
      if (!mounted) return;
      if (documents.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final parsed = widget.importService.parseAll(documents);
      final resolved = parsed.candidates
          .map((candidate) {
            final account = const TransactionAccountResolver().resolve(
              accounts: _accounts,
              accountHint: candidate.accountHint,
              bankHint: candidate.parserId.startsWith('sber') ? 'sber' : null,
              currency: candidate.currency,
            );
            return _reviewIdentity(
              candidate.copyWith(accountId: account?.accountId),
            );
          })
          .toList(growable: false);
      final resolvedAccountIds = resolved
          .map((candidate) => candidate.accountId)
          .whereType<String>()
          .toSet();
      setState(() {
        _loading = false;
        _warnings = parsed.warnings;
        _candidates = resolved;
        _batchAccountId = resolvedAccountIds.length == 1
            ? resolvedAccountIds.single
            : null;
        if (resolved.isEmpty) {
          _error =
              'На скриншотах не найдены операции. '
              'Проверьте, что видны суммы и типы операций.';
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось локально распознать скриншоты';
      });
    }
  }

  void _setBatchAccount(String? accountId) {
    if (accountId == null) return;
    setState(() {
      _batchAccountId = accountId;
      _candidates = _candidates
          .map(
            (candidate) =>
                _reviewIdentity(candidate.copyWith(accountId: accountId)),
          )
          .toList(growable: false);
    });
  }

  BankScreenshotCandidate _reviewIdentity(BankScreenshotCandidate row) {
    final identity = resolveScreenshotIdentity(
      row,
      widget.controller.synoballState,
    );
    return identity.reviewReason == null
        ? row
        : row.copyWith(
            selected: false,
            possibleDuplicateReason: identity.reviewReason,
          );
  }

  Future<void> _edit(int index) async {
    final edited = await showDialog<BankScreenshotCandidate>(
      context: context,
      builder: (context) => _CandidateEditor(
        candidate: _candidates[index],
        accounts: _accounts,
        categories: widget.controller.categories,
      ),
    );
    if (edited == null || !mounted) return;
    setState(() {
      final updated = _candidates.toList();
      updated[index] = edited;
      _candidates = updated;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final selected = _candidates.where((candidate) => candidate.selected);
    if (selected.isEmpty) return;
    if (selected.any((candidate) => candidate.accountId == null)) {
      setState(() => _error = 'Выберите счёт для импорта');
      return;
    }
    setState(() => _saving = true);
    try {
      final outcome = await widget.controller.importBankScreenshotCandidates(
        selected,
      );
      if (!mounted) return;
      final added = outcome.createdTransactionIds.length;
      final merged = outcome.matchedTransactionIds.length;
      final unresolved =
          outcome.pendingCandidateIds.length +
          outcome.failedCandidateIds.length;
      if (unresolved > 0) {
        setState(() {
          _saving = false;
          _error =
              'Добавлено: $added, дополнено: $merged. '
              'Требуют проверки / не приняты: $unresolved. '
              'Импорт завершён не полностью.';
        });
        return;
      }
      Navigator.of(context).pop(
        'Добавлено: $added, дополнено без дублей: $merged'
        '${outcome.suppressedTransactionIds.isEmpty ? '' : ', в корзине: ${outcome.suppressedTransactionIds.length}'}',
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Не удалось сохранить операции';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _candidates.where((item) => item.selected).length;
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text(
          'Скриншоты банка',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Выберите до 10 скриншотов истории операций. '
                  'OCR работает на устройстве; изображения и исходный текст '
                  'не сохраняются в Synoball.',
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    key: const Key('pick-bank-screenshots'),
                    onPressed: _loading ? null : _scan,
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      _loading ? 'Распознавание…' : 'Выбрать скриншоты',
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: const TextStyle(color: QestoColors.orange),
                  ),
                ],
                for (final warning in _warnings) ...[
                  const SizedBox(height: 8),
                  Text(warning, style: Theme.of(context).textTheme.bodySmall),
                ],
                if (_candidates.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Предпросмотр · ${_candidates.length}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      SizedBox(
                        width: 280,
                        child: DropdownButtonFormField<String>(
                          key: const Key('bank-screenshot-batch-account'),
                          initialValue: _batchAccountId,
                          decoration: const InputDecoration(
                            labelText: 'Счёт для пакета',
                          ),
                          items: [
                            for (final account in _accounts)
                              DropdownMenuItem(
                                value: account.id,
                                child: Text(account.title),
                              ),
                          ],
                          onChanged: _setBatchAccount,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (var index = 0; index < _candidates.length; index++)
                    Card(
                      child: CheckboxListTile(
                        key: Key('bank-screenshot-candidate-$index'),
                        value: _candidates[index].selected,
                        onChanged: (selected) => setState(() {
                          final updated = _candidates.toList();
                          updated[index] = updated[index].copyWith(
                            selected: selected ?? false,
                          );
                          _candidates = updated;
                        }),
                        secondary: IconButton(
                          tooltip: 'Изменить',
                          onPressed: () => _edit(index),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(_candidates[index].merchant)),
                            Text(_moneyLabel(_candidates[index])),
                          ],
                        ),
                        subtitle: Text(
                          '${_kindLabel(_candidates[index].kind)} · '
                          '${_dateLabel(_candidates[index].date)} · '
                          '${_candidates[index].categoryId} · '
                          '${(_candidates[index].confidence * 100).round()}%'
                          '${_candidates[index].possibleDuplicateReason == null ? '' : '\n${_candidates[index].possibleDuplicateReason}'}',
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const Key('save-bank-screenshots'),
                      onPressed: _saving || selectedCount == 0 ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text('Импортировать ($selectedCount)'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CandidateEditor extends StatefulWidget {
  const _CandidateEditor({
    required this.candidate,
    required this.accounts,
    required this.categories,
  });
  final BankScreenshotCandidate candidate;
  final List<QestoAccount> accounts;
  final List<BudgetCategory> categories;

  @override
  State<_CandidateEditor> createState() => _CandidateEditorState();
}

class _CandidateEditorState extends State<_CandidateEditor> {
  late final TextEditingController _merchant;
  late final TextEditingController _amount;
  late var _kind = widget.candidate.kind;
  late var _date = widget.candidate.date;
  late var _accountId = widget.candidate.accountId;
  late var _categoryId = widget.candidate.categoryId;

  @override
  void initState() {
    super.initState();
    _merchant = TextEditingController(text: widget.candidate.merchant);
    _amount = TextEditingController(
      text: (widget.candidate.amountMinor / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _merchant.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Проверить операцию'),
    content: SizedBox(
      width: 470,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _merchant,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Сумма'),
            ),
            DropdownButtonFormField<BankScreenshotTransactionKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Тип'),
              items: [
                for (final kind in BankScreenshotTransactionKind.values)
                  DropdownMenuItem(value: kind, child: Text(_kindLabel(kind))),
              ],
              onChanged: (value) => setState(() => _kind = value ?? _kind),
            ),
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: const InputDecoration(labelText: 'Счёт'),
              items: [
                for (final account in widget.accounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(account.title),
                  ),
              ],
              onChanged: (value) => setState(() => _accountId = value),
            ),
            DropdownButtonFormField<String>(
              initialValue:
                  widget.categories.any((item) => item.id == _categoryId)
                  ? _categoryId
                  : null,
              decoration: const InputDecoration(labelText: 'Категория'),
              items: [
                for (final category in widget.categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _categoryId = value ?? _categoryId),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Дата'),
              subtitle: Text(_dateLabel(_date)),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: () async {
                final selected = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  initialDate: _date,
                );
                if (selected != null) setState(() => _date = selected);
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () {
          final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
          if (amount == null || amount <= 0 || _merchant.text.trim().isEmpty) {
            return;
          }
          Navigator.pop(
            context,
            widget.candidate.copyWith(
              merchant: _merchant.text.trim(),
              amountMinor: (amount * 100).round(),
              kind: _kind,
              date: _date,
              accountId: _accountId,
              categoryId: _categoryId,
              confidence: 1,
            ),
          );
        },
        child: const Text('Готово'),
      ),
    ],
  );
}

String _kindLabel(BankScreenshotTransactionKind kind) => switch (kind) {
  BankScreenshotTransactionKind.expense => 'Расход',
  BankScreenshotTransactionKind.income => 'Доход',
  BankScreenshotTransactionKind.transfer => 'Перевод',
  BankScreenshotTransactionKind.refund => 'Возврат',
};

String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.'
    '${date.month.toString().padLeft(2, '0')}.${date.year}';

String _moneyLabel(BankScreenshotCandidate candidate) {
  final sign =
      candidate.kind == BankScreenshotTransactionKind.income ||
          candidate.kind == BankScreenshotTransactionKind.refund
      ? '+'
      : '−';
  return '$sign${(candidate.amountMinor / 100).toStringAsFixed(2)} ₽';
}
