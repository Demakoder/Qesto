import '../domain/bank_screenshot_models.dart';
import '../../transaction_import/services/transaction_category_resolver.dart';
import 'bank_screenshot_parser.dart';

class SberBankScreenshotParser implements BankScreenshotParser {
  const SberBankScreenshotParser({
    this.categoryResolver = const TransactionCategoryResolver(),
  });

  static const id = 'sber-mobile-history-v1';
  @override
  String get parserId => id;
  final TransactionCategoryResolver categoryResolver;

  @override
  double confidenceFor(ExtractedBankScreenshot document) {
    final text = document.lines.map((line) => _normalize(line.text)).join('\n');
    var score = 0.0;
    if (text.contains('платежный счет') || text.contains('платежный счет')) {
      score += 0.55;
    }
    if (text.contains('оплата товаров и услуг')) score += 0.25;
    if (text.contains('перевод по запросу сбп')) score += 0.15;
    if (text.contains('ваши привилегии')) score += 0.05;
    return score.clamp(0, 1).toDouble();
  }

  @override
  BankScreenshotParseResult parse(ExtractedBankScreenshot document) {
    final lines = document.lines.toList(growable: false)
      ..sort((a, b) {
        final byTop = (a.top ?? 0).compareTo(b.top ?? 0);
        return byTop != 0 ? byTop : (a.left ?? 0).compareTo(b.left ?? 0);
      });
    final groups = <_Group>[];
    var activeDate = DateTime(
      document.capturedAt.year,
      document.capturedAt.month,
      document.capturedAt.day,
    );
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      activeDate = _dateHeading(line.text, document.capturedAt) ?? activeDate;
      final kind = _kind(line.text);
      if (kind == null) continue;
      final start = index > 2 ? index - 2 : 0;
      final end = (index + 3).clamp(0, lines.length - 1);
      final nearby = lines.sublist(start, end + 1);
      final merchant = _merchant(lines, index);
      final directAmount = _directAmount(nearby, line);
      final balance = _balance(nearby);
      final accountHint = _accountHint(nearby);
      groups.add(
        _Group(
          merchant: merchant,
          kind: kind,
          date: activeDate,
          amountMinor: directAmount,
          balanceMinor: balance,
          accountHint: accountHint,
        ),
      );
    }

