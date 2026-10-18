import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/budget/transaction_editor_screen.dart';
import '../../features/classification/classification_actions.dart';
import '../../features/trash/transaction_trash_screen.dart';

class MobileTransactionDetail extends StatefulWidget {
  const MobileTransactionDetail({
    required this.controller,
    required this.transactionId,
    super.key,
  });
  final BudgetController controller;
  final String transactionId;
  @override
  State<MobileTransactionDetail> createState() =>
      _MobileTransactionDetailState();
}

class _MobileTransactionDetailState extends State<MobileTransactionDetail> {
  bool _deleting = false;
  String? _error;
  Future<void> _delete() async {
    if (_deleting) return;
    final yes = await confirmClassification(
      context,
      'Переместить операцию в корзину?',
      'Она исчезнет из аналитики. Восстановить можно в корзине.',
      action: 'В корзину',
    );
    if (!yes || !mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.controller.deleteTransaction(widget.transactionId);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _deleting = false;
          _error = 'Не удалось сохранить удаление. Повторите попытку.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final t = c.transactions
          .where((t) => t.id == widget.transactionId)
          .firstOrNull;
      return Scaffold(
        key: const Key('mobile-transaction-detail'),
        appBar: AppBar(title: const Text('Операция')),
        body: t == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Операция недоступна или в корзине'),
                    if (_error != null) ...[
                      Text(_error!),
                      TextButton(
                        onPressed: _deleting ? null : _delete,
                        child: const Text('Повторить сохранение удаления'),
                      ),
                    ],
                    TextButton(
                      onPressed: () => openTransactionTrash(context, c),
                      child: const Text('Открыть корзину'),
                    ),
                  ],
                ),
              )
            : _body(context, t),
        bottomNavigationBar: t == null
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    key: const Key('mobile-transaction-edit'),
                    onPressed: _deleting
                        ? null
                        : () => Navigator.of(context).push<BudgetTransaction>(
                            MaterialPageRoute<BudgetTransaction>(
                              settings: RouteSettings(
                                name: '/transaction/${t.id}/edit',
                              ),
                              builder: (_) => TransactionEditorScreen(
                                controller: c,
                                initialTransaction: t,
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Редактировать'),
                  ),
                ),
              ),
      );
    },
  );

  Widget _body(BuildContext context, BudgetTransaction t) {
    final c = widget.controller;
    final canonical = c.synoballState.transactions
        .where((item) => item.id == t.id)
        .firstOrNull;
    final evidence = c.synoballState.evidence.where(
      (e) => e.transactionId == t.id,
    );
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            transactionTypeLabel(t),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            formatMinorMoney(t.amountMinor, t.currency),
            key: const Key('mobile-transaction-amount'),
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color:
                  t.type == TransactionType.income ||
                      t.type == TransactionType.refund
                  ? context.qestoColors.positive
                  : context.qestoColors.text,
            ),
          ),
          const SizedBox(height: 16),
          _row(
            'Дата и время',
            '${formatDate(t.date, includeYear: true)} · ${t.date.hour.toString().padLeft(2, '0')}:${t.date.minute.toString().padLeft(2, '0')}',
          ),
          _row(
            'Категория',
            c.categories
                    .where((item) => item.id == t.categoryId)
                    .firstOrNull
                    ?.name ??
                'Без категории',
          ),
          _row('Подкатегория', t.subcategoryId ?? 'Не указана'),
          _row('Продавец / контрагент', t.merchant ?? t.title ?? 'Не указан'),
          _row(
            'Счёт',
            c.accounts.where((a) => a.id == t.accountId).firstOrNull?.title ??
                'Не определён',
          ),
          _row(
            'Комментарий',
            t.comment?.isNotEmpty == true ? t.comment! : 'Нет комментария',
          ),
          _row(
            'Теги',
            c.tagsForTransaction(t).map((tag) => tag.name).join(', ').isEmpty
                ? 'Нет тегов'
                : c.tagsForTransaction(t).map((tag) => tag.name).join(', '),
          ),
          _row(
            'Проверка',
            t.isConfirmed ? 'Данные подтверждены' : 'Требует проверки',
          ),
          _row(
            'Категоризация',
            '${(t.classificationConfidence * 100).round()}% уверенности',
          ),
          if (t.isPotentialDuplicate)
            const Text('Возможный дубль — проверьте исходные данные'),
          if (canonical != null) _row('Статус', canonical.status.name),
          ExpansionTile(
            title: const Text('Источник и происхождение'),
            children: [
              for (final e in evidence)
                _row(
                  e.sourceType.name,
                  '${e.observedAt}\nБанковский ID: ${e.providerTransactionId ?? 'нет'}',
                ),
              if (evidence.isEmpty)
                const ListTile(title: Text('Данных происхождения нет')),
              if (t.description?.isNotEmpty == true)
                ListTile(
                  title: const Text('Исходное описание'),
                  subtitle: SelectableText(t.description!),
                ),
            ],
          ),
          if (t.receipt case final receipt?)
            ExpansionTile(
              title: const Text('Состав чека'),
              children: [
                for (final item in receipt.items)
                  ListTile(
                    title: Text(item.name),
                    subtitle: Text('Количество: ${item.quantity}'),
                    trailing: Text(
                      formatMinorMoney(item.totalMinor, t.currency),
                    ),
                  ),
                _row(
                  'Итого по чеку',
                  formatMinorMoney(receipt.totalMinor, t.currency),
                ),
              ],
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('mobile-transaction-category-scope'),
            onPressed: _deleting
                ? null
                : () => changeCategory(context, c, t.id),
            icon: const Icon(Icons.rule),
            label: const Text('Категория / правило для похожих'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('mobile-transaction-delete'),
            onPressed: _deleting ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: Text(_deleting ? 'Сохраняем…' : 'В корзину'),
          ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: context.qestoColors.danger)),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value),
      ],
    ),
  );
}
