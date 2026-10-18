import 'package:flutter/material.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../synoball/core/models.dart';

/// A presentation of existing pending candidates, not an intake pipeline.
class MobilePendingReviewBanner extends StatelessWidget {
  const MobilePendingReviewBanner({
    required this.controller,
    required this.onOpenTransaction,
    super.key,
  });
  final BudgetController controller;
  final ValueChanged<String> onOpenTransaction;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      key: const Key('mobile-pending-review-banner'),
      leading: const Icon(Icons.inbox_outlined),
      title: Text(
        'Ожидают подтверждения: ${controller.pendingCandidates.length}',
      ),
      subtitle: const Text('Просмотреть исходные данные'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/sources/pending-review'),
          builder: (_) => MobilePendingReviewPage(
            controller: controller,
            onOpenTransaction: onOpenTransaction,
          ),
        ),
      ),
    ),
  );
}

class MobilePendingReviewPage extends StatefulWidget {
  const MobilePendingReviewPage({
    required this.controller,
    required this.onOpenTransaction,
    super.key,
  });
  final BudgetController controller;
  final ValueChanged<String> onOpenTransaction;
  @override
  State<MobilePendingReviewPage> createState() =>
      _MobilePendingReviewPageState();
}

class _MobilePendingReviewPageState extends State<MobilePendingReviewPage> {
  bool _busy = false;
  String? _error;
  String? _retryId;
  Future<void> _confirm(String id) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _retryId = id;
    });
    try {
      final canonicalId = await widget.controller.confirmVoiceCandidate(id);
      if (mounted) {
        _retryId = null;
        widget.onOpenTransaction(canonicalId);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Не удалось сохранить подтверждение. Повторите попытку.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Входящие: проверка')),
    body: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final rows = c.pendingCandidates;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(_error!),
              TextButton(
                onPressed: _busy || _retryId == null
                    ? null
                    : () => _confirm(_retryId!),
                child: const Text('Повторить'),
              ),
            ],
            if (rows.isEmpty) const Text('Неподтверждённых записей нет'),
            for (final row in rows)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.merchantGuess ?? 'Операция',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${formatMinorMoney(row.amount.minorUnits, row.amount.currency)} · ${_direction(row)}',
                      ),
                      Text(formatDate(row.occurredAt, includeYear: true)),
                      Text(
                        'Источник: ${_source(c, row)?.name ?? 'не определён'}',
                      ),
                      Text(
                        'Счёт: ${c.accounts.where((a) => a.id == row.accountId).firstOrNull?.title ?? 'не определён'}',
                      ),
                      Text(
                        'Категория: ${c.categories.where((a) => a.id == (row.userCategoryOverride ?? row.categoryGuess)).firstOrNull?.name ?? 'не определена'}',
                      ),
                      ExpansionTile(
                        title: const Text('Исходные данные'),
                        children: [SelectableText(row.rawDescription)],
                      ),
                      if (_source(c, row) == SynoballSourceType.manualVoice)
                        FilledButton(
                          onPressed: _busy ? null : () => _confirm(row.id),
                          child: const Text('Подтвердить операцию'),
                        )
                      else
                        const Text(
                          'Эту запись нужно исправить и подтвердить в экране её источника: «Ещё → Источники» или соответствующий импорт. Автоматического подтверждения здесь нет.',
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
  SynoballSourceType? _source(BudgetController c, TransactionCandidate row) => c
      .synoballState
      .ingestionRecords
      .where((r) => r.id == row.ingestionRecordId)
      .firstOrNull
      ?.sourceType;
  String _direction(TransactionCandidate row) {
    if (row.tags.contains('legacy-type-refund')) return 'Возврат';
    if (row.tags.contains('legacy-type-transfer')) return 'Перевод';
    return switch (row.direction) {
      FinancialDirection.inflow => 'Доход',
      FinancialDirection.outflow => 'Расход',
      FinancialDirection.neutral => 'Нейтральная операция',
    };
  }
}
