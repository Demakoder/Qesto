import 'package:flutter/material.dart';

import '../../../../core/formatters/qesto_formatters.dart';
import '../../../../core/theme/qesto_theme.dart';
import '../../../../core/widgets/qesto_card.dart';
import '../../../../data/models/qesto_models.dart';
import '../../../budget/state/budget_controller.dart';
import '../../../budget/transaction_details_screen.dart';
import '../widgets/statistics_components.dart';

enum TransactionDrilldownSort { date, amount, merchant }

/// One live, sortable operation list shared by analytics drill-downs.
/// Callers own the financial filter; this widget never widens it on navigation.
class TransactionDrilldownList extends StatefulWidget {
  const TransactionDrilldownList({
    required this.controller,
    required this.transactions,
    required this.title,
    this.keyPrefix = 'drilldown',
    this.counterpartyName,
    this.counterpartyLabel,
    this.selectedDay,
    this.selectedCounterparty,
    this.onClearDay,
    this.onClearCounterparty,
    super.key,
  });

  final BudgetController controller;
  final List<BudgetTransaction> transactions;
  final String title;
  final String keyPrefix;
  final String Function(BudgetTransaction)? counterpartyName;
  final String? counterpartyLabel;
  final DateTime? selectedDay;
  final String? selectedCounterparty;
  final VoidCallback? onClearDay;
  final VoidCallback? onClearCounterparty;

  @override
  State<TransactionDrilldownList> createState() =>
      _TransactionDrilldownListState();
}

class _TransactionDrilldownListState extends State<TransactionDrilldownList> {
  TransactionDrilldownSort _sort = TransactionDrilldownSort.date;
  bool _descending = true;
  bool _sortTouched = false;
  int _visibleCount = 30;

  String _name(BudgetTransaction item) =>
      widget.counterpartyName?.call(item) ??
      (item.merchant?.trim().isNotEmpty == true
          ? item.merchant!.trim()
          : item.title?.trim().isNotEmpty == true
          ? item.title!.trim()
          : 'Без названия');

  List<BudgetTransaction> _sorted() {
    final rows = [...widget.transactions];
    rows.sort((left, right) {
      final order = switch (_sort) {
        TransactionDrilldownSort.date => left.date.compareTo(right.date),
        TransactionDrilldownSort.amount => left.amountMinor.compareTo(
          right.amountMinor,
        ),
        TransactionDrilldownSort.merchant => _name(
          left,
        ).toLowerCase().compareTo(_name(right).toLowerCase()),
      };
      final directed = _descending ? -order : order;
      return directed != 0 ? directed : left.id.compareTo(right.id);
    });
    return rows;
  }

  void _selectSort(TransactionDrilldownSort sort) => setState(() {
    if (_sort == sort && _sortTouched) {
      _descending = !_descending;
    } else {
      _sort = sort;
      _descending = sort != TransactionDrilldownSort.merchant;
      _sortTouched = true;
    }
    _visibleCount = 30;
  });

  Widget _sortChip(TransactionDrilldownSort sort, String label, IconData icon) {
    final active = _sort == sort;
    return FilterChip(
      key: Key('${widget.keyPrefix}-sort-${sort.name}'),
      avatar: Icon(icon, size: 17),
      label: Text(label + (active ? (_descending ? ' ↓' : ' ↑') : '')),
      selected: active,
      showCheckmark: false,
      onSelected: (_) => _selectSort(sort),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sorted();
    final visible = rows.take(_visibleCount).toList(growable: false);
    final income =
        rows.isNotEmpty &&
        rows.every((item) => item.type == TransactionType.income);
    return QestoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatisticsSectionHeader(title: '${widget.title} · ${rows.length}'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _sortChip(
                TransactionDrilldownSort.date,
                'Дата',
                Icons.calendar_today_outlined,
              ),
              _sortChip(
                TransactionDrilldownSort.amount,
                'Сумма',
                Icons.payments_outlined,
              ),
              _sortChip(
                TransactionDrilldownSort.merchant,
                widget.counterpartyLabel ?? (income ? 'Источник' : 'Продавец'),
                Icons.storefront_outlined,
              ),
            ],
          ),
          if (widget.selectedDay != null ||
              widget.selectedCounterparty != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (widget.selectedDay case final day?)
                  InputChip(
                    key: Key('${widget.keyPrefix}-day-filter'),
                    label: Text(formatDate(day, includeYear: true)),
                    onDeleted: widget.onClearDay,
                  ),
                if (widget.selectedCounterparty case final name?)
                  InputChip(
                    key: Key('${widget.keyPrefix}-merchant-filter'),
                    label: Text(name),
                    onDeleted: widget.onClearCounterparty,
                  ),
                TextButton(
                  onPressed: () {
                    widget.onClearDay?.call();
                    widget.onClearCounterparty?.call();
                  },
                  child: const Text('Сбросить фильтр'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Text('По выбранным фильтрам операций нет'),
            )
          else
            for (final item in visible) ...[
              const Divider(height: 1),
              ListTile(
                key: Key('${widget.keyPrefix}-operation-${item.id}'),
                contentPadding: EdgeInsets.zero,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TransactionDetailsScreen(
                      controller: widget.controller,
                      period: widget.controller.periods.firstWhere(
                        (period) => period.contains(item.date),
                        orElse: () => widget.controller.periods.last,
                      ),
                      transactionId: item.id,
                    ),
                  ),
                ),
                title: Text(
                  _name(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${formatDate(item.date, includeYear: true)} · '
                  '${widget.controller.categories.where((c) => c.id == item.categoryId).firstOrNull?.name ?? 'Без категории'}'
                  '${item.isConfirmed ? '' : ' · Требует проверки'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  formatMoney(
                    item.amount,
                    item.currency,
                    showSign:
                        item.type == TransactionType.income ||
                        item.type == TransactionType.refund,
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color:
                        item.type == TransactionType.income ||
                            item.type == TransactionType.refund
                        ? context.qestoColors.green
                        : context.qestoColors.text,
                  ),
                ),
              ),
            ],
          if (rows.length > visible.length)
            Align(
              alignment: Alignment.center,
              child: TextButton(
                key: Key('${widget.keyPrefix}-load-more'),
                onPressed: () => setState(() => _visibleCount += 30),
                child: Text('Показать ещё · ${rows.length - visible.length}'),
              ),
            ),
        ],
      ),
    );
  }
}
