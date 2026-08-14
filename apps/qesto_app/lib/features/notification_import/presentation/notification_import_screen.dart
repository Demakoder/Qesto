import 'package:flutter/material.dart';

import '../../../core/formatters/qesto_formatters.dart';
import '../../../core/theme/qesto_theme.dart';
import '../../../core/widgets/nested_screen_header.dart';
import '../../../core/widgets/qesto_card.dart';
import '../../../data/models/qesto_models.dart';
import '../../budget/add_expense_screen.dart';
import '../../budget/state/budget_controller.dart';
import '../data/notification_capture_service.dart';
import '../domain/parsed_bank_transaction.dart';
import '../services/bank_notification_parser.dart';

class NotificationImportScreen extends StatefulWidget {
  const NotificationImportScreen({
    required this.controller,
    this.captureService = const NotificationCaptureService(),
    this.parser = const SberbankNotificationParser(),
    this.captureAvailable = true,
    this.onAllDataDeleted,
    super.key,
  });

  final BudgetController controller;
  final NotificationCaptureService captureService;
  final BankNotificationParser parser;
  final bool captureAvailable;
  final Future<void> Function()? onAllDataDeleted;

  @override
  State<NotificationImportScreen> createState() =>
      _NotificationImportScreenState();
}

class _NotificationImportScreenState extends State<NotificationImportScreen> {
  var _loading = true;
  String? _error;
  List<CapturedNotification> _notifications = const [];
  var _deletingAllData = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.captureAvailable) {
      if (!mounted) return;
      setState(() {
        _notifications = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    try {
      final notifications = await widget.captureService.readNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _loading = false;
        _error = null;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось прочитать уведомления';
      });
    }
  }

  Future<void> _deleteAllData() async {
    if (_deletingAllData) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить все данные Qesto?'),
        content: const Text(
          'Будут безвозвратно удалены операции, счета, бюджеты, накопления, '
          'планы и история действий. Само приложение останется установленным.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton.icon(
            key: const Key('confirm-delete-all-data'),
            style: FilledButton.styleFrom(backgroundColor: QestoColors.orange),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Удалить всё'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingAllData = true);
    try {
      await widget.controller.clearAllFinancialData();
      if (widget.captureAvailable) {
        try {
          await widget.captureService.clearNotifications();
        } on Object {
          // Financial data deletion must not depend on Android inbox access.
        }
      }
      await widget.onAllDataDeleted?.call();
      if (!mounted) return;
      setState(() {
        _notifications = const [];
        _deletingAllData = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Все данные Qesto удалены')));
    } on Object {
      if (!mounted) return;
      setState(() => _deletingAllData = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить все данные')),
      );
    }
  }

  BudgetPeriod? _periodFor(DateTime date) {
    for (final period in widget.controller.periods) {
      if (period.contains(date)) return period;
    }
    return null;
  }

  QestoAccount get _defaultAccount {
    return widget.controller.accounts.firstWhere(
      (account) => account.type != AccountType.liability,
      orElse: () => widget.controller.accounts.first,
    );
  }

  String _categoryName(String categoryId) {
    return widget.controller.categories
        .firstWhere(
          (category) => category.id == categoryId,
          orElse: () => widget.controller.categories.last,
        )
        .name;
  }

  Future<bool> _removeNotification(String notificationKey) async {
    try {
      await widget.captureService.removeNotification(notificationKey);
      if (!mounted) return false;
      setState(() {
        _notifications = _notifications
            .where((item) => item.notificationKey != notificationKey)
            .toList();
      });
      return true;
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось обработать уведомление')),
        );
      }
      return false;
    }
  }

  Future<void> _discard(CapturedNotification notification) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Пропустить уведомление?'),
        content: const Text('Оно будет удалено из списка найденных операций.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Пропустить'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _removeNotification(notification.notificationKey);
    }
  }

  Future<void> _add(
    CapturedNotification notification,
    ParsedBankTransaction transaction,
  ) async {
    final period = _periodFor(transaction.date);
    if (period == null) return;

    await widget.controller.addAndroidNotificationExpense(
      period: period,
      amountMinor: transaction.amountMinor,
      date: transaction.date,
      categoryId: transaction.categoryId,
      accountId: _defaultAccount.id,
      title: transaction.merchant,
      notificationKey: notification.notificationKey,
      packageName: notification.packageName,
      rawNotification: '${notification.title}\n${notification.text}',
      subcategoryId: transaction.subcategoryId,
      confidence: transaction.confidence,
    );
    final removed = await _removeNotification(notification.notificationKey);
    if (removed && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Расход добавлен в бюджет')));
    }
  }

  Future<void> _edit(
    CapturedNotification notification,
    ParsedBankTransaction transaction,
  ) async {
    final period = _periodFor(transaction.date);
    if (period == null || !transaction.hasWholeCurrencyAmount) return;

    final draft = BudgetTransaction(
      id: 'import-draft-${notification.notificationKey.hashCode}',
      userId: period.userId,
      accountId: _defaultAccount.id,
      date: transaction.date,
      amount: transaction.wholeCurrencyAmount,
      currency: transaction.currency,
      type: TransactionType.expense,
      categoryId: transaction.categoryId,
      subcategoryId: transaction.subcategoryId,
      merchant: transaction.merchant,
      title: transaction.merchant,
      normalizedMerchant: transaction.merchant.toLowerCase(),
      isConfirmed: false,
      classificationConfidence: transaction.confidence,
    );
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => AddExpenseScreen(
          controller: widget.controller,
          period: period,
          initialTransaction: draft,
          addInitialAsNew: true,
        ),
      ),
    );
    if (saved == true) {
      await _removeNotification(notification.notificationKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text(
          'Найденные операции',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        actions: [
          IconButton(
            key: const Key('delete-all-data'),
            tooltip: 'Удалить все данные Qesto',
            onPressed: _deletingAllData ? null : _deleteAllData,
            icon: _deletingAllData
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(
                    Icons.delete_sweep_outlined,
                    color: QestoColors.orange,
                  ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: switch ((_loading, _error, _notifications.isEmpty)) {
          (true, _, _) => const Center(child: CircularProgressIndicator()),
          (false, final error?, _) => _MessageState(
            icon: Icons.error_outline_rounded,
            message: error,
            actionLabel: 'Повторить',
            onAction: _load,
          ),
          (false, null, true) => _MessageState(
            icon: Icons.notifications_none_rounded,
            message: widget.captureAvailable
                ? 'Новых операций нет'
                : 'Банковские уведомления доступны на Android. Здесь можно удалить все локальные данные Qesto.',
          ),
          _ => RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              itemCount: _notifications.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final notification = _notifications[index];
                final transaction = widget.parser.parse(notification);
                if (transaction == null) {
                  return _UnsupportedNotificationCard(
                    notification: notification,
                    onDiscard: () => _discard(notification),
                  );
                }
                return _ParsedTransactionCard(
                  transaction: transaction,
                  categoryName: _categoryName(transaction.categoryId),
                  hasPeriod: _periodFor(transaction.date) != null,
                  onDiscard: () => _discard(notification),
                  onEdit: () => _edit(notification, transaction),
                  onAdd: () => _add(notification, transaction),
                );
              },
            ),
          ),
        },
      ),
    );
  }
}

