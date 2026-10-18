import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../synoball/enrichment/category_policy.dart';
import '../classification/classification_actions.dart';
import 'state/budget_controller.dart';

/// Mobile presentation of the existing canonical update/delete/tag commands.
class MobileSelectionToolbar extends StatefulWidget {
  const MobileSelectionToolbar({
    required this.controller,
    required this.ids,
    required this.onClear,
    super.key,
  });
  final BudgetController controller;
  final Set<String> ids;
  final VoidCallback onClear;
  @override
  State<MobileSelectionToolbar> createState() => _MobileSelectionToolbarState();
}

class _MobileSelectionToolbarState extends State<MobileSelectionToolbar> {
  bool _busy = false;
  String? _error;
  Future<void> Function()? _retry;
  Future<void> _run(Future<void> Function() command) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _retry = command;
    });
    try {
      await command();
      if (mounted) {
        widget.onClear();
        _retry = null;
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Не удалось сохранить. Часть изменений могла примениться. Повторите попытку.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _category() async {
    final c = widget.controller;
    final selected = await pickCategory(context, c);
    if (selected == null || !mounted) return;
    final ids = widget.ids.toSet();
    await _run(
      () => c.updateTransactions(
        c.transactions
            .where((t) => ids.contains(t.id))
            .map((t) => t.copyWith(categoryId: selected.id)),
        explicitCategorySelection: true,
      ),
    );
  }

  Future<void> _tags() async {
    final c = widget.controller;
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Добавить тег выбранным операциям'),
        children: [
          for (final tag in c.classification.tags)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, tag.id),
              child: Text(tag.name),
            ),
          if (c.classification.tags.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Создайте тег в «Категории и правила».'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    final ids = widget.ids.toSet();
    await _run(() async {
      for (final id in ids) {
        final t = c.transactions.where((t) => t.id == id).firstOrNull;
        if (t != null) {
          await c.setTransactionTags(id, {
            ...t.tags
                .where((s) => s.startsWith(userLabelPrefix))
                .map((s) => s.substring(userLabelPrefix.length)),
            chosen,
          });
        }
      }
    });
  }

  Future<void> _delete() async {
    final ids = widget.ids.toSet();
    if (!await confirmClassification(
          context,
          'Переместить ${ids.length} операций в корзину?',
          'Они исчезнут из аналитики; восстановление доступно в корзине.',
          action: 'В корзину',
        ) ||
        !mounted) {
      return;
    }
    await _run(() async {
      for (final id in ids) {
        await widget.controller.deleteTransaction(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('mobile-selection-toolbar'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Выбрано: ${widget.ids.length}')),
              IconButton(
                tooltip: 'Снять выделение',
                onPressed: _busy ? null : widget.onClear,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : _category,
                child: const Text('Категория'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _tags,
                child: const Text('Теги'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () {
                        final ids = widget.ids.toSet();
                        _run(
                          () => widget.controller.updateTransactions(
                            widget.controller.transactions
                                .where(
                                  (t) =>
                                      ids.contains(t.id) &&
                                      !t.tags.contains('sber-status-pending') &&
                                      !t.tags.contains('status-pending'),
                                )
                                .map((t) => t.copyWith(isConfirmed: true)),
                          ),
                        );
                      },
                child: const Text('Проверено'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final rows = widget.controller.transactions.where(
                          (t) => widget.ids.contains(t.id),
                        );
                        await Clipboard.setData(
                          ClipboardData(
                            text: [
                              'Дата\tОписание\tТип\tСумма',
                              ...rows.map(
                                (t) =>
                                    '${t.date.toIso8601String()}\t${t.merchant ?? t.title ?? ''}\t${t.type.name}\t${t.amountMinor / 100} ${t.currency}',
                              ),
                            ].join('\n'),
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Выбранные операции скопированы как TSV',
                              ),
                            ),
                          );
                        }
                      },
                child: const Text('Экспорт'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _delete,
                child: const Text('В корзину'),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!),
            TextButton(
              onPressed: _busy || _retry == null ? null : () => _run(_retry!),
              child: const Text('Повторить'),
            ),
          ],
        ],
      ),
    ),
  );
}
