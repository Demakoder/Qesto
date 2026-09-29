import 'package:flutter/material.dart';
import '../../core/formatters/qesto_formatters.dart';

import '../../synoball/core/models.dart';
import '../budget/state/budget_controller.dart';

Future<void> openTransactionTrash(
  BuildContext context,
  BudgetController controller,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => TransactionTrashScreen(controller: controller),
  ),
);

class TransactionTrashEntry extends StatelessWidget {
  const TransactionTrashEntry({required this.controller, super.key});
  final BudgetController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Card(
      child: ListTile(
        key: const Key('open-transaction-trash'),
        leading: const Icon(Icons.delete_outline_rounded),
        title: const Text('Корзина'),
        subtitle: Text(
          'Удалённых операций: ${controller.trashedTransactions.length} · восстановление',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => openTransactionTrash(context, controller),
      ),
    ),
  );
}

class TransactionTrashScreen extends StatefulWidget {
  const TransactionTrashScreen({required this.controller, super.key});
  final BudgetController controller;

  @override
  State<TransactionTrashScreen> createState() => _TransactionTrashScreenState();
}

class _TransactionTrashScreenState extends State<TransactionTrashScreen> {
  final _search = TextEditingController();
  var _saving = false;
  String? _error;
  List<String>? _retryIds;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _restore(List<String> ids, {bool confirm = false}) async {
    if (_saving || ids.isEmpty) return;
    if (confirm) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Восстановить все операции?'),
          content: Text(
            '${ids.length} операций вернутся из корзины. Статистика будет пересчитана.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Восстановить'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final restored = await widget.controller.restoreTrashedTransactions(ids);
      _retryIds = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            restored == 0
                ? 'Изменения сохранены'
                : 'Восстановлено операций: $restored',
          ),
        ),
      );
    } on Object {
      if (mounted) {
        setState(() {
          _retryIds = ids;
          _error =
              'Не удалось сохранить восстановление. Проверьте доступ к хранилищу.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final all = widget.controller.trashedTransactions;
      final query = _search.text.trim().toLowerCase();
      final items = all
          .where(
            (item) =>
                '${item.merchantName ?? ''} ${item.rawDescription} ${item.amount.currency}'
                    .toLowerCase()
                    .contains(query),
          )
          .toList();
      return Scaffold(
        appBar: AppBar(title: const Text('Корзина')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Удалённые операции не участвуют в статистике и не возвращаются при повторном импорте. Корзина хранится без автоочистки. Восстановление возвращает исходные данные и статус операции.',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('trash-search'),
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Найти удалённую операцию',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      if (all.isNotEmpty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: const Key('restore-all-trash'),
                            onPressed: _saving
                                ? null
                                : () => _restore(
                                    all.map((item) => item.id).toList(),
                                    confirm: true,
                                  ),
                            icon: const Icon(Icons.restore_from_trash_outlined),
                            label: Text('Восстановить всё (${all.length})'),
                          ),
                        ),
                      if (_saving) const LinearProgressIndicator(),
                      if (_retryIds != null)
                        TextButton.icon(
                          key: const Key('retry-trash-save'),
                          onPressed: _saving
                              ? null
                              : () => _restore(_retryIds!),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Повторить сохранение'),
                        ),
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            all.isEmpty ? 'Корзина пуста' : 'Ничего не найдено',
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final account = widget.controller.accounts
                                .where(
                                  (account) => account.id == item.accountId,
                                )
                                .firstOrNull;
                            final money = formatMinorMoney(
                              item.amount.minorUnits.abs(),
                              item.amount.currency,
                            );
                            final sign = switch (item.direction) {
                              FinancialDirection.inflow => '+',
                              FinancialDirection.outflow => '−',
                              FinancialDirection.neutral => '',
                            };
                            return Card(
                              child: ListTile(
                                key: Key('trashed-${item.id}'),
                                title: Text(
                                  item.merchantName ??
                                      item.normalizedDescription,
                                ),
                                subtitle: Text(
                                  '$sign$money · ${formatDate(item.occurredAt, includeYear: true)}\n'
                                  '${account?.title ?? 'Исходный счёт недоступен'}\n'
                                  'В корзине с ${formatDate(item.updatedAt, includeYear: true)}',
                                ),
                                isThreeLine: true,
                                trailing: IconButton(
                                  key: Key('restore-trash-${item.id}'),
                                  tooltip: 'Восстановить',
                                  icon: const Icon(
                                    Icons.restore_from_trash_outlined,
                                  ),
                                  onPressed: _saving
                                      ? null
                                      : () => _restore([item.id]),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
