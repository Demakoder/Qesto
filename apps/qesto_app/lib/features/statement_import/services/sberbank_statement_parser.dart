import '../../notification_import/domain/parsed_bank_transaction.dart';
import '../../notification_import/services/merchant_category_classifier.dart';
import '../domain/bank_statement_models.dart';

class SberbankStatementParser {
  const SberbankStatementParser({
    this.classifier = const MerchantCategoryClassifier(),
  });

  final MerchantCategoryClassifier classifier;

  static final _periodPattern = RegExp(
    r'За период\s+(\d{2}\.\d{2}\.\d{4})\s*[-—–]\s*(\d{2}\.\d{2}\.\d{4})',
    caseSensitive: false,
  );
  static final _accountPattern = RegExp(
    r'Номер сч[её]та\s+([\d\s]{12,})',
    caseSensitive: false,
  );
  static final _operationPattern = RegExp(
    r'^\s*(\d{2}\.\d{2}\.\d{4})\s+(\d{2}:\d{2})\s+(.+?)\s+([+\-−]?\d[\d\s\u00A0]*,\d{2})\s+([\-−]?\d[\d\s\u00A0]*,\d{2})\s*$',
  );
  static final _columnarOperationPattern = RegExp(
    r'^\s*(\d{2}\.\d{2}\.\d{4})\s+(\d{2}:\d{2})\s+(.+?)\s+(\d{2}\.\d{2}\.\d{4})\s+(\d{6})\s+(.+?)\s*$',
  );
  static final _detailsPattern = RegExp(
    r'^\s*(\d{2}\.\d{2}\.\d{4})\s+(\d{6})\s+(.*)$',
  );
  static final _moneyOnlyPattern = RegExp(r'^[+\-−]?\d[\d\s\u00A0]*,\d{2}$');
  static final _cardPattern = RegExp(r'\*{2,}(\d{4})');

  ParsedBankStatement parse(String source) {
    final text = source.replaceAll('\u00A0', ' ');
    if (!_looksLikeSberbankStatement(text)) {
      throw const UnsupportedBankStatementException(
        'Поддерживаются только PDF-выписки Сбербанка по платёжному счёту',
      );
    }

    final period = _periodPattern.firstMatch(text);
    if (period == null) {
      throw const UnsupportedBankStatementException(
        'Не удалось определить период выписки Сбербанка',
      );
    }

    final pendingTransactions = _parseRowTransactions(text);
    if (pendingTransactions.isEmpty) {
      pendingTransactions.addAll(_parseColumnarTransactions(text));
    }

    final transactions = pendingTransactions
        .map(_buildTransaction)
        .toList(growable: false);
    if (transactions.isEmpty) {
      throw const UnsupportedBankStatementException(
        'В выписке Сбербанка не найдены операции',
      );
    }

    return ParsedBankStatement(
      bankName: 'Сбербанк',
      periodStart: _parseDate(period.group(1)!),
      periodEnd: _parseDate(period.group(2)!),
      accountLastFour: _accountLastFour(text),
      transactions: transactions,
    );
  }

  List<_PendingStatementTransaction> _parseRowTransactions(String text) {
    final pendingTransactions = <_PendingStatementTransaction>[];
    _PendingStatementTransaction? current;

    for (final rawLine in text.split(RegExp(r'\r?\n'))) {
      final line = rawLine.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (line.isEmpty) continue;

      final operation = _operationPattern.firstMatch(line);
      if (operation != null) {
        if (current?.isComplete ?? false) pendingTransactions.add(current!);
        current = _PendingStatementTransaction(
          operationDate: _parseDateTime(
            operation.group(1)!,
            operation.group(2)!,
          ),
          bankCategory: operation.group(3)!.trim(),
          amountText: operation.group(4)!,
          balanceText: operation.group(5)!,
        );
        continue;
      }

      final details = _detailsPattern.firstMatch(line);
      if (details != null && current != null) {
        current
          ..processingDate = _parseDate(details.group(1)!)
          ..authorizationCode = details.group(2)!
          ..description = details.group(3)!.trim();
        continue;
      }

      if (current?.isComplete ?? false) {
        if (!_isBoilerplate(line)) {
          current!.description = '${current.description} $line'.trim();
        }
      }
    }
    if (current?.isComplete ?? false) pendingTransactions.add(current!);
    return pendingTransactions;
  }