    final candidates = <BankScreenshotCandidate>[];
    final occurrences = <String, int>{};
    for (var index = 0; index < groups.length; index++) {
      final group = groups[index];
      var amount = group.amountMinor;
      var inferred = false;
      if (amount == null &&
          group.balanceMinor != null &&
          index + 1 < groups.length &&
          groups[index + 1].balanceMinor != null) {
        final delta = group.balanceMinor! - groups[index + 1].balanceMinor!;
        if (delta != 0 && delta.abs() < 100000000000) {
          amount = delta.abs();
          inferred = true;
        }
      }
      if (amount == null || amount <= 0 || !_validMerchant(group.merchant)) {
        continue;
      }
      final merchant = _cleanMerchant(group.merchant);
      final category = categoryResolver.resolve(merchant);
      final fingerprint = _fingerprint(
        '${group.date.toIso8601String()}|${group.kind.name}|$amount|'
        '${_normalize(merchant)}|${group.balanceMinor ?? ''}|'
        '${group.accountHint ?? ''}',
      );
      // Equal amount/merchant/day is not proof that two visible rows are the
      // same purchase. Keep the first legacy ID and distinguish occurrences.
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
          parserId: id,
          merchant: merchant,
          amountMinor: amount,
          currency: 'RUB',
          date: group.date,
          kind: group.kind,
          categoryId: category.categoryId,
          accountHint: group.accountHint,
          balanceAfterMinor: group.balanceMinor,
          confidence:
              (inferred ? 0.82 : 0.92) * category.confidence.clamp(0.7, 1),
          selected: inferred || group.amountMinor != null,
        ),
      );
    }
    return BankScreenshotParseResult(
      candidates: candidates,
      warnings: [
        if (occurrences.values.any((count) => count > 1))
          'На скриншоте есть одинаковые строки операций. Они сохранены отдельно; проверьте их перед импортом.',
        if (groups.isNotEmpty && candidates.isEmpty)
          'Операции найдены, но суммы не удалось прочитать',
      ],
    );
  }

  BankScreenshotTransactionKind? _kind(String value) {
    final text = _normalize(value);
    if (text.contains('возврат') || text.contains('отмена операц')) {
      return BankScreenshotTransactionKind.refund;
    }
    if (text.contains('перевод от') ||
        text.contains('зачислен') ||
        text.contains('поступлен')) {
      return BankScreenshotTransactionKind.income;
    }
    if (text.contains('перевод') || text.contains('сбп')) {
      return BankScreenshotTransactionKind.transfer;
    }
    if (text.contains('оплата товаров') ||
        text.contains('покупка') ||
        text.contains('списание') ||
        text.contains('снятие')) {
      return BankScreenshotTransactionKind.expense;
    }
    return null;
  }

  String _merchant(List<BankScreenshotTextLine> lines, int operationIndex) {
    final values = <String>[];
    for (
      var index = operationIndex - 1;
      index >= 0 && values.length < 2;
      index--
    ) {
      final value = lines[index].text.trim();
      if (_kind(value) != null || _isBalance(value) || _isUi(value)) break;
      if (_money.hasMatch(value) &&
          !_letters.hasMatch(value.replaceAll(_money, ''))) {
        continue;
      }
      if (_validMerchant(value)) values.insert(0, value);
    }
    return values.join(' ').trim();
  }

  int? _directAmount(
    List<BankScreenshotTextLine> nearby,
    BankScreenshotTextLine operationLine,
  ) {
    final candidates = nearby
        .where((line) {
          if (_isBalance(line.text) || _isBonus(line.text)) return false;
          final top = line.top;
          final opTop = operationLine.top;
          return top == null || opTop == null || (top - opTop).abs() < 70;
        })
        .toList(growable: false);
    for (final line in candidates) {
      final match = _money.firstMatch(line.text);
      if (match == null) continue;
      return _minor(match);
    }
    return null;
  }

  int? _balance(List<BankScreenshotTextLine> lines) {
    for (final line in lines) {
      if (!_isBalance(line.text)) continue;
      final match = _looseMoney.firstMatch(line.text);
      if (match != null) return _minor(match);
    }
    return null;
  }

  String? _accountHint(List<BankScreenshotTextLine> lines) {
    for (final line in lines) {
      final suffix = RegExp(
        r'[*•·]{1,4}\s*(\d{4})(?!\d)',
      ).firstMatch(line.text);
      if (suffix != null) return '*${suffix.group(1)}';
    }
    return null;
  }

  int _minor(RegExpMatch match) {
    final whole = int.parse(match.group(1)!.replaceAll(RegExp(r'[^0-9]'), ''));
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return whole * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
  }

  DateTime? _dateHeading(String value, DateTime capturedAt) {
    final text = _normalize(value);
    final day = DateTime(capturedAt.year, capturedAt.month, capturedAt.day);
    if (text == 'сегодня') return day;
    if (text == 'вчера') return day.subtract(const Duration(days: 1));
    final match = RegExp(r'^(\d{1,2})\s+([a-zа-я]+)').firstMatch(text);
    if (match == null) return null;
    final months = <String, int>{
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

  bool _isBalance(String value) {
    final text = _normalize(value);
    return text.contains('платежный счет') ||
        text.contains('платежный счет') ||
        text.startsWith('баланс') ||
        text.startsWith('остаток');
  }

  bool _isBonus(String value) {
    final text = _normalize(value);
    return text.contains('спасибо') ||
        RegExp(r'^\+?\d+(?:[,.]\d+)?\s*[сc]$').hasMatch(text);
  }

  bool _isUi(String value) {
    final text = _normalize(value);
    return text == 'период' ||
        text.startsWith('что показывать') ||
        text.startsWith('ваши привилегии') ||
        text.startsWith('перейти в раздел');
  }

  bool _validMerchant(String value) =>
      value.trim().length >= 2 &&
      !_isUi(value) &&
      !_isBalance(value) &&
      _letters.hasMatch(value);

  String _cleanMerchant(String value) => value
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[•·\-]+|[•·\-]+$'), '')
      .trim();

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

  static final _letters = RegExp(r'[a-zа-я]', caseSensitive: false);
  static final _money = RegExp(
    r'(\d[\d\s\u00a0\u202f]*)(?:[,.](\d{1,2}))?\s*(?:₽|р(?:уб)?\.?)',
    caseSensitive: false,
  );
  static final _looseMoney = RegExp(
    r'(\d[\d\s\u00a0\u202f]*)(?:[,.](\d{1,2}))?',
  );
}

class _Group {
  const _Group({
    required this.merchant,
    required this.kind,
    required this.date,
    required this.amountMinor,
    required this.balanceMinor,
    required this.accountHint,
  });
  final String merchant;
  final BankScreenshotTransactionKind kind;
  final DateTime date;
  final int? amountMinor;
  final int? balanceMinor;
  final String? accountHint;
}
