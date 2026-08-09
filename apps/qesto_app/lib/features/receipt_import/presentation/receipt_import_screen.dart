import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/formatters/qesto_formatters.dart';
import '../../../core/theme/qesto_theme.dart';
import '../../../core/widgets/nested_screen_header.dart';
import '../../../core/widgets/qesto_card.dart';
import '../../../data/models/qesto_models.dart';
import '../../budget/category_picker.dart';
import '../../budget/state/budget_controller.dart';
import '../data/receipt_scanner_service.dart';
import '../domain/receipt_models.dart';
import '../services/receipt_qr_parser.dart';
import '../services/receipt_transaction_matcher.dart';

class ReceiptImportScreen extends StatefulWidget {
  const ReceiptImportScreen({
    required this.controller,
    this.scanner = const ReceiptScannerService(),
    this.parser = const ReceiptQrParser(),
    this.matcher = const ReceiptTransactionMatcher(),
    super.key,
  });

  final BudgetController controller;
  final ReceiptScannerService scanner;
  final ReceiptQrParser parser;
  final ReceiptTransactionMatcher matcher;

  @override
  State<ReceiptImportScreen> createState() => _ReceiptImportScreenState();
}

class _ReceiptImportScreenState extends State<ReceiptImportScreen> {
  final _merchantController = TextEditingController();
  var _loading = false;
  var _createNew = true;
  String? _error;
  String? _selectedTransactionId;
  BudgetCategory? _selectedCategory;
  ParsedFiscalReceipt? _receipt;
  List<BudgetTransaction> _matches = const [];

