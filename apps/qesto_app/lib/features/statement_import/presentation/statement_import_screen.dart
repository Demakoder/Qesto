import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/formatters/qesto_formatters.dart';
import '../../../core/theme/qesto_theme.dart';
import '../../../core/widgets/nested_screen_header.dart';
import '../../../core/widgets/qesto_card.dart';
import '../../../data/models/qesto_models.dart';
import '../../budget/state/budget_controller.dart';
import '../data/bank_statement_file_service.dart';
import '../domain/bank_statement_models.dart';
import '../services/sberbank_statement_parser.dart';
import '../services/universal_excel_statement_adapter.dart';

class StatementImportScreen extends StatefulWidget {
  const StatementImportScreen({
    required this.controller,
    this.fileService = const BankStatementFileService(),
    this.parser = const SberbankStatementParser(),
    this.excelAdapter = const UniversalExcelStatementAdapter(),
    this.pickerMode = StatementPickerMode.all,
    super.key,
  });

  final BudgetController controller;
  final BankStatementFileService fileService;
  final SberbankStatementParser parser;
  final UniversalExcelStatementAdapter excelAdapter;
  final StatementPickerMode pickerMode;

  @override
  State<StatementImportScreen> createState() => _StatementImportScreenState();
}

class _StatementImportScreenState extends State<StatementImportScreen> {
  var _loading = false;
  String? _error;
  String? _fileName;
  String? _rawStatementText;
  ParsedBankStatement? _statement;
  Set<String> _selectedIds = <String>{};
  int? _yearOverride;

  List<ParsedStatementTransaction> get _statementTransactions =>
      _statement?.transactions ?? const [];

  List<ParsedStatementTransaction> get _eligibleTransactions =>
      _statementTransactions
          .where(
            (transaction) => !widget.controller.hasTransaction(transaction.id),
          )
          .toList(growable: false);

  int get _roundingCount => _selectedTransactions
      .where((transaction) => transaction.hasKopecks)
      .length;

  List<ParsedStatementTransaction> get _selectedTransactions =>
      _eligibleTransactions
          .where((transaction) => _selectedIds.contains(transaction.id))
          .toList(growable: false);

  bool get _hasExistingStatementTransactions => _statementTransactions.any(
    (transaction) => widget.controller.hasTransaction(transaction.id),
  );