class _ParsedTransactionCard extends StatelessWidget {
  const _ParsedTransactionCard({
    required this.transaction,
    required this.categoryName,
    required this.hasPeriod,
    required this.onDiscard,
    required this.onEdit,
    required this.onAdd,
  });

  final ParsedBankTransaction transaction;
  final String categoryName;
  final bool hasPeriod;
  final VoidCallback onDiscard;
  final VoidCallback onEdit;
  final VoidCallback onAdd;

  bool get _canAdd => hasPeriod && transaction.hasWholeCurrencyAmount;

  @override
  Widget build(BuildContext context) {
    final time =
        '${transaction.date.hour.toString().padLeft(2, '0')}:'
        '${transaction.date.minute.toString().padLeft(2, '0')}';

    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: QestoColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.restaurant_rounded,
                  color: QestoColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.merchant,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_formatMinorMoney(transaction.amountMinor, transaction.currency)} · $categoryName',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      '${formatDate(transaction.date)} · $time',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!_canAdd) ...[
            const SizedBox(height: 10),
            Text(
              hasPeriod
                  ? 'Суммы с копейками пока нельзя добавить в текущую модель бюджета'
                  : 'Для даты операции не найден бюджетный период',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: QestoColors.orange),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(onPressed: onDiscard, child: const Text('Пропустить')),
              OutlinedButton(
                onPressed: _canAdd ? onEdit : null,
                child: const Text('Изменить'),
              ),
              FilledButton.icon(
                onPressed: _canAdd ? onAdd : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Добавить'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnsupportedNotificationCard extends StatelessWidget {
  const _UnsupportedNotificationCard({
    required this.notification,
    required this.onDiscard,
  });

  final CapturedNotification notification;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notification.title.isEmpty
                ? 'Неизвестное уведомление'
                : notification.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Формат пока не поддерживается',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onDiscard, child: const Text('Пропустить')),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: QestoColors.secondaryText),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatMinorMoney(int amountMinor, String currency) {
  final whole = amountMinor ~/ 100;
  final fraction = amountMinor.remainder(100).abs();
  final formatted = formatMoney(whole, currency);
  if (fraction == 0) return formatted;

  final symbol = currencySymbol(currency);
  return formatted.replaceFirst(
    ' $symbol',
    ',${fraction.toString().padLeft(2, '0')} $symbol',
  );
}
