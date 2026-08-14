import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/theme/qesto_theme.dart';
import '../../data/models/qesto_models.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../synoball/core/models.dart';
import '../desktop_financial_helpers.dart';
import '../widgets/desktop_components.dart';

class DesktopTransactionsPage extends StatefulWidget {
  const DesktopTransactionsPage({
    required this.controller,
    this.requestedTransactionId,
    this.requestSerial = 0,
    super.key,
  });

  final BudgetController controller;
  final String? requestedTransactionId;
  final int requestSerial;

  @override
  State<DesktopTransactionsPage> createState() =>
      _DesktopTransactionsPageState();
}

class _DesktopTransactionsPageState extends State<DesktopTransactionsPage> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _selectedIds = <String>{};
  String? _categoryId;
  String? _accountId;
  SynoballSourceType? _source;
  bool _reviewOnly = false;
  String? _openedId;

  @override
  void initState() {
    super.initState();
    _openedId = widget.requestedTransactionId;
  }

  @override
  void didUpdateWidget(covariant DesktopTransactionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestSerial != widget.requestSerial) {
      setState(() => _openedId = widget.requestedTransactionId);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.slash): () =>
            _searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_openedId != null) setState(() => _openedId = null);
        },
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final transactions = _filteredTransactions();
            final opened = _openedId == null
                ? null
                : widget.controller.transactions
                      .cast<BudgetTransaction?>()
                      .firstWhere(
                        (item) => item?.id == _openedId,
                        orElse: () => null,
                      );
            return Padding(
              padding: const EdgeInsets.fromLTRB(26, 20, 26, 28),
              child: Column(
                children: [
                  _FilterBar(
                    controller: widget.controller,
                    searchController: _searchController,
                    searchFocus: _searchFocus,
                    categoryId: _categoryId,
                    accountId: _accountId,
                    source: _source,
                    reviewOnly: _reviewOnly,
                    onSearchChanged: (_) => setState(() {}),
                    onCategoryChanged: (value) =>
                        setState(() => _categoryId = value),
                    onAccountChanged: (value) =>
                        setState(() => _accountId = value),
                    onSourceChanged: (value) => setState(() => _source = value),
                    onReviewChanged: (value) =>
                        setState(() => _reviewOnly = value),
                    onClear: _clearFilters,
                  ),
                  if (widget.controller.pendingCandidates.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _CandidateBanner(controller: widget.controller),
                  ],
                  if (_selectedIds.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _BulkBar(
                      controller: widget.controller,
                      selectedIds: _selectedIds,
                      onClear: () => setState(_selectedIds.clear),
                      onChanged: () => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DesktopCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                _TransactionTableHeader(
                                  allSelected:
                                      transactions.isNotEmpty &&
                                      transactions.every(
                                        (item) =>
                                            _selectedIds.contains(item.id),
                                      ),
                                  onSelectAll: (selected) => setState(() {
                                    if (selected) {
                                      _selectedIds.addAll(
                                        transactions.map((item) => item.id),
                                      );
                                    } else {
                                      _selectedIds.removeAll(
                                        transactions.map((item) => item.id),
                                      );
                                    }
                                  }),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: transactions.isEmpty
                                      ? const DesktopEmptyState(
                                          title: 'Операции не найдены',
                                          message:
                                              'Измените фильтры или добавьте новый источник данных.',
                                          icon: Icons.search_off_rounded,
                                        )
                                      : ListView.separated(
                                          itemCount: transactions.length,
                                          separatorBuilder: (_, _) =>
                                              const Divider(
                                                height: 1,
                                                indent: 16,
                                                endIndent: 16,
                                              ),
                                          itemBuilder: (context, index) {
                                            final transaction =
                                                transactions[index];
                                            return _TransactionTableRow(
                                              controller: widget.controller,
                                              transaction: transaction,
                                              selected: _selectedIds.contains(
                                                transaction.id,
                                              ),
                                              opened:
                                                  opened?.id == transaction.id,
                                              onSelected: (selected) =>
                                                  setState(() {
                                                    if (selected) {
                                                      _selectedIds.add(
                                                        transaction.id,
                                                      );
                                                    } else {
                                                      _selectedIds.remove(
                                                        transaction.id,
                                                      );
                                                    }
                                                  }),
                                              onTap: () => setState(
                                                () =>
                                                    _openedId = transaction.id,
                                              ),
                                            );
                                          },
                                        ),
                                ),
                                Container(
                                  height: 42,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: QestoColors.surfaceSecondary,
                                    borderRadius: BorderRadius.vertical(
                                      bottom: Radius.circular(16),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        'Показано ${transactions.length} из ${widget.controller.transactions.length}',
                                        style: const TextStyle(
                                          color: QestoColors.secondaryText,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const Spacer(),
                                      const Text(
                                        'Строки виртуализированы',
                                        style: TextStyle(
                                          color: QestoColors.secondaryText,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (opened != null)
                          Positioned(
                            top: 0,
                            right: 0,
                            bottom: 0,
                            width: 370,
                            child: _TransactionDrawer(
                              key: ValueKey(opened.id),
                              controller: widget.controller,
                              transaction: opened,
                              onClose: () => setState(() => _openedId = null),
                              onDeleted: () => setState(() => _openedId = null),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<BudgetTransaction> _filteredTransactions() {
    final query = _searchController.text.trim().toLowerCase();
    final values = widget.controller.transactions.where((transaction) {
      if (_categoryId != null && transaction.categoryId != _categoryId) {
        return false;
      }
      if (_accountId != null && transaction.accountId != _accountId) {
        return false;
      }
      if (_reviewOnly && !desktopNeedsReview(transaction)) return false;
      if (_source != null &&
          !desktopEvidenceFor(
            widget.controller,
            transaction.id,
          ).any((item) => item.sourceType == _source)) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        desktopTransactionTitle(transaction),
        transaction.description ?? '',
        desktopCategoryName(widget.controller, transaction),
        desktopAccountName(widget.controller, transaction),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
    values.sort((a, b) => b.date.compareTo(a.date));
    return values;
  }

  void _clearFilters() => setState(() {
    _searchController.clear();
    _categoryId = null;
    _accountId = null;
    _source = null;
    _reviewOnly = false;
  });
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.controller,
    required this.searchController,
    required this.searchFocus,
    required this.categoryId,
    required this.accountId,
    required this.source,
    required this.reviewOnly,
    required this.onSearchChanged,
    required this.onCategoryChanged,
    required this.onAccountChanged,
    required this.onSourceChanged,
    required this.onReviewChanged,
    required this.onClear,
  });

  final BudgetController controller;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final String? categoryId;
  final String? accountId;
  final SynoballSourceType? source;
  final bool reviewOnly;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onAccountChanged;
  final ValueChanged<SynoballSourceType?> onSourceChanged;
  final ValueChanged<bool> onReviewChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasFilters =
        searchController.text.isNotEmpty ||
        categoryId != null ||
        accountId != null ||
        source != null ||
        reviewOnly;
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          height: 42,
          child: TextField(
            controller: searchController,
            focusNode: searchFocus,
            onChanged: onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'Поиск по операциям  /',
              prefixIcon: Icon(Icons.search_rounded, size: 19),
            ),
          ),
        ),
        _DropdownFilter<String>(
          value: categoryId,
          hint: 'Категория',
          icon: Icons.category_outlined,
          items: controller.categories
              .map(
                (item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(item.shortName ?? item.name),
                ),
              )
              .toList(),
          onChanged: onCategoryChanged,
        ),
        _DropdownFilter<String>(
          value: accountId,
          hint: 'Счёт',
          icon: Icons.account_balance_wallet_outlined,
          items: controller.accounts
              .map(
                (item) =>
                    DropdownMenuItem(value: item.id, child: Text(item.title)),
              )
              .toList(),
          onChanged: onAccountChanged,
        ),
        _DropdownFilter<SynoballSourceType>(
          value: source,
          hint: 'Источник',
          icon: Icons.hub_outlined,
          items: SynoballSourceType.values
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(desktopSourceTypeLabel(item)),
                ),
              )
              .toList(),
          onChanged: onSourceChanged,
        ),
        FilterChip(
          selected: reviewOnly,
          onSelected: onReviewChanged,
          avatar: Icon(
            reviewOnly
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 16,
          ),
          label: const Text('Требуют проверки'),
          side: const BorderSide(color: QestoColors.border),
          selectedColor: QestoColors.primarySoft,
          checkmarkColor: QestoColors.primary,
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: reviewOnly ? QestoColors.primary : QestoColors.text,
          ),
        ),
        if (hasFilters)
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Сбросить'),
          ),
      ],
    );
  }
}

class _DropdownFilter<T> extends StatelessWidget {
  const _DropdownFilter({
    required this.value,
    required this.hint,
    required this.icon,
    required this.items,
    required this.onChanged,
  });

  final T? value;
  final String hint;
  final IconData icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      constraints: const BoxConstraints(minWidth: 130, maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: QestoColors.surface,
        border: Border.all(color: QestoColors.border),
        borderRadius: BorderRadius.circular(11),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Row(
            children: [
              Icon(icon, size: 16, color: QestoColors.secondaryText),
              const SizedBox(width: 6),
              Flexible(child: Text(hint, overflow: TextOverflow.ellipsis)),
            ],
          ),
          style: const TextStyle(
            color: QestoColors.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _CandidateBanner extends StatelessWidget {
  const _CandidateBanner({required this.controller});
  final BudgetController controller;

  @override
  Widget build(BuildContext context) {
    final candidates = controller.pendingCandidates;
    return DesktopCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: const Color(0xFFFFF9EC),
      borderColor: const Color(0xFFFFE6AE),
      child: Row(
        children: [
          const Icon(
            Icons.mic_none_rounded,
            size: 19,
            color: QestoColors.warning,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${candidates.length} голосовая операция требует подтверждения',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          for (final candidate in candidates.take(2))
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: OutlinedButton.icon(
                onPressed: () => controller.confirmVoiceCandidate(candidate.id),
                icon: const Icon(Icons.check_rounded, size: 16),
                label: Text(candidate.merchantGuess ?? 'Подтвердить'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: QestoColors.text,
                  side: const BorderSide(color: Color(0xFFFFD789)),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.controller,
    required this.selectedIds,
    required this.onClear,
    required this.onChanged,
  });

  final BudgetController controller;
  final Set<String> selectedIds;
  final VoidCallback onClear;
  final VoidCallback onChanged;

  List<BudgetTransaction> get selected => controller.transactions
      .where((item) => selectedIds.contains(item.id))
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    return DesktopCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: QestoColors.primarySoft,
      borderColor: const Color(0xFFD6E4FF),
      child: Row(
        children: [
          Text(
            'Выбрано: ${selectedIds.length}',
            style: const TextStyle(
              color: QestoColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 14),
          PopupMenuButton<String>(
            tooltip: 'Изменить категорию',
            onSelected: (categoryId) async {
              await controller.updateTransactions(
                selected.map((item) => item.copyWith(categoryId: categoryId)),
              );
              onChanged();
            },
            itemBuilder: (_) => controller.categories
                .map(
                  (item) =>
                      PopupMenuItem(value: item.id, child: Text(item.name)),
                )
                .toList(),
            child: const _BulkAction(
              icon: Icons.category_outlined,
              label: 'Категория',
            ),
          ),
          const SizedBox(width: 7),
          InkWell(
            onTap: () async {
              await controller.updateTransactions(
                selected.map((item) => item.copyWith(isConfirmed: true)),
              );
              onChanged();
            },
            borderRadius: BorderRadius.circular(8),
            child: const _BulkAction(
              icon: Icons.done_all_rounded,
              label: 'Проверено',
            ),
          ),
          const SizedBox(width: 7),
          InkWell(
            onTap: () async {
              final lines = <String>['Дата\tОписание\tКатегория\tСумма'];
              for (final item in selected) {
                lines.add(
                  '${item.date.toIso8601String()}\t${desktopTransactionTitle(item)}\t${desktopCategoryName(controller, item)}\t${desktopSignedAmount(item)}',
                );
              }
              await Clipboard.setData(ClipboardData(text: lines.join('\n')));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Выбранные операции скопированы как TSV'),
                  ),
                );
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: const _BulkAction(
              icon: Icons.file_download_outlined,
              label: 'Экспорт',
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Снять выделение',
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _BulkAction extends StatelessWidget {
  const _BulkAction({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _TransactionTableHeader extends StatelessWidget {
  const _TransactionTableHeader({
    required this.allSelected,
    required this.onSelectAll,
  });
  final bool allSelected;
  final ValueChanged<bool> onSelectAll;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showAccount = constraints.maxWidth > 690;
        final showSource = constraints.maxWidth > 850;
        return SizedBox(
          height: 44,
          child: Row(
            children: [
              SizedBox(
                width: 50,
                child: Checkbox(
                  value: allSelected,
                  onChanged: (value) => onSelectAll(value ?? false),
                ),
              ),
              const SizedBox(width: 80, child: _HeaderLabel('Дата')),
              const Expanded(flex: 3, child: _HeaderLabel('Описание')),
              const Expanded(flex: 2, child: _HeaderLabel('Категория')),
              if (showAccount)
                const Expanded(flex: 2, child: _HeaderLabel('Счёт')),
              if (showSource)
                const SizedBox(width: 120, child: _HeaderLabel('Источник')),
              const SizedBox(width: 52, child: _HeaderLabel('Статус')),
              const SizedBox(
                width: 116,
                child: _HeaderLabel('Сумма', alignRight: true),
              ),
              const SizedBox(width: 12),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  const _HeaderLabel(this.label, {this.alignRight = false});
  final String label;
  final bool alignRight;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
    child: Text(
      label,
      style: const TextStyle(
        color: QestoColors.secondaryText,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.25,
      ),
    ),
  );
}

class _TransactionTableRow extends StatelessWidget {
  const _TransactionTableRow({
    required this.controller,
    required this.transaction,
    required this.selected,
    required this.opened,
    required this.onSelected,
    required this.onTap,
  });
  final BudgetController controller;
  final BudgetTransaction transaction;
  final bool selected;
  final bool opened;
  final ValueChanged<bool> onSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showAccount = constraints.maxWidth > 690;
        final showSource = constraints.maxWidth > 850;
        return Material(
          color: opened
              ? QestoColors.primarySoft
              : selected
              ? const Color(0xFFF7F9FD)
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 58,
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Checkbox(
                      value: selected,
                      onChanged: (value) => onSelected(value ?? false),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      '${transaction.date.day.toString().padLeft(2, '0')}.${transaction.date.month.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: QestoColors.secondaryText,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: QestoColors.surfaceSecondary,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.shopping_bag_outlined,
                            size: 16,
                            color: QestoColors.secondaryText,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                desktopTransactionTitle(transaction),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (transaction.normalizedMerchant != null &&
                                  transaction.normalizedMerchant !=
                                      transaction.merchant)
                                Text(
                                  transaction.normalizedMerchant!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: QestoColors.secondaryText,
                                    fontSize: 9,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      desktopCategoryName(controller, transaction),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (showAccount)
                    Expanded(
                      flex: 2,
                      child: Text(
                        desktopAccountName(controller, transaction),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: QestoColors.secondaryText,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  if (showSource)
                    SizedBox(
                      width: 120,
                      child: Text(
                        desktopSourceLabel(controller, transaction.id),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: QestoColors.secondaryText,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: 52,
                    child: Tooltip(
                      message: desktopNeedsReview(transaction)
                          ? 'Требует проверки'
                          : 'Проверено',
                      child: Icon(
                        desktopNeedsReview(transaction)
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_outline_rounded,
                        color: desktopNeedsReview(transaction)
                            ? QestoColors.warning
                            : QestoColors.positive,
                        size: 18,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 116,
                    child: Text(
                      formatMoney(
                        desktopSignedAmount(transaction),
                        transaction.currency,
                        showSign: true,
                      ),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: desktopAmountColor(transaction),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TransactionDrawer extends StatefulWidget {
  const _TransactionDrawer({
    required this.controller,
    required this.transaction,
    required this.onClose,
    required this.onDeleted,
    super.key,
  });
  final BudgetController controller;
  final BudgetTransaction transaction;
  final VoidCallback onClose;
  final VoidCallback onDeleted;

  @override
  State<_TransactionDrawer> createState() => _TransactionDrawerState();
}

class _TransactionDrawerState extends State<_TransactionDrawer> {
  late String? _categoryId = widget.transaction.categoryId;
  late String _accountId = widget.transaction.accountId;
  late bool _reviewed = widget.transaction.isConfirmed;
  late final TextEditingController _merchantController = TextEditingController(
    text: desktopTransactionTitle(widget.transaction),
  );
  late final TextEditingController _noteController = TextEditingController(
    text: widget.transaction.comment ?? '',
  );

  @override
  void dispose() {
    _merchantController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transaction = widget.transaction;
    final evidence = desktopEvidenceFor(widget.controller, transaction.id);
    return Material(
      elevation: 16,
      color: QestoColors.surface,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: QestoColors.border)),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Операция',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть · Esc',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text(
                  desktopTransactionTitle(transaction),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  formatMoney(
                    desktopSignedAmount(transaction),
                    transaction.currency,
                    showSign: true,
                  ),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: desktopAmountColor(transaction),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${formatDate(transaction.date, includeYear: true)} · ${transaction.date.hour.toString().padLeft(2, '0')}:${transaction.date.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: QestoColors.secondaryText,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 20),
                _DrawerLabel('Категория'),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  isExpanded: true,
                  items: widget.controller.categories
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: 14),
                _DrawerLabel('Счёт'),
                DropdownButtonFormField<String>(
                  initialValue: _accountId,
                  isExpanded: true,
                  items: widget.controller.accounts
                      .map(
                        (item) => DropdownMenuItem(
                          value: item.id,
                          child: Text(item.title),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _accountId = value);
                  },
                ),
                const SizedBox(height: 14),
                _DrawerLabel('Merchant'),
                TextField(controller: _merchantController),
                const SizedBox(height: 14),
                _DrawerLabel('Заметка'),
                TextField(
                  controller: _noteController,
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _reviewed,
                  onChanged: (value) => setState(() => _reviewed = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Проверено',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Исправления становятся user-confirmed evidence',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
                const Divider(height: 28),
                const _DrawerLabel('Synoball provenance'),
                for (final item in evidence)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          desktopSourceIcon(item.sourceType),
                          size: 17,
                          color: QestoColors.secondaryText,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            desktopSourceTypeLabel(item.sourceType),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${(item.confidence * 100).round()}%',
                          style: const TextStyle(
                            color: QestoColors.secondaryText,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Категория',
                        style: TextStyle(
                          color: QestoColors.secondaryText,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Text(
                      '${(transaction.classificationConfidence * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DesktopProgressBar(
                  value: transaction.classificationConfidence,
                  color: transaction.classificationConfidence >= 0.8
                      ? QestoColors.positive
                      : QestoColors.warning,
                  height: 5,
                ),
                if (const bool.fromEnvironment('DEV_MODE')) ...[
                  const Divider(height: 28),
                  const _DrawerLabel('Developer'),
                  SelectableText(
                    'transaction: ${transaction.id}\naccount: ${transaction.accountId}\nevidence: ${evidence.map((item) => item.id).join(', ')}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: QestoColors.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: QestoColors.border)),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Удалить',
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Удалить операцию?'),
                        content: const Text(
                          'Она останется в audit trail Synoball как soft delete.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Удалить'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    await widget.controller.deleteTransaction(transaction.id);
                    widget.onDeleted();
                  },
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: QestoColors.negative,
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    await widget.controller.updateTransaction(
                      transaction.copyWith(
                        categoryId: _categoryId,
                        accountId: _accountId,
                        merchant: _merchantController.text.trim(),
                        comment: _noteController.text.trim(),
                        isConfirmed: _reviewed,
                        classificationConfidence: _reviewed
                            ? 1
                            : transaction.classificationConfidence,
                      ),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Операция сохранена в Synoball'),
                        ),
                      );
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: QestoColors.primary,
                  ),
                  child: const Text('Сохранить'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerLabel extends StatelessWidget {
  const _DrawerLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      label,
      style: const TextStyle(
        color: QestoColors.secondaryText,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.35,
      ),
    ),
  );
}