  Future<void> _pickStatement() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final file = await widget.fileService.pickStatement(
        mode: widget.pickerMode,
      );
      if (file == null || !mounted) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      if (widget.pickerMode == StatementPickerMode.excel &&
          file.kind != StatementFileKind.excel) {
        throw const FormatException('Выберите таблицу в формате XLSX или XLSM');
      }
      if (widget.pickerMode == StatementPickerMode.statement &&
          file.kind == StatementFileKind.excel) {
        throw const FormatException('Выберите банковскую выписку PDF');
      }
      final statement = switch (file.kind) {
        StatementFileKind.excel => await widget.excelAdapter.parseInBackground(
          bytes: file.bytes!,
          fileName: file.fileName,
          referenceDate: widget.controller.referenceDate,
          yearOverride: _yearOverride,
        ),
        _ => widget.parser.parse(file.text),
      };
      final selected = statement.transactions
          .where((item) => !widget.controller.hasTransaction(item.id))
          .map((item) => item.id)
          .toSet();
      setState(() {
        _loading = false;
        _fileName = file.fileName;
        _rawStatementText = file.text.isNotEmpty
            ? file.text
            : jsonEncode({
                'source': 'qesto-excel-adapter-v1',
                'fileName': file.fileName,
                'byteLength': file.bytes?.length ?? 0,
                'transactions': statement.transactions.length,
              });
        _statement = statement;
        _selectedIds = selected;
      });
    } on UnsupportedBankStatementException catch (error) {
      _showError(error.message);
    } on PlatformException catch (error) {
      _showError(error.message ?? 'Не удалось прочитать выбранный файл');
    } on FormatException catch (error) {
      _showError(error.message);
    } on Object {
      _showError('Не удалось обработать выписку или Excel-таблицу');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  void _toggleAll() {
    setState(() {
      if (_selectedIds.length == _eligibleTransactions.length) {
        _selectedIds = <String>{};
      } else {
        _selectedIds = _eligibleTransactions.map((item) => item.id).toSet();
      }
    });
  }

  void _toggleTransaction(ParsedStatementTransaction transaction) {
    if (widget.controller.hasTransaction(transaction.id)) return;
    setState(() {
      if (!_selectedIds.add(transaction.id)) {
        _selectedIds.remove(transaction.id);
      }
    });
  }

  Future<void> _importSelected() async {
    final selected = _selectedTransactions;
    final selectedIds = selected.map((item) => item.id).toSet();
    final transactionsToApply = _statementTransactions
        .where(
          (item) =>
              selectedIds.contains(item.id) ||
              widget.controller.hasTransaction(item.id),
        )
        .toList();
    if (transactionsToApply.isEmpty) return;
    final statement = _statement!;
    final currentAccount = widget.controller.accounts.first;
    final accountSuffix = statement.accountLastFour == null
        ? ''
        : ' • ${statement.accountLastFour}';
    final sourceId = statement.bankName == 'Excel'
        ? 'excel-${_stableFileId(_fileName ?? 'excel')}'
        : 'sber-${statement.accountLastFour ?? 'statement'}';
    final sourceTitle = statement.bankName == 'Excel'
        ? 'Импорт из Excel'
        : 'Счёт Сбербанка$accountSuffix';
    final account = QestoAccount(
      id: '$sourceId-account',
      userId: currentAccount.userId,
      title: sourceTitle,
      balance: statement.closingBalanceRubles,
      currency: statement.transactions.first.currency,
      type: statement.bankName == 'Excel'
          ? AccountType.other
          : AccountType.bankCard,
    );
    final capitalTotals = <String, _CapitalAccountDraft>{};
    for (final item in transactionsToApply) {
      final kind = item.capitalKind;
      if (kind == null) continue;
      final name = item.capitalAccountName?.trim().isNotEmpty == true
          ? item.capitalAccountName!.trim()
          : _capitalAccountDefaultName(kind);
      final key = '${kind.name}|${name.toLowerCase()}';
      final existing = capitalTotals[key];
      capitalTotals[key] = _CapitalAccountDraft(
        name: name,
        kind: kind,
        amountMinor: (existing?.amountMinor ?? 0) + item.amountMinor.abs(),
      );
    }
    final capitalAccounts = [
      for (final entry in capitalTotals.entries)
        QestoAccount(
          id: '$sourceId-capital-${_stableFileId(entry.key)}',
          userId: currentAccount.userId,
          title: entry.value.name,
          balance: (entry.value.amountMinor / 100).round(),
          currency: statement.transactions.first.currency,
          type: switch (entry.value.kind) {
            StatementCapitalKind.savings => AccountType.savings,
            StatementCapitalKind.deposit => AccountType.deposit,
            StatementCapitalKind.investment => AccountType.investment,
          },
        ),
    ];
    final knownPeriodIds = widget.controller.periods
        .map((period) => period.id)
        .toSet();

    final transactions = <BudgetTransaction>[];
    for (final item in transactionsToApply) {
      final period = widget.controller.periodForOrCreate(item.operationDate);
      final exactAmount = _formatMinorMoney(item.amountMinor);
      transactions.add(
        BudgetTransaction(
          id: item.id,
          userId: period.userId,
          accountId: account.id,
          date: item.operationDate,
          amount: item.roundedRubles,
          currency: item.currency,
          type: _transactionType(item.kind),
          categoryId: item.category.categoryId,
          subcategoryId: item.category.subcategoryId,
          merchant: item.merchant,
          title: item.merchant,
          description: item.description,
          comment:
              'Импортировано из ${statement.bankName == 'Excel' ? 'Excel' : 'выписки Сбербанка'} · источник ${item.authorizationCode}'
              '${item.hasKopecks ? ' · точная сумма $exactAmount ₽' : ''}',
          normalizedMerchant: _normalizeMerchant(item.merchant),
          classificationConfidence: item.confidence,
          transferDirection: item.kind == StatementTransactionKind.transfer
              ? item.isIncoming
                    ? TransferDirection.incoming
                    : TransferDirection.outgoing
              : null,
          tags: [
            'statement-import',
            if (statement.bankName == 'Excel') 'excel-import' else 'sberbank',
            if (item.description.contains('агрегировано за период'))
              'excel-period-aggregate',
            if (item.capitalKind != null) 'excel-capital-allocation',
            if (item.kind == StatementTransactionKind.transfer)
              item.isIncoming ? 'transfer-incoming' : 'transfer-outgoing',
          ],
        ),
      );
    }

    final createdPeriodIds = widget.controller.periods
        .map((period) => period.id)
        .where((id) => !knownPeriodIds.contains(id))
        .toSet();
    final importedCount = await widget.controller.importStatement(
      account: account,
      transactions: transactions,
      createdPeriodIds: createdPeriodIds,
      actionTitle: 'Импорт ${_fileName ?? statement.bankName}',
      rawPayload: _rawStatementText,
      exactMinorById: {
        for (final item in transactionsToApply) item.id: item.amountMinor.abs(),
      },
      additionalAccounts: capitalAccounts,
    );
    if (!mounted) return;
    Navigator.of(context).pop(importedCount);
  }

  @override
  Widget build(BuildContext context) {
    final statement = _statement;
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text(
          widget.pickerMode == StatementPickerMode.excel
              ? 'Добавить Excel-таблицу'
              : 'Загрузить выписку',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: SafeArea(
        top: false,
        child: statement == null
            ? _buildPickerState(context)
            : _buildStatement(context, statement),
      ),
      bottomNavigationBar: statement == null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                child: FilledButton.icon(
                  key: const Key('import-statement-transactions'),
                  onPressed:
                      _selectedIds.isEmpty && !_hasExistingStatementTransactions
                      ? null
                      : _importSelected,
                  icon: const Icon(Icons.download_done_rounded),
                  label: Text(
                    _selectedIds.isEmpty
                        ? 'Обновить данные счёта'
                        : 'Добавить выбранные (${_selectedIds.length})',
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildPickerState(BuildContext context) {
    final excelOnly = widget.pickerMode == StatementPickerMode.excel;
    final statementOnly = widget.pickerMode == StatementPickerMode.statement;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
      children: [
        QestoCard(
          child: Column(
            children: [
              Icon(
                excelOnly
                    ? Icons.table_view_rounded
                    : Icons.account_balance_rounded,
                size: 58,
                color: QestoColors.primary,
              ),
              const SizedBox(height: 14),
              Text(
                excelOnly
                    ? 'Excel-таблица'
                    : statementOnly
                    ? 'Выписка Сбербанка в PDF'
                    : 'Выписка или Excel-таблица',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                excelOnly
                    ? 'Выберите XLSX или XLSM с журналом операций либо помесячной таблицей. '
                          'Данные обрабатываются на устройстве, макросы не запускаются.'
                    : statementOnly
                    ? 'Выберите PDF-выписку Сбербанка. Она будет преобразована адаптером '
                          'в стандартный формат перед импортом в Synoball.'
                    : 'Поддерживаются PDF Сбербанка, XLSX и XLSM с журналами операций '
                          'или помесячными таблицами. Всё обрабатывается только на вашем устройстве; '
                          'макросы не запускаются.',
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
              if (excelOnly) ...[
                DropdownButtonFormField<int?>(
                  key: const Key('excel-year-override'),
                  initialValue: _yearOverride,
                  decoration: const InputDecoration(
                    labelText: 'Год данных',
                    helperText:
                        'Авто использует год из книги или определяет его по заполненным месяцам',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Определить автоматически'),
                    ),
                    for (var offset = 0; offset < 8; offset++)
                      DropdownMenuItem<int?>(
                        value: widget.controller.referenceDate.year - offset,
                        child: Text(
                          '${widget.controller.referenceDate.year - offset}',
                        ),
                      ),
                  ],
                  onChanged: _loading
                      ? null
                      : (value) => setState(() => _yearOverride = value),
                ),
                const SizedBox(height: 14),
              ],
              FilledButton.icon(
                key: Key(excelOnly ? 'pick-excel-file' : 'pick-statement-pdf'),
                onPressed: _loading ? null : _pickStatement,
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(
                  _loading
                      ? 'Анализируем данные…'
                      : excelOnly
                      ? 'Выбрать Excel-файл'
                      : 'Выбрать выписку',
                ),
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

  Widget _buildStatement(BuildContext context, ParsedBankStatement statement) {
    final counts = {
      for (final kind in StatementTransactionKind.values)
        kind: statement.transactions
            .where((transaction) => transaction.kind == kind)
            .length,
    };
    final incomingTransfers = statement.transactions
        .where(
          (transaction) =>
              transaction.kind == StatementTransactionKind.transfer &&
              transaction.isIncoming,
        )
        .length;
    final outgoingTransfers =
        (counts[StatementTransactionKind.transfer] ?? 0) - incomingTransfers;
    final duplicates =
        statement.transactions.length - _eligibleTransactions.length;
    final allSelected = _selectedIds.length == _eligibleTransactions.length;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      itemCount: _statementTransactions.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                QestoCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fileName ?? 'Финансовые данные',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${formatDate(statement.periodStart, includeYear: true)} — '
                        '${formatDate(statement.periodEnd, includeYear: true)}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${statement.bankName == 'Excel' ? 'Универсальный Excel-адаптер' : 'Счёт Сбербанка'}'
                        '${statement.accountLastFour == null ? '' : ' • ${statement.accountLastFour}'}'
                        '${statement.bankName == 'Excel' ? '' : ' · остаток ${formatMoney(statement.closingBalanceRubles, 'RUB')}'}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Найдено операций: ${statement.transactions.length}',
                      ),
                      Text(
                        'Расходов: ${counts[StatementTransactionKind.expense]} · '
                        'возвратов: ${counts[StatementTransactionKind.refund]}',
                      ),
                      Text(
                        'Доходов: ${counts[StatementTransactionKind.income]} · '
                        'переводов: ${counts[StatementTransactionKind.transfer]} '
                        '(входящих: $incomingTransfers, исходящих: $outgoingTransfers)',
                      ),
                      if ((counts[StatementTransactionKind.savings] ?? 0) > 0 ||
                          (counts[StatementTransactionKind.investment] ?? 0) >
                              0)
                        Text(
                          'В капитал: накопления — '
                          '${counts[StatementTransactionKind.savings]} · '
                          'инвестиции — '
                          '${counts[StatementTransactionKind.investment]}',
                        ),
                      if (duplicates > 0)
                        Text('Уже добавленных операций: $duplicates'),
                      if (_roundingCount > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Суммы с копейками будут округлены до ближайшего рубля. '
                          'Точная сумма сохранится в комментарии.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: QestoColors.orange),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Операции',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    TextButton(
                      key: const Key('toggle-all-statement-transactions'),
                      onPressed: _eligibleTransactions.isEmpty
                          ? null
                          : _toggleAll,
                      child: Text(allSelected ? 'Снять все' : 'Выбрать все'),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        final transaction = _statementTransactions[index - 1];
        final duplicate = widget.controller.hasTransaction(transaction.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: QestoCard(
            padding: EdgeInsets.zero,
            child: CheckboxListTile(
              key: Key('statement-transaction-${transaction.id}'),
              value: !duplicate && _selectedIds.contains(transaction.id),
              onChanged: duplicate
                  ? null
                  : (_) => _toggleTransaction(transaction),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
              title: Text(
                transaction.merchant,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${formatDate(transaction.operationDate, includeYear: true)} · '
                '${_kindLabel(transaction.kind)} · '
                '${_categoryName(transaction.category.categoryId)}'
                '${duplicate ? ' · уже добавлено' : ''}',
              ),
              secondary: Text(
                '${_amountSign(transaction)}'
                '${_formatMinorMoney(transaction.amountMinor)} ₽',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _isCredit(transaction) ? QestoColors.primary : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _categoryName(String id) => widget.controller.categories
      .firstWhere(
        (category) => category.id == id,
        orElse: () => widget.controller.categories.last,
      )
      .name;
}

TransactionType _transactionType(StatementTransactionKind kind) =>
    switch (kind) {
      StatementTransactionKind.expense => TransactionType.expense,
      StatementTransactionKind.income => TransactionType.income,
      StatementTransactionKind.transfer => TransactionType.transfer,
      StatementTransactionKind.refund => TransactionType.refund,
      StatementTransactionKind.savings => TransactionType.savingsTransfer,
      StatementTransactionKind.investment => TransactionType.investment,
    };

String _kindLabel(StatementTransactionKind kind) => switch (kind) {
  StatementTransactionKind.expense => 'Расход',
  StatementTransactionKind.income => 'Доход',
  StatementTransactionKind.transfer => 'Перевод',
  StatementTransactionKind.refund => 'Возврат',
  StatementTransactionKind.savings => 'В накопления',
  StatementTransactionKind.investment => 'Инвестиция',
};

bool _isCredit(ParsedStatementTransaction transaction) =>
    transaction.kind == StatementTransactionKind.refund ||
    transaction.kind == StatementTransactionKind.income ||
    transaction.isIncoming;

String _amountSign(ParsedStatementTransaction transaction) =>
    _isCredit(transaction) ? '+' : '−';

String _formatMinorMoney(int amountMinor) {
  final whole = amountMinor.abs() ~/ 100;
  final fraction = amountMinor.abs() % 100;
  final formattedWhole = formatMoney(whole, 'RUB').replaceFirst(' ₽', '');
  return fraction == 0
      ? formattedWhole
      : '$formattedWhole,${fraction.toString().padLeft(2, '0')}';
}

String _normalizeMerchant(String value) => value
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
    .trim();

String _stableFileId(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.toLowerCase().codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _capitalAccountDefaultName(StatementCapitalKind kind) => switch (kind) {
  StatementCapitalKind.savings => 'Накопления из Excel',
  StatementCapitalKind.deposit => 'Депозит из Excel',
  StatementCapitalKind.investment => 'Инвестиции из Excel',
};

class _CapitalAccountDraft {
  const _CapitalAccountDraft({
    required this.name,
    required this.kind,
    required this.amountMinor,
  });

  final String name;
  final StatementCapitalKind kind;
  final int amountMinor;
}
