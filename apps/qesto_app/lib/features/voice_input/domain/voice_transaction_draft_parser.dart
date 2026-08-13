class ParsedVoiceTransactionDraft {
  const ParsedVoiceTransactionDraft({
    required this.transcript,
    this.amountRubles,
    this.merchant,
    this.categoryId,
  });

  final String transcript;
  final int? amountRubles;
  final String? merchant;
  final String? categoryId;
}

class VoiceTransactionDraftParser {
  const VoiceTransactionDraftParser();

  ParsedVoiceTransactionDraft parse(String transcript) {
    final normalized = transcript.trim().replaceAll(RegExp(r'\s+'), ' ');
    final amountMatch = RegExp(
      r'(\d[\d ]*(?:[.,]\d{1,2})?)\s*(?:₽|руб(?:л(?:ей|я|ь)?)?)?',
      caseSensitive: false,
    ).firstMatch(normalized);
    final amount = amountMatch == null
        ? null
        : double.tryParse(
            amountMatch.group(1)!.replaceAll(' ', '').replaceAll(',', '.'),
          )?.round();
    final merchant = _merchant(normalized, amountMatch);
    return ParsedVoiceTransactionDraft(
      transcript: normalized,
      amountRubles: amount,
      merchant: merchant,
      categoryId: _category(normalized.toLowerCase()),
    );
  }

  String? _merchant(String value, RegExpMatch? amountMatch) {
    final afterPlace = RegExp(
      r'(?:^|\s)(?:в|у|из)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(value);
    var candidate = afterPlace?.group(1)?.trim();
    if ((candidate == null || candidate.isEmpty) && amountMatch != null) {
      candidate = value
          .substring(0, amountMatch.start)
          .replaceFirst(
            RegExp(
              r'^(?:добавь|запиши|потратил(?:а)?|купил(?:а)?|оплатил(?:а)?)\s+',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
    }
    if (candidate == null || candidate.isEmpty) return null;
    return candidate[0].toUpperCase() + candidate.substring(1);
  }

  String? _category(String value) {
    const rules = <String, List<String>>{
      'cafes': ['кофе', 'кафе', 'ресторан', 'бургер', 'пицц'],
      'groceries': ['продукт', 'супермаркет', 'магазин', 'молоко', 'хлеб'],
      'transport': ['такси', 'метро', 'автобус', 'транспорт'],
      'car': ['бензин', 'азс', 'автомоб'],
      'health': ['аптек', 'врач', 'лекарств'],
      'subscriptions': ['подписк', 'spotify', 'netflix', 'яндекс плюс'],
      'utilities': ['коммунал', 'электрич', 'квартплат'],
      'clothes': ['одежд', 'обув', 'куртк', 'кроссов'],
    };
    for (final entry in rules.entries) {
      if (entry.value.any(value.contains)) return entry.key;
    }
    return null;
  }
}
