import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../core/widgets/nested_screen_header.dart';
import '../../core/widgets/qesto_card.dart';
import '../../core/widgets/qesto_elements.dart';
import '../../data/models/qesto_models.dart';
import 'add_expense_screen.dart';
import 'state/budget_controller.dart';

class TransactionDetailsScreen extends StatefulWidget {
  const TransactionDetailsScreen({
    required this.controller,
    required this.period,
    required this.transactionId,
    super.key,
  });

  final BudgetController controller;
  final BudgetPeriod period;
  final String transactionId;

  @override
  State<TransactionDetailsScreen> createState() =>
      _TransactionDetailsScreenState();
}

class _TransactionDetailsScreenState extends State<TransactionDetailsScreen> {
  BudgetTransaction? get _transaction => widget.controller.transactions
      .where((transaction) => transaction.id == widget.transactionId)
      .firstOrNull;

  Future<void> _edit(BudgetTransaction transaction) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddExpenseScreen(
          controller: widget.controller,
          period: widget.period,
          initialTransaction: transaction,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _delete(BudgetTransaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить операцию?'),
        content: const Text('Все суммы и графики будут пересчитаны.'),
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
      widget.controller.deleteTransaction(transaction.id);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final transaction = _transaction;
    if (transaction == null) {
      return Scaffold(
        appBar: NestedScreenHeader(
          title: Text(
            'Операция',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        body: const Center(child: Text('Операция была удалена')),
      );
    }
    final category = transaction.categoryId == null
        ? null
        : widget.controller.categoryById(transaction.categoryId!);
    final account = widget.controller.accountById(transaction.accountId);
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text('Операция', style: Theme.of(context).textTheme.titleLarge),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
        children: [
          QestoCard(
            child: Column(
              children: [
                Text(
                  transaction.type == TransactionType.refund
                      ? 'Возврат'
                      : 'Расход',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: QestoColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 8),
                AmountText(
                  formatMoney(transaction.amount, transaction.currency),
                  color: transaction.type == TransactionType.refund
                      ? QestoColors.green
                      : QestoColors.text,
                ),
                const SizedBox(height: 22),
                _DetailRow(
                  label: 'Дата',
                  value: formatDate(transaction.date, includeYear: true),
                ),
                _DetailRow(
                  label: 'Категория',
                  value: category?.name ?? 'Без категории',
                ),
                _DetailRow(
                  label: 'Подкатегория',
                  value: transaction.subcategoryId ?? 'Не указана',
                ),
                _DetailRow(
                  label: 'Продавец',
                  value:
                      transaction.merchant ?? transaction.title ?? 'Не указан',
                ),
                _DetailRow(label: 'Счёт', value: account.title),
                _DetailRow(
                  label: 'Комментарий',
                  value: transaction.comment?.isNotEmpty == true
                      ? transaction.comment!
                      : 'Нет комментария',
                ),
              ],
            ),
          ),
          if (transaction.receipt != null) ...[
            const SizedBox(height: 16),
            _ReceiptDetailsCard(receipt: transaction.receipt!),
          ],
          const SizedBox(height: 16),
          QestoButton(
            label: 'Редактировать',
            icon: Icons.edit_rounded,
            onPressed: () => _edit(transaction),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _delete(transaction),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Удалить операцию'),
            style: OutlinedButton.styleFrom(
              foregroundColor: QestoColors.danger,
              minimumSize: const Size.fromHeight(54),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptDetailsCard extends StatelessWidget {
  const _ReceiptDetailsCard({required this.receipt});

  final TransactionReceiptDetails receipt;

  @override
  Widget build(BuildContext context) {
    return QestoCard(
      key: const Key('receipt-items-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Состав чека', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          if (receipt.merchant?.isNotEmpty == true)
            _DetailRow(label: 'Магазин', value: receipt.merchant!),
          if (receipt.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Товары не распознаны',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: QestoColors.secondaryText,
                ),
              ),
            )
          else
            for (final item in receipt.items) _ReceiptItemRow(item: item),
          const Divider(height: 22),
          _DetailRow(
            label: 'Итого по чеку',
            value: '${_formatMinorMoney(receipt.totalMinor)} ₽',
          ),
          Text(
            'ФН ${receipt.fiscalDriveNumber} · '
            'ФД ${receipt.fiscalDocumentNumber}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ReceiptItemRow extends StatelessWidget {
  const _ReceiptItemRow({required this.item});

  final TransactionReceiptItem item;

  @override
  Widget build(BuildContext context) {
    final quantity = item.quantity == 1
        ? null
        : '${_formatQuantity(item.quantity)} шт.';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name),
                if (quantity != null)
                  Text(quantity, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_formatMinorMoney(item.totalMinor)} ₽',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMinorMoney(int amountMinor) {
  final whole = amountMinor.abs() ~/ 100;
  final fraction = amountMinor.abs() % 100;
  final formattedWhole = formatMoney(whole, 'RUB').replaceFirst(' ₽', '');
  return fraction == 0
      ? formattedWhole
      : '$formattedWhole,${fraction.toString().padLeft(2, '0')}';
}

String _formatQuantity(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
