import '../../transaction_import/services/transaction_category_resolver.dart';
import '../domain/bank_screenshot_models.dart';
import 'bank_screenshot_parser.dart';

class GenericBankScreenshotParser implements BankScreenshotParser {
  const GenericBankScreenshotParser({
    this.categoryResolver = const TransactionCategoryResolver(),
  });

  final TransactionCategoryResolver categoryResolver;

  @override
  String get parserId => 'generic-bank-history-v1';

  @override
  double confidenceFor(ExtractedBankScreenshot document) {
    final financialLines = document.lines.where(
      (line) => _money.hasMatch(line.text) && !_isBalance(line.text),
    );
    return (financialLines.length * 0.18).clamp(0, 0.72).toDouble();
  }

  @override
  BankScreenshotParseResult parse(ExtractedBankScreenshot document) {
    final lines = document.lines.toList(growable: false)
      ..sort((a, b) {
        final top = (a.top ?? 0).compareTo(b.top ?? 0);
        return top == 0 ? (a.left ?? 0).compareTo(b.left ?? 0) : top;
      });
    var activeDate = DateTime(
      document.capturedAt.year,
      document.capturedAt.month,
      document.capturedAt.day,
    );
    final candidates = <BankScreenshotCandidate>[];
    final occurrences = <String, int>{};
    for (var index = 0; index < lines.length; index++) {
      activeDate =
          _dateHeading(lines[index].text, document.capturedAt) ?? activeDate;
      final line = lines[index];
      if (_isBalance(line.text) || _isBonus(line.text)) continue;
      final match = _money.firstMatch(line.text);
      if (match == null) continue;
      final amount = _minor(match);
      if (amount <= 0) continue;
      final context = [
        if (index > 0) lines[index - 1].text,
        line.text,
        if (index + 1 < lines.length) lines[index + 1].text,
      ].join(' ');
      final kind = _kind(context, match.group(1) ?? '');
      final merchant = _merchant(lines, index, match);
      if (merchant == null) continue;
      final occurredAt = _withTime(activeDate, context) ?? activeDate;
      final category = categoryResolver.resolve(merchant);
      final fingerprint = _fingerprint(
        '${occurredAt.toIso8601String()}|${kind.name}|$amount|'
        '${_normalize(merchant)}',
      );
      final occurrence = occurrences.update(
        fingerprint,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      candidates.add(
        BankScreenshotCandidate(
          id: occurrence == 1
              ? 'bank-shot-$fingerprint'
              : 'bank-shot-$fingerprint-row-$occurrence',
          imageHash: document.imageHash,
          parserId: parserId,
          merchant: merchant,
          amountMinor: amount,
          currency: _currency(match.group(4) ?? ''),
          date: occurredAt,
          kind: kind,
          categoryId: category.categoryId,
          confidence: (0.72 * category.confidence.clamp(0.75, 1)).toDouble(),
          dateOnly: occurredAt.hour == 0 && occurredAt.minute == 0,
          selected: true,
        ),
      );
    }
    return BankScreenshotParseResult(
      candidates: candidates,
      warnings: [
        if (candidates.isEmpty) 'Формат банка не узнан уверенно',
        if (occurrences.values.any((count) => count > 1))
          'На скриншоте есть одинаковые строки операций. Они сохранены отдельно; проверьте их перед импортом.',
      ],
    );
  }

  String? _merchant(
    List<BankScreenshotTextLine> lines,
    int index,
    RegExpMatch amount,
  ) {
    final inline = lines[index].text
        .replaceRange(amount.start, amount.end, ' ')
        .replaceAll(RegExp(r'[+−–—\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (_validMerchant(inline)) return inline;
    for (final offset in const [-1, 1, -2]) {
      final target = index + offset;
      if (target < 0 || target >= lines.length) continue;
      final candidate = lines[target].text.trim();
      if (_validMerchant(candidate) && !_dateLike(candidate)) return candidate;
    }
    return null;
  }

  BankScreenshotTransactionKind _kind(String context, String sign) {
    final value = _normalize(context);
    if (value.contains('возврат') || value.contains('refund')) {
      return BankScreenshotTransactionKind.refund;
    }
    if (value.contains('перевод') || value.contains('сбп')) {
      return value.contains('перевод от')
          ? BankScreenshotTransactionKind.income
          : BankScreenshotTransactionKind.transfer;
    }
    if (value.contains('зачислен') ||
        value.contains('пополнен') ||
        sign.contains('+')) {
      return BankScreenshotTransactionKind.income;
    }
    return BankScreenshotTransactionKind.expense;
  }

  DateTime? _withTime(DateTime date, String value) {
    final match = RegExp(
      r'(?:^|\s)([01]?\d|2[0-3]):([0-5]\d)(?:\s|$)',
    ).firstMatch(value);
    return match == null
        ? null
        : DateTime(
            date.year,
            date.month,
            date.day,
            int.parse(match.group(1)!),
            int.parse(match.group(2)!),
          );
  }

  DateTime? _dateHeading(String value, DateTime capturedAt) {
    final text = _normalize(value);
    final day = DateTime(capturedAt.year, capturedAt.month, capturedAt.day);
    if (text == 'сегодня') return day;
    if (text == 'вчера') return day.subtract(const Duration(days: 1));
    final match = RegExp(r'^(\d{1,2})\s+([a-zа-я]+)').firstMatch(text);
    if (match == null) return null;
    const months = <String, int>{
      'января': 1,
      'февраля': 2,
      'марта': 3,
      'апреля': 4,
      'мая': 5,
      'июня': 6,
      'июля': 7,
      'августа': 8,
      'сентября': 9,
      'октября': 10,
      'ноября': 11,
      'декабря': 12,
    };
    final month = months[match.group(2)];
    if (month == null) return null;
    var year = capturedAt.year;
    if (month > capturedAt.month + 1) year--;
    return DateTime(year, month, int.parse(match.group(1)!));
  }

  int _minor(RegExpMatch match) {
    final whole = int.parse(match.group(2)!.replaceAll(RegExp(r'\D'), ''));
    final fraction = (match.group(3) ?? '').padRight(2, '0');
    return whole * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
  }

  String _currency(String value) {
    final text = value.toLowerCase();
    if (text.contains(r'$') || text.contains('usd')) return 'USD';
    if (text.contains('€') || text.contains('eur')) return 'EUR';
    return 'RUB';
  }

  bool _validMerchant(String value) {
    final text = _normalize(value);
    return text.length >= 2 &&
        RegExp(r'[a-zа-я]').hasMatch(text) &&
        !_isBalance(text) &&
        !text.contains('поиск') &&
        !text.contains('период');
  }

  bool _dateLike(String value) =>
      _normalize(value) == 'сегодня' || _normalize(value) == 'вчера';
  bool _isBalance(String value) {
    final text = _normalize(value);
    return text.contains('баланс') ||
        text.contains('остаток') ||
        text.contains('доступно') ||
        text.contains('платежный счет') ||
        text.contains('платежный счет');
  }

  bool _isBonus(String value) {
    final text = _normalize(value);
    return text.contains('спасибо') || text.contains('бонус');
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _fingerprint(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static final _money = RegExp(
    r'([+−–—\-]?\s*)(\d[\d\s\u00a0\u202f]*)(?:[,.](\d{1,2}))?\s*'
    r'(₽|р(?:уб)?\.?|rub|\$|usd|€|eur)',
    caseSensitive: false,
  );
}
