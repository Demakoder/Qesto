import '../../../data/models/qesto_models.dart';

enum VoiceTransactionKind { expense, income, transfer }

class VoiceRecognitionResult {
  const VoiceRecognitionResult({required this.text, required this.onDevice});

  final String text;
  final bool onDevice;
}

class VoiceTransactionDraft {
  const VoiceTransactionDraft({
    required this.rawText,
    required this.kind,
    required this.amount,
    required this.title,
    this.categoryId,
    this.sourceAccountId,
    this.destinationAccountId,
  });

  final String rawText;
  final VoiceTransactionKind kind;
  final int amount;
  final String title;
  final String? categoryId;
  final String? sourceAccountId;
  final String? destinationAccountId;

  TransactionType get transactionType => switch (kind) {
    VoiceTransactionKind.expense => TransactionType.expense,
    VoiceTransactionKind.income => TransactionType.income,
    VoiceTransactionKind.transfer => TransactionType.transfer,
  };
}

class VoiceTransactionParseException implements Exception {
  const VoiceTransactionParseException(this.message);

  final String message;

  @override
  String toString() => message;
}
