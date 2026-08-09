enum FiscalReceiptKind { expense, refund }

class ParsedFiscalReceipt {
  const ParsedFiscalReceipt({
    required this.purchasedAt,
    required this.amountMinor,
    required this.fiscalDriveNumber,
    required this.fiscalDocumentNumber,
    required this.fiscalSign,
    required this.kind,
    required this.rawQr,
  });

  final DateTime purchasedAt;
  final int amountMinor;
  final String fiscalDriveNumber;
  final String fiscalDocumentNumber;
  final String fiscalSign;
  final FiscalReceiptKind kind;
  final String rawQr;

  int get roundedRubles => (amountMinor + 50) ~/ 100;
  bool get hasKopecks => amountMinor % 100 != 0;

  String get fingerprint =>
      '$fiscalDriveNumber:$fiscalDocumentNumber:$fiscalSign';
  String get transactionId => 'receipt-$fingerprint';
  String get transactionTag => 'receipt:$fingerprint';
}

class ParsedReceiptItem {
  const ParsedReceiptItem({
    required this.name,
    required this.totalMinor,
    this.quantity = 1,
    this.unitPriceMinor,
  });

  final String name;
  final double quantity;
  final int? unitPriceMinor;
  final int totalMinor;
}

class ParsedReceiptDocument {
  const ParsedReceiptDocument({
    required this.rawText,
    this.merchant,
    this.items = const [],
  });

  final String rawText;
  final String? merchant;
  final List<ParsedReceiptItem> items;
}
