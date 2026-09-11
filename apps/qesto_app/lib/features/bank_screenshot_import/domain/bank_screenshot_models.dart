import '../../../data/models/qesto_models.dart';

class BankScreenshotTextLine {
  const BankScreenshotTextLine({
    required this.text,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.confidence,
  });

  final String text;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final double? confidence;

  factory BankScreenshotTextLine.fromMap(Map<Object?, Object?> map) =>
      BankScreenshotTextLine(
        text: map['text']?.toString() ?? '',
        left: _number(map['left']),
        top: _number(map['top']),
        right: _number(map['right']),
        bottom: _number(map['bottom']),
        confidence: _number(map['confidence']),
      );

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}

class ExtractedBankScreenshot {
  const ExtractedBankScreenshot({
    required this.imageHash,
    required this.capturedAt,
    required this.lines,
    this.width,
    this.height,
  });

  final String imageHash;
  final DateTime capturedAt;
  final List<BankScreenshotTextLine> lines;
  final double? width;
  final double? height;

  factory ExtractedBankScreenshot.fromMap(Map<Object?, Object?> map) {
    final rawLines = map['lines'];
    return ExtractedBankScreenshot(
      imageHash: map['imageHash']?.toString() ?? '',
      capturedAt:
          DateTime.tryParse(map['capturedAt']?.toString() ?? '') ??
          DateTime.now(),
      width: BankScreenshotTextLine._number(map['width']),
      height: BankScreenshotTextLine._number(map['height']),
      lines: rawLines is List
          ? rawLines
                .whereType<Map>()
                .map(
                  (line) => BankScreenshotTextLine.fromMap(
                    Map<Object?, Object?>.from(line),
                  ),
                )
                .where((line) => line.text.trim().isNotEmpty)
                .toList(growable: false)
          : const [],
    );
  }
}

enum BankScreenshotTransactionKind { expense, income, transfer, refund }

class BankScreenshotCandidate {
  const BankScreenshotCandidate({
    required this.id,
    required this.imageHash,
    required this.parserId,
    required this.merchant,
    required this.amountMinor,
    required this.currency,
    required this.date,
    required this.kind,
    required this.categoryId,
    required this.confidence,
    this.accountId,
    this.accountHint,
    this.balanceAfterMinor,
    this.dateOnly = true,
    this.selected = true,
    this.legacyProviderId,
    this.possibleDuplicateReason,
  });

  final String id;
  final String imageHash;
  final String parserId;
  final String merchant;
  final int amountMinor;
  final String currency;
  final DateTime date;
  final BankScreenshotTransactionKind kind;
  final String categoryId;
  final double confidence;
  final String? accountId;
  final String? accountHint;
  final int? balanceAfterMinor;
  final bool dateOnly;
  final bool selected;
  final String? legacyProviderId;
  final String? possibleDuplicateReason;

  TransactionType get transactionType => switch (kind) {
    BankScreenshotTransactionKind.expense => TransactionType.expense,
    BankScreenshotTransactionKind.income => TransactionType.income,
    BankScreenshotTransactionKind.transfer => TransactionType.transfer,
    BankScreenshotTransactionKind.refund => TransactionType.refund,
  };

  BankScreenshotCandidate copyWith({
    String? id,
    String? legacyProviderId,
    String? possibleDuplicateReason,
    String? merchant,
    int? amountMinor,
    String? currency,
    DateTime? date,
    BankScreenshotTransactionKind? kind,
    String? categoryId,
    double? confidence,
    String? accountId,
    bool clearAccountId = false,
    String? accountHint,
    int? balanceAfterMinor,
    bool? dateOnly,
    bool? selected,
  }) => BankScreenshotCandidate(
    id: id ?? this.id,
    imageHash: imageHash,
    parserId: parserId,
    merchant: merchant ?? this.merchant,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    date: date ?? this.date,
    kind: kind ?? this.kind,
    categoryId: categoryId ?? this.categoryId,
    confidence: confidence ?? this.confidence,
    accountId: clearAccountId ? null : accountId ?? this.accountId,
    accountHint: accountHint ?? this.accountHint,
    balanceAfterMinor: balanceAfterMinor ?? this.balanceAfterMinor,
    dateOnly: dateOnly ?? this.dateOnly,
    selected: selected ?? this.selected,
    legacyProviderId: legacyProviderId ?? this.legacyProviderId,
    possibleDuplicateReason:
        possibleDuplicateReason ?? this.possibleDuplicateReason,
  );
}

class BankScreenshotParseResult {
  const BankScreenshotParseResult({
    required this.candidates,
    required this.warnings,
  });

  final List<BankScreenshotCandidate> candidates;
  final List<String> warnings;
}
