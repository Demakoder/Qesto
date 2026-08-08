import '../../notification_import/domain/parsed_bank_transaction.dart';

enum StatementTransactionKind { expense, income, transfer, refund }

class ParsedBankStatement {
  const ParsedBankStatement({
    required this.bankName,
    required this.periodStart,
    required this.periodEnd,
    required this.transactions,
    this.accountLastFour,
  });

  final String bankName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String? accountLastFour;
  final List<ParsedStatementTransaction> transactions;

  List<ParsedStatementTransaction> get consumerTransactions => transactions
      .where(
        (transaction) =>
            transaction.kind == StatementTransactionKind.expense ||
            transaction.kind == StatementTransactionKind.refund,
      )
      .toList(growable: false);
}

class ParsedStatementTransaction {
  const ParsedStatementTransaction({
    required this.id,
    required this.operationDate,
    required this.processingDate,
    required this.authorizationCode,
    required this.bankCategory,
    required this.description,
    required this.merchant,
    required this.amountMinor,
    required this.balanceMinor,
    required this.kind,
    required this.category,
    required this.confidence,
    this.cardLastFour,
  });

  final String id;
  final DateTime operationDate;
  final DateTime processingDate;
  final String authorizationCode;
  final String bankCategory;
  final String description;
  final String merchant;
  final int amountMinor;
  final int balanceMinor;
  final StatementTransactionKind kind;
  final CategorySuggestion category;
  final double confidence;
  final String? cardLastFour;

  bool get hasKopecks => amountMinor.abs() % 100 != 0;
  int get roundedRubles => (amountMinor.abs() / 100).round();
}

class UnsupportedBankStatementException implements Exception {
  const UnsupportedBankStatementException(this.message);

  final String message;

  @override
  String toString() => message;
}