  List<_PendingStatementTransaction> _parseColumnarTransactions(String text) {
    final transactions = <_PendingStatementTransaction>[];
    for (final page in _splitPages(text)) {
      final lines = page
          .split(RegExp(r'\r?\n'))
          .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      final pageOperations = <_ColumnarStatementTransaction>[];
      final pageMoney = <String>[];
      _ColumnarStatementTransaction? current;
      var readingMoney = false;

      for (final line in lines) {
        if (_isMoneyColumnHeader(line)) {
          readingMoney = true;
          current = null;
          continue;
        }
        if (readingMoney) {
          if (_moneyOnlyPattern.hasMatch(line)) pageMoney.add(line);
          continue;
        }

        final operation = _columnarOperationPattern.firstMatch(line);
        if (operation != null) {
          current = _ColumnarStatementTransaction(
            operationDate: _parseDateTime(
              operation.group(1)!,
              operation.group(2)!,
            ),
            bankCategory: operation.group(3)!.trim(),
            processingDate: _parseDate(operation.group(4)!),
            authorizationCode: operation.group(5)!,
            description: operation.group(6)!.trim(),
          );
          pageOperations.add(current);
          continue;
        }

        if (current != null && _isColumnarDescriptionContinuation(line)) {
          current.description = '${current.description} $line'.trim();
        }
        if (_endsOperationColumn(line)) current = null;
      }

      final pairCount = pageMoney.length ~/ 2;
      final transactionCount = pairCount < pageOperations.length
          ? pairCount
          : pageOperations.length;
      for (var index = 0; index < transactionCount; index++) {
        final operation = pageOperations[index];
        transactions.add(
          _PendingStatementTransaction(
              operationDate: operation.operationDate,
              bankCategory: operation.bankCategory,
              amountText: pageMoney[index * 2],
              balanceText: pageMoney[(index * 2) + 1],
            )
            ..processingDate = operation.processingDate
            ..authorizationCode = operation.authorizationCode
            ..description = operation.description,
        );
      }
    }
    return transactions;
  }

  List<String> _splitPages(String text) {
    final explicitPages = text
        .split('\f')
        .where((page) => page.trim().isNotEmpty)
        .toList(growable: false);
    if (explicitPages.length > 1) return explicitPages;

    final pageStarts = RegExp(
      r'(?=Выписка по плат[её]жному сч[её]ту\s+Страница\s+\d+\s+из\s+\d+)',
      caseSensitive: false,
    );
    return text
        .split(pageStarts)
        .where((page) => page.trim().isNotEmpty)
        .toList(growable: false);
  }

  bool _isMoneyColumnHeader(String line) {
    final normalized = line.toLowerCase().replaceAll('ё', 'е');
    return normalized.contains('сумма в валюте счета') &&
        normalized.contains('остаток средств');
  }

  bool _isColumnarDescriptionContinuation(String line) {
    if (_moneyOnlyPattern.hasMatch(line)) return false;
    if (_columnarOperationPattern.hasMatch(line)) return false;
    if (_isBoilerplate(line) || _endsOperationColumn(line)) return false;
    final normalized = line.toLowerCase().replaceAll('ё', 'е');
    return !normalized.startsWith('итого по операциям') &&
        !normalized.startsWith('остаток на ') &&
        !normalized.startsWith('пополнение') &&
        !normalized.startsWith('списание') &&
        !normalized.startsWith('заказано в сбербанк онлайн') &&
        !RegExp(r'^\d+\.\s').hasMatch(line);
  }

  bool _endsOperationColumn(String line) {
    final normalized = line.toLowerCase().replaceAll('ё', 'е');
    return normalized.startsWith('продолжение на следующей странице') ||
        normalized.startsWith('для проверки подлинности документа') ||
        normalized.startsWith('итого по операциям') ||
        _isMoneyColumnHeader(line);
  }

  bool _looksLikeSberbankStatement(String text) {
    final normalized = text.toLowerCase().replaceAll('ё', 'е');
    return (normalized.contains('сбербанк') ||
            normalized.contains('sberbank.ru')) &&
        normalized.contains('выписка по платежному счету') &&
        normalized.contains('расшифровка операций');
  }

  ParsedStatementTransaction _buildTransaction(
    _PendingStatementTransaction pending,
  ) {
    final amountMinor = _parseMoneyMinor(pending.amountText);
    final kind = _kindFor(pending.bankCategory, pending.amountText);
    final merchant = _merchantFrom(pending.description, pending.bankCategory);
    final category = _categoryFor(merchant, pending.bankCategory);
    final cardLastFour = _cardPattern.firstMatch(pending.description)?.group(1);
    final dateKey = pending.operationDate.toIso8601String();

    return ParsedStatementTransaction(
      id: 'sber-$dateKey-${pending.authorizationCode}',
      operationDate: pending.operationDate,
      processingDate: pending.processingDate!,
      authorizationCode: pending.authorizationCode!,
      bankCategory: pending.bankCategory,
      description: pending.description,
      merchant: merchant,
      amountMinor: amountMinor.abs(),
      balanceMinor: _parseMoneyMinor(pending.balanceText),
      kind: kind,
      isIncoming: pending.amountText.trimLeft().startsWith('+'),
      category: category,
      confidence: category.categoryId == 'other' ? 0.55 : 0.9,
      cardLastFour: cardLastFour,
    );
  }

