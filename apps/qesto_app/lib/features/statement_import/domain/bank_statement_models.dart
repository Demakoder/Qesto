import '../../notification_import/domain/parsed_bank_transaction.dart';

enum StatementTransactionKind {
  expense,
  income,
  transfer,
  refund,
  savings,
  investment,
}

enum StatementCapitalKind { savings, deposit, investment }

class ParsedBankStatement {
  const ParsedBankStatement({
    required this.bankName,
    required this.periodStart,
    required this.periodEnd,
    required this.transactions,
    this.accountLastFour,
    this.sourceAccountKey,
    this.controlTotals,
    this.sourceRowCount,
  });

  final String bankName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String? accountLastFour;

  /// Hash of a complete provider account number, never a last-four identity.
  final String? sourceAccountKey;
  final List<ParsedStatementTransaction> transactions;
  // Adapter-only checks against the document, not inferred account balances.
  final StatementControlTotals? controlTotals;
  final int? sourceRowCount;
  int get inflowsMinor => transactions
      .where((r) => r.isIncoming)
      .fold(0, (n, r) => n + r.amountMinor.abs());
  int get outflowsMinor => transactions
      .where((r) => !r.isIncoming)
      .fold(0, (n, r) => n + r.amountMinor.abs());
  bool get hasReconciliationMismatch {
    final controls = controlTotals;
    return (sourceRowCount != null && sourceRowCount != transactions.length) ||
        (controls != null &&
            (controls.inflowsMinor != inflowsMinor ||
                controls.outflowsMinor != outflowsMinor ||
                controls.openingMinor + inflowsMinor - outflowsMinor !=
                    controls.closingMinor));
  }

  bool get controlTotalsVerified =>
      controlTotals != null && !hasReconciliationMismatch;

  ParsedStatementTransaction get latestTransaction => transactions.reduce(
    (latest, item) =>
        item.operationDate.isAfter(latest.operationDate) ? item : latest,
  );

  int get closingBalanceMinor =>
      controlTotals?.closingMinor ?? latestTransaction.balanceMinor;
  int get closingBalanceRubles => (closingBalanceMinor / 100).round();
}

class StatementControlTotals {
  const StatementControlTotals({
    required this.openingMinor,
    required this.closingMinor,
    required this.inflowsMinor,
    required this.outflowsMinor,
  });
  final int openingMinor;
  final int closingMinor;
  final int inflowsMinor;
  final int outflowsMinor;
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
    required this.isIncoming,
    required this.category,
    required this.confidence,
    this.currency = 'RUB',
    this.cardLastFour,
    this.capitalKind,
    this.capitalAccountName,
    this.excelLegacyId,
    this.excelObservationKey,
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
  final bool isIncoming;
  final CategorySuggestion category;
  final double confidence;
  final String currency;
  final String? cardLastFour;
  final StatementCapitalKind? capitalKind;
  final String? capitalAccountName;
  // Adapter-only provenance; neither field changes the Synoball schema.
  final String? excelLegacyId;
  final String? excelObservationKey;

  bool get hasKopecks => amountMinor.abs() % 100 != 0;
  int get roundedRubles => (amountMinor.abs() / 100).round();
}

class UnsupportedBankStatementException implements Exception {
  const UnsupportedBankStatementException(this.message);

  final String message;

  @override
  String toString() => message;
}
