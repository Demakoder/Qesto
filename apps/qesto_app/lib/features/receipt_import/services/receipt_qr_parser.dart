import '../domain/receipt_models.dart';

class ReceiptQrParser {
  const ReceiptQrParser();

  ParsedFiscalReceipt parse(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) {
      throw const FormatException('QR-код чека пуст');
    }

    final query = _queryPart(raw);
    late final Map<String, String> parameters;
    try {
      parameters = Uri.splitQueryString(
        query,
      ).map((key, value) => MapEntry(key.toLowerCase(), value.trim()));
    } on FormatException {
      throw const FormatException('QR-код имеет неизвестный формат');
    }

    final purchasedAt = _parseDate(_required(parameters, 't'));
    final amountMinor = _parseAmount(_required(parameters, 's'));
    final fiscalDriveNumber = _digits(_required(parameters, 'fn'), 'ФН');
    final fiscalDocumentNumber = _digits(_required(parameters, 'i'), 'ФД');
    final fiscalSign = _digits(_required(parameters, 'fp'), 'ФП');
    final kind = switch (_required(parameters, 'n')) {
      '1' => FiscalReceiptKind.expense,
      '2' => FiscalReceiptKind.refund,
      _ => throw const FormatException(
        'Поддерживаются только чеки покупки и возврата',
      ),
    };

    return ParsedFiscalReceipt(
      purchasedAt: purchasedAt,
      amountMinor: amountMinor,
      fiscalDriveNumber: fiscalDriveNumber,
      fiscalDocumentNumber: fiscalDocumentNumber,
      fiscalSign: fiscalSign,
      kind: kind,
      rawQr: raw,
    );
  }

  String _queryPart(String raw) {
    final questionMark = raw.indexOf('?');
    return questionMark < 0 ? raw : raw.substring(questionMark + 1);
  }

  String _required(Map<String, String> parameters, String key) {
    final value = parameters[key];
    if (value == null || value.isEmpty) {
      throw const FormatException('Это не фискальный QR-код кассового чека');
    }
    return value;
  }

  DateTime _parseDate(String value) {
    final match = RegExp(
      r'^(\d{4})(\d{2})(\d{2})[Tt](\d{2})(\d{2})(\d{2})?',
    ).firstMatch(value);
    if (match == null) {
      throw const FormatException('В QR-коде указана некорректная дата');
    }
    try {
      final year = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final day = int.parse(match.group(3)!);
      final hour = int.parse(match.group(4)!);
      final minute = int.parse(match.group(5)!);
      final second = int.tryParse(match.group(6) ?? '') ?? 0;
      final date = DateTime(year, month, day, hour, minute, second);
      if (date.year != year ||
          date.month != month ||
          date.day != day ||
          date.hour != hour ||
          date.minute != minute ||
          date.second != second) {
        throw const FormatException(
          'В QR-коде указана некорректная дата',
        );
      }
      return date;
    } on Object {
      throw const FormatException('В QR-коде указана некорректная дата');
    }
  }

  int _parseAmount(String value) {
    final normalized = value.replaceAll(',', '.');
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);
    if (match == null) {
      throw const FormatException('В QR-коде указана некорректная сумма');
    }
    final rubles = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return rubles * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
  }

  String _digits(String value, String fieldName) {
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      throw FormatException('В QR-коде некорректное поле $fieldName');
    }
    return value;
  }
}
