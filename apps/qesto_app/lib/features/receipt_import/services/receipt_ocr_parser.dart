import '../data/receipt_scanner_models.dart';
import '../domain/receipt_models.dart';

class ReceiptOcrParser {
  const ReceiptOcrParser();

  ParsedReceiptDocument parse(
    ExtractedReceiptDocument document, {
    int? expectedTotalMinor,
  }) {
    final lines =
        (document.lines.isNotEmpty
                ? document.lines.map((line) => line.text)
                : document.text.split(RegExp(r'[\r\n]+')))
            .map(_cleanLine)
            .where((line) => line.isNotEmpty)
            .toList();

    return ParsedReceiptDocument(
      rawText: document.text,
      merchant: _findMerchant(lines),
      items: _findItems(lines, expectedTotalMinor: expectedTotalMinor),
    );
  }

  String? _findMerchant(List<String> lines) {
    String? best;
    var bestScore = -1;
    for (var index = 0; index < lines.length && index < 12; index++) {
      final line = lines[index];
      final lower = line.toLowerCase();
      if (_isMetadata(line) || _isTotalLine(lower) || _looksLikeAmount(line)) {
        continue;
      }
      final letters = RegExp(r'[A-Za-zА-Яа-яЁё]').allMatches(line).length;
      if (letters < 3) continue;

      var score = 12 - index;
      if (RegExp(r'\b(ооо|ип|ао|пао)\b', caseSensitive: false).hasMatch(line)) {
        score += 16;
      }
      if (lower.contains('магазин') || lower.contains('супермаркет')) {
        score += 7;
      }
      if (line.contains('"') || line.contains('«')) score += 4;
      final uppercase = RegExp(r'[A-ZА-ЯЁ]').allMatches(line).length;
      if (uppercase >= letters * 0.7) score += 3;
      if (score > bestScore) {
        bestScore = score;
        best = line;
      }
    }
    return best == null ? null : _cleanMerchant(best);
  }

  List<ParsedReceiptItem> _findItems(
    List<String> lines, {
    int? expectedTotalMinor,
  }) {
    final markerIndex = lines.indexWhere(
      (line) => RegExp(
        r'(кассовый\s+чек|товарн(?:ый|ого)\s+чек|приход)',
        caseSensitive: false,
      ).hasMatch(line),
    );
    final items = <ParsedReceiptItem>[];
    String? pendingName;

    for (
      var index = markerIndex < 0 ? 0 : markerIndex + 1;
      index < lines.length;
      index++
    ) {
      var line = lines[index];
      final lower = line.toLowerCase();
      if (_isTotalLine(lower)) break;
      if (_isMetadata(line)) continue;

      line = line.replaceFirst(RegExp(r'^\s*\d{1,3}[.)]\s*'), '').trim();
      if (line.isEmpty) continue;

      final formula = _formulaPattern.firstMatch(line);
      if (formula != null) {
        final prefix = line.substring(0, formula.start).trim();
        final name = _validItemName(prefix) ? prefix : pendingName;
        if (name == null) continue;
        final quantity = _parseDecimal(formula.group(1)!);
        final unitPrice = _parseMinor(formula.group(2)!);
        final explicitTotal = formula.group(3);
        final total = explicitTotal == null
            ? (quantity * unitPrice).round()
            : _parseMinor(explicitTotal);
        _addItem(
          items,
          ParsedReceiptItem(
            name: _cleanItemName(name),
            quantity: quantity,
            unitPriceMinor: unitPrice,
            totalMinor: total,
          ),
          expectedTotalMinor,
        );
        pendingName = null;
        continue;
      }

      final amount = _amountAtEnd.firstMatch(line);
      if (amount != null) {
        final prefix = line.substring(0, amount.start).trim();
        final name = _validItemName(prefix) ? prefix : pendingName;
        if (name != null) {
          _addItem(
            items,
            ParsedReceiptItem(
              name: _cleanItemName(name),
              totalMinor: _parseMinor(amount.group(1)!),
            ),
            expectedTotalMinor,
          );
        }
        pendingName = null;
        continue;
      }

      if (_validItemName(line)) pendingName = line;
    }
    return items;
  }

  void _addItem(
    List<ParsedReceiptItem> items,
    ParsedReceiptItem item,
    int? expectedTotalMinor,
  ) {
    if (item.totalMinor <= 0) return;
    if (expectedTotalMinor != null &&
        item.totalMinor > expectedTotalMinor * 2) {
      return;
    }
    if (items.isNotEmpty) {
      final previous = items.last;
      if (_normalize(previous.name) == _normalize(item.name) &&
          previous.totalMinor == item.totalMinor) {
        return;
      }
    }
    items.add(item);
  }

  bool _isMetadata(String line) {
    final lower = line.toLowerCase();
    return RegExp(
      r'(кассовый\s+чек|товарн(?:ый|ого)\s+чек|приход|возврат|кассир|'
      r'инн|кпп|сн\s*кассы|смена|чек\s*№|фн|фд|фп|фискальн|'
      r'наличн|безналичн|банковск|карта|ндс|налог|сайт\s+фнс|'
      r'www\.|https?://|адрес|место\s+расчет|телефон|спасибо|'
      r'дата|время|скидка|бонус|наименован|кол-?во|количеств|'
      r'цена|стоимость|полный\s+расчет)',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  bool _isTotalLine(String lower) => RegExp(
    r'^\s*(итог|итого|всего|к\s+оплате|сумма\s+чека)',
    caseSensitive: false,
  ).hasMatch(lower);

  bool _validItemName(String value) {
    if (value.length < 3 || _isMetadata(value)) return false;
    return RegExp(r'[A-Za-zА-Яа-яЁё].*[A-Za-zА-Яа-яЁё]').hasMatch(value);
  }

  bool _looksLikeAmount(String value) =>
      _amountAtEnd.hasMatch(value) && !_validItemName(value);

  static final _formulaPattern = RegExp(
    r'(\d+(?:[.,]\d{1,3})?)\s*[xх×*]\s*(\d+[,.:\-]\d{2})'
    r'(?:\s*(?:=)?\s*(\d+[,.:\-]\d{2}))?'
    r'\s*(?:₽|р(?:уб)?\.?)?\s*[A-ZА-Я]?[.,]?$',
    caseSensitive: false,
  );

  static final _amountAtEnd = RegExp(
    r'(\d{1,7}[,.:\-]\d{2})\s*(?:₽|р(?:уб)?\.?)?'
    r'\s*[A-ZА-Я]?[.,]?$',
    caseSensitive: false,
  );
}

String _cleanLine(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').replaceAll('—', '-').trim();

String _cleanMerchant(String value) => value
    .replaceFirst(RegExp(r'^(ооо|ип|ао|пао)\s+', caseSensitive: false), '')
    .replaceAll(RegExp(r'^[«"]|[»"]$'), '')
    .trim();

String _cleanItemName(String value) => value
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'[._]{3,}'), ' ')
    .replaceAll(RegExp(r'[-=:]+$'), '')
    .trim();

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
    .trim();

double _parseDecimal(String value) =>
    double.parse(value.replaceAll(RegExp(r'[,:\-]'), '.'));

int _parseMinor(String value) => (_parseDecimal(value) * 100).round();