  @override
  void dispose() {
    _merchantController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_loading) return;
    if (!widget.scanner.isSupported) {
      _showError(
        'Сканирование QR-кода чека доступно только в Android-приложении',
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rawValue = await widget.scanner.scanQr();
      if (rawValue == null || !mounted) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final receipt = widget.parser.parse(rawValue);
      if (widget.matcher.isImported(
        transactions: widget.controller.transactions,
        receipt: receipt,
      )) {
        throw const FormatException('Этот чек уже добавлен в Qesto');
      }
      final matches = widget.matcher.findMatches(
        transactions: widget.controller.transactions,
        receipt: receipt,
      );
      final category = widget.controller.categories.firstWhere(
        (item) => item.id == 'groceries',
        orElse: () => widget.controller.categories.last,
      );
      _merchantController.clear();
      setState(() {
        _loading = false;
        _receipt = receipt;
        _matches = matches;
        _selectedTransactionId = matches.firstOrNull?.id;
        _createNew = matches.isEmpty;
        _selectedCategory = category;
      });
    } on PlatformException catch (error) {
      _showError(error.message ?? 'Не удалось открыть сканер QR-кода');
    } on FormatException catch (error) {
      _showError(error.message);
    } on UnsupportedError catch (error) {
      _showError(error.message?.toString() ?? 'Сканирование не поддерживается');
    } on Object {
      _showError('Не удалось обработать QR-код чека');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  Future<void> _pickCategory() async {
    final category = await showBudgetCategoryPicker(
      context: context,
      categories: widget.controller.categories,
      recentCategoryIds: widget.controller.transactions.reversed
          .map((item) => item.categoryId)
          .whereType<String>()
          .toSet()
          .toList(),
    );
    if (category != null && mounted) {
      setState(() => _selectedCategory = category);
    }
  }

  void _saveReceipt() {
    final receipt = _receipt;
    if (receipt == null) return;
    if (widget.matcher.isImported(
      transactions: widget.controller.transactions,
      receipt: receipt,
    )) {
      _showError('Этот чек уже добавлен в Qesto');
      return;
    }

    if (!_createNew && _selectedTransactionId != null) {
      final transaction = widget.controller.transactions.firstWhere(
        (item) => item.id == _selectedTransactionId,
      );
      final comment = [
        transaction.comment,
        _receiptComment(receipt),
      ].whereType<String>().where((item) => item.trim().isNotEmpty).join('\n');
      widget.controller.updateTransaction(
        transaction.copyWith(
          comment: comment,
          tags: {
            ...transaction.tags,
            'receipt-import',
            receipt.transactionTag,
          }.toList(),
        ),
      );
      Navigator.of(context).pop('Чек привязан к существующей операции');
      return;
    }

    final category = _selectedCategory;
    if (category == null) {
      _showError('Выберите категорию операции');
      return;
    }
    final period = widget.controller.periodForOrCreate(receipt.purchasedAt);
    final account = widget.controller.accounts.firstWhere(
      (item) => item.type != AccountType.liability,
      orElse: () => widget.controller.accounts.first,
    );
    final merchant = _merchantController.text.trim();
    final title = merchant.isEmpty ? 'Кассовый чек' : merchant;
    widget.controller.addImportedTransactions([
      BudgetTransaction(
        id: receipt.transactionId,
        userId: period.userId,
        accountId: account.id,
        date: receipt.purchasedAt,
        amount: receipt.roundedRubles,
        currency: period.currency,
        type: receipt.kind == FiscalReceiptKind.refund
            ? TransactionType.refund
            : TransactionType.expense,
        categoryId: category.id,
        merchant: title,
        title: title,
        description: 'Импортировано по QR-коду кассового чека',
        comment: _receiptComment(receipt),
        normalizedMerchant: _normalizeMerchant(title),
        tags: ['receipt-import', receipt.transactionTag],
      ),
    ]);
    Navigator.of(context).pop(
      receipt.kind == FiscalReceiptKind.refund
          ? 'Возврат из чека добавлен'
          : 'Расход из чека добавлен',
    );
  }

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text(
          'Добавить чек',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: SafeArea(
        top: false,
        child: receipt == null
            ? _buildScannerState(context)
            : _buildReceipt(context, receipt),
      ),
      bottomNavigationBar: receipt == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                child: FilledButton.icon(
                  key: const Key('save-receipt'),
                  onPressed: _saveReceipt,
                  icon: Icon(
                    _createNew ? Icons.add_circle_rounded : Icons.link_rounded,
                  ),
                  label: Text(
                    _createNew ? 'Добавить операцию' : 'Привязать чек',
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildScannerState(BuildContext context) {
    final supported = widget.scanner.isSupported;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
      children: [
        QestoCard(
          child: Column(
            children: [
              const Icon(
                Icons.qr_code_scanner_rounded,
                size: 58,
                color: QestoColors.primary,
              ),
              const SizedBox(height: 14),
              Text(
                'QR-код кассового чека',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                supported
                    ? 'Наведите системный сканер Android на QR-код внизу '
                          'чека. Изображение обрабатывается на устройстве.'
                    : 'Системный сканер чеков доступен только в '
                          'Android-приложении Qesto.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: QestoColors.orange),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const Key('scan-receipt-qr'),
                onPressed: supported && !_loading ? _scan : null,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(_loading ? 'Открываем сканер…' : 'Сканировать QR'),
              ),
              if (_loading) ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReceipt(BuildContext context, ParsedFiscalReceipt receipt) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
      children: [
        QestoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                receipt.kind == FiscalReceiptKind.refund
                    ? 'Чек возврата'
                    : 'Кассовый чек',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${formatDate(receipt.purchasedAt, includeYear: true)} · '
                '${_twoDigits(receipt.purchasedAt.hour)}:'
                '${_twoDigits(receipt.purchasedAt.minute)}',
              ),
              const SizedBox(height: 4),
              Text(
                '${_formatMinorMoney(receipt.amountMinor)} ₽',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'ФН ${receipt.fiscalDriveNumber} · '
                'ФД ${receipt.fiscalDocumentNumber}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (receipt.hasKopecks) ...[
                const SizedBox(height: 8),
                Text(
                  'В бюджете сумма будет округлена до ближайшего рубля. '
                  'Точная сумма сохранится в комментарии.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: QestoColors.orange),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_matches.isNotEmpty) ...[
          Text(
            'Похожая банковская операция',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Привяжите чек, чтобы расход не учитывался дважды.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          for (final transaction in _matches)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _ReceiptChoice(
                selected:
                    !_createNew && _selectedTransactionId == transaction.id,
                title: transaction.merchant ?? transaction.title ?? 'Операция',
                subtitle:
                    '${formatDate(transaction.date, includeYear: true)} · '
                    '${formatMoney(transaction.amount, transaction.currency)}',
                onTap: () => setState(() {
                  _createNew = false;
                  _selectedTransactionId = transaction.id;
                }),
              ),
            ),
          _ReceiptChoice(
            selected: _createNew,
            title: 'Создать отдельную операцию',
            subtitle: 'Используйте, если покупки ещё нет в бюджете',
            onTap: () => setState(() {
              _createNew = true;
              _selectedTransactionId = null;
            }),
          ),
          const SizedBox(height: 16),
        ],
        if (_createNew) _buildNewTransactionFields(context),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _loading ? null : _scan,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Сканировать другой чек'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: QestoColors.orange),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildNewTransactionFields(BuildContext context) {
    final category = _selectedCategory;
    final account = widget.controller.accounts.firstWhere(
      (item) => item.type != AccountType.liability,
      orElse: () => widget.controller.accounts.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Новая операция', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        TextField(
          key: const Key('receipt-merchant-field'),
          controller: _merchantController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Магазин или продавец',
            hintText: 'Можно оставить пустым',
            prefixIcon: Icon(Icons.storefront_rounded),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        QestoCard(
          onTap: _pickCategory,
          child: Row(
            children: [
              const Icon(Icons.category_rounded, color: QestoColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Категория',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      category?.name ?? 'Выберите категорию',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Счёт: ${account.title}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ReceiptChoice extends StatelessWidget {
  const _ReceiptChoice({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return QestoCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: selected ? QestoColors.primary : QestoColors.secondaryText,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _receiptComment(ParsedFiscalReceipt receipt) =>
    'Кассовый чек · ФН ${receipt.fiscalDriveNumber} · '
    'ФД ${receipt.fiscalDocumentNumber} · ФП ${receipt.fiscalSign}\n'
    'Точная сумма ${_formatMinorMoney(receipt.amountMinor)} ₽';

String _formatMinorMoney(int amountMinor) {
  final whole = amountMinor.abs() ~/ 100;
  final fraction = amountMinor.abs() % 100;
  final formattedWhole = formatMoney(whole, 'RUB').replaceFirst(' ₽', '');
  return fraction == 0
      ? formattedWhole
      : '$formattedWhole,${fraction.toString().padLeft(2, '0')}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _normalizeMerchant(String value) => value
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
    .trim();
