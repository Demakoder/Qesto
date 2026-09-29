class CategorySuggestion {
  const CategorySuggestion({required this.categoryId, this.subcategoryId});

  final String categoryId;
  final String? subcategoryId;
}

enum ParsedBankTransactionKind { expense, income, transfer, refund }

class ParsedBankTransaction {
  const ParsedBankTransaction({
    required this.notificationKey,
    required this.sourcePackage,
    required this.date,
    required this.amountMinor,
    required this.currency,
    required this.merchant,
    required this.categoryId,
    required this.confidence,
    this.kind = ParsedBankTransactionKind.expense,
    this.isSmsNotification = false,
    this.bankHint,
    this.subcategoryId,
    this.accountHint,
  });

  final String notificationKey;
  final String sourcePackage;
  final DateTime date;
  final int amountMinor;
  final String currency;
  final String merchant;
  final String categoryId;
  final String? subcategoryId;
  final String? accountHint;
  final double confidence;
  final ParsedBankTransactionKind kind;
  final bool isSmsNotification;
  final String? bankHint;

  bool get hasWholeCurrencyAmount => amountMinor % 100 == 0;
  int get wholeCurrencyAmount => amountMinor ~/ 100;
}
