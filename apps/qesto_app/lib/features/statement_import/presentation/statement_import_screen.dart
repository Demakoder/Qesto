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

class StatementImportScreen extends StatefulWidget {
  const StatementImportScreen({
    required this.controller,
    this.fileService = const BankStatementFileService(),
    this.parser = const SberbankStatementParser(),
    super.key,
  });

  final BudgetController controller;
  final BankStatementFileService fileService;
  final SberbankStatementParser parser;

  @override
  State<StatementImportScreen> createState() => _StatementImportScreenState();
}

class _StatementImportScreenState extends State<StatementImportScreen> {
  var _loading = false;
  String? _error;
  String? _fileName;
  ParsedBankStatement? _statement;
  Set<String> _selectedIds = <String>{};

  List<ParsedStatementTransaction> get _consumerTransactions =>
      _statement?.consumerTransactions ?? const [];

  List<ParsedStatementTransaction> get _eligibleTransactions =>
      _consumerTransactions
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

  Future<void> _pickStatement() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final file = await widget.fileService.pickPdf();
      if (file == null || !mounted) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final statement = widget.parser.parse(file.text);
      final selected = statement.consumerTransactions
          .where((item) => !widget.controller.hasTransaction(item.id))
          .map((item) => item.id)
          .toSet();
      setState(() {
        _loading = false;
        _fileName = file.fileName;
        _statement = statement;
        _selectedIds = selected;
      });
    } on UnsupportedBankStatementException catch (error) {
      _showError(error.message);
    } on PlatformException catch (error) {
      _showError(error.message ?? 'Не удалось прочитать PDF-выписку');
    } on FormatException catch (error) {
      _showError(error.message);
    } on Object {
      _showError('Не удалось обработать PDF-выписку');
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

  void _importSelected() {
    final selected = _selectedTransactions;
    if (selected.isEmpty) return;
    final account = widget.controller.accounts.firstWhere(
      (item) => item.type != AccountType.liability,
      orElse: () => widget.controller.accounts.first,
    );

    final transactions = <BudgetTransaction>[];
    for (final item in selected) {
      final period = widget.controller.periodForOrCreate(item.operationDate);
      final exactAmount = _formatMinorMoney(item.amountMinor);
      transactions.add(
        BudgetTransaction(
          id: item.id,
          userId: period.userId,
          accountId: account.id,
          date: item.operationDate,
          amount: item.roundedRubles,
          currency: period.currency,
          type: item.kind == StatementTransactionKind.refund
              ? TransactionType.refund
              : TransactionType.expense,
          categoryId: item.category.categoryId,
          subcategoryId: item.category.subcategoryId,
          merchant: item.merchant,
          title: item.merchant,
          description: item.description,
          comment:
              'Импортировано из выписки Сбербанка · код ${item.authorizationCode}'
              '${item.hasKopecks ? ' · точная сумма $exactAmount ₽' : ''}',
          normalizedMerchant: _normalizeMerchant(item.merchant),
          classificationConfidence: item.confidence,
          tags: const ['statement-import', 'sberbank'],
        ),
      );
    }

    widget.controller.addImportedTransactions(transactions);
    Navigator.of(context).pop(transactions.length);
  }

  @override
  Widget build(BuildContext context) {
    final statement = _statement;
    return Scaffold(
      appBar: NestedScreenHeader(
        title: Text(
          'Загрузить выписку',
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
                  onPressed: _selectedIds.isEmpty ? null : _importSelected,
                  icon: const Icon(Icons.download_done_rounded),
                  label: Text('Добавить выбранные (${_selectedIds.length})'),
                ),
              ),
            ),
    );
  }

  Widget _buildPickerState(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
      children: [
        QestoCard(
          child: Column(
            children: [
              const Icon(
                Icons.picture_as_pdf_rounded,
                size: 58,
                color: QestoColors.primary,
              ),
              const SizedBox(height: 14),
              Text(
                'Выписка Сбербанка в PDF',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Выберите выписку по платёжному счёту. Файл обрабатывается '
                'только на вашем устройстве и никуда не отправляется.',
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
                key: const Key('pick-statement-pdf'),
                onPressed: _loading ? null : _pickStatement,
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(_loading ? 'Читаем выписку…' : 'Выбрать PDF'),
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
    final skipped =
        statement.transactions.length - statement.consumerTransactions.length;
    final duplicates =
        statement.consumerTransactions.length - _eligibleTransactions.length;
    final allSelected = _selectedIds.length == _eligibleTransactions.length;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      itemCount: _consumerTransactions.length + 1,
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
                        _fileName ?? 'Выписка Сбербанка',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${formatDate(statement.periodStart, includeYear: true)} — '
                        '${formatDate(statement.periodEnd, includeYear: true)}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Найдено расходов и возвратов: '
                        '${statement.consumerTransactions.length}',
                      ),
                      if (skipped > 0)
                        Text('Доходов и переводов пропущено: $skipped'),
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

        final transaction = _consumerTransactions[index - 1];
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
                '${_categoryName(transaction.category.categoryId)}'
                '${duplicate ? ' · уже добавлено' : ''}',
              ),
              secondary: Text(
                '${transaction.kind == StatementTransactionKind.refund ? '+' : '−'}'
                '${_formatMinorMoney(transaction.amountMinor)} ₽',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: transaction.kind == StatementTransactionKind.refund
                      ? QestoColors.primary
                      : null,
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