  StatementTransactionKind _kindFor(String category, String amountText) {
    final normalized = category.toLowerCase().replaceAll('ё', 'е');
    if (normalized.contains('возврат') || normalized.contains('отмена')) {
      return StatementTransactionKind.refund;
    }
    if (normalized.startsWith('перевод') ||
        normalized.contains('внесение наличных') ||
        normalized.contains('выдача наличных')) {
      return StatementTransactionKind.transfer;
    }
    if (amountText.trimLeft().startsWith('+')) {
      return StatementTransactionKind.income;
    }
    return StatementTransactionKind.expense;
  }

  CategorySuggestion _categoryFor(String merchant, String bankCategory) {
    final merchantSuggestion = classifier.classify(merchant);
    if (merchantSuggestion.categoryId != 'other') return merchantSuggestion;

    final category = bankCategory.toLowerCase().replaceAll('ё', 'е');
    if (category.contains('супермаркет')) {
      return const CategorySuggestion(
        categoryId: 'groceries',
        subcategoryId: 'Супермаркеты',
      );
    }
    if (category.contains('ресторан') || category.contains('кафе')) {
      return const CategorySuggestion(categoryId: 'cafes');
    }
    if (category.contains('транспорт')) {
      return const CategorySuggestion(categoryId: 'transport');
    }
    if (category.contains('путешеств')) {
      return const CategorySuggestion(categoryId: 'travel');
    }
    if (category.contains('развлечен')) {
      return const CategorySuggestion(categoryId: 'fun');
    }
    return const CategorySuggestion(categoryId: 'other');
  }

  String _merchantFrom(String description, String bankCategory) {
    final withoutOperation = description
        .replaceFirst(RegExp(r'\.?\s*Операция по .*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (withoutOperation.isEmpty) return bankCategory;
    return withoutOperation;
  }

  String? _accountLastFour(String text) {
    final match = _accountPattern.firstMatch(text);
    if (match == null) return null;
    final digits = match.group(1)!.replaceAll(RegExp(r'\D'), '');
    return digits.length < 4 ? null : digits.substring(digits.length - 4);
  }

  bool _isBoilerplate(String line) {
    final normalized = line.toLowerCase();
    return normalized.startsWith('выписка по') ||
        normalized.startsWith('страница ') ||
        normalized.startsWith('дата операции') ||
        normalized.startsWith('дата обработки') ||
        normalized.startsWith('и код авторизации') ||
        normalized.startsWith('продолжение на следующей странице') ||
        normalized.startsWith('для проверки подлинности') ||
        normalized.startsWith('действителен до');
  }

  DateTime _parseDate(String value) {
    final parts = value.split('.').map(int.parse).toList(growable: false);
    return DateTime(parts[2], parts[1], parts[0]);
  }

  DateTime _parseDateTime(String date, String time) {
    final parsedDate = _parseDate(date);
    final timeParts = time.split(':').map(int.parse).toList(growable: false);
    return DateTime(
      parsedDate.year,
      parsedDate.month,
      parsedDate.day,
      timeParts[0],
      timeParts[1],
    );
  }

  int _parseMoneyMinor(String value) {
    final normalized = value
        .replaceAll('−', '-')
        .replaceAll(RegExp(r'[\s\u00A0]'), '')
        .replaceAll(',', '.');
    return (double.parse(normalized) * 100).round();
  }
}

class _PendingStatementTransaction {
  _PendingStatementTransaction({
    required this.operationDate,
    required this.bankCategory,
    required this.amountText,
    required this.balanceText,
  });

  final DateTime operationDate;
  final String bankCategory;
  final String amountText;
  final String balanceText;
  DateTime? processingDate;
  String? authorizationCode;
  String description = '';

  bool get isComplete =>
      processingDate != null &&
      authorizationCode != null &&
      description.isNotEmpty;
}

class _ColumnarStatementTransaction {
  _ColumnarStatementTransaction({
    required this.operationDate,
    required this.bankCategory,
    required this.processingDate,
    required this.authorizationCode,
    required this.description,
  });

  final DateTime operationDate;
  final String bankCategory;
  final DateTime processingDate;
  final String authorizationCode;
  String description;
}
