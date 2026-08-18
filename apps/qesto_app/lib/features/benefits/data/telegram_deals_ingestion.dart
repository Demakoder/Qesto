import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'bounded_http_response.dart';

const telegramDealChannels = <String>[
  'skidki',
  'kuponych',
  'mm_promokods',
  'pepperru',
  'aktsiya_telegram',
];
const _maximumTelegramPageBytes = 2 * 1024 * 1024;
const _maximumTelegramMessageChars = 12_000;

class TelegramDealsIngestion {
  TelegramDealsIngestion({
    http.Client? client,
    this.maximumPageBytes = _maximumTelegramPageBytes,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final int maximumPageBytes;

  Future<String> fetchOffersJson() async {
    final pages = <String, String>{};
    await Future.wait(
      telegramDealChannels.map((channel) async {
        try {
          final request = http.Request('GET', Uri.https('t.me', '/s/$channel'))
            ..headers['User-Agent'] =
                'Mozilla/5.0 (Linux; Android 14) '
                'AppleWebKit/537.36 QestoDeals/2.0';
          final response = await _client
              .send(request)
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200) {
            final body = await readBoundedHttpBody(
              response,
              maximumBytes: maximumPageBytes,
              timeout: const Duration(seconds: 10),
            );
            if (body.isNotEmpty) pages[channel] = body;
          } else {
            await response.stream.listen((_) {}).cancel();
          }
        } on Object {
          // One unavailable channel must not hide results from the others.
        }
      }),
    );
    if (pages.isEmpty) {
      throw StateError(
        'Telegram is unavailable. Check that the phone VPN includes Qesto.',
      );
    }
    return buildOffersJson(pages);
  }

  String buildOffersJson(Map<String, String> channelPages) {
    final offers = <Map<String, dynamic>>[];
    for (final entry in channelPages.entries) {
      for (final message in _parsePage(entry.key, entry.value)) {
        if (!_isAllowed(message)) continue;
        offers.addAll(_extractOffers(message));
      }
    }

    offers.sort((left, right) {
      final confidence = (right['confidence'] as int).compareTo(
        left['confidence'] as int,
      );
      if (confidence != 0) return confidence;
      return (right['updated_at'] as String).compareTo(
        left['updated_at'] as String,
      );
    });

    final unique = <String, Map<String, dynamic>>{};
    for (final offer in offers) {
      if ((offer['confidence'] as int) < 50) continue;
      final promoCode = offer['promo_code'] as String?;
      final key = promoCode == null
          ? 'source:${offer['id']}'
          : 'promo:${_normalized(promoCode)}';
      unique.putIfAbsent(key, () => offer);
    }
    final values = unique.values.take(300).toList(growable: false);
    return jsonEncode({
      'offers': values,
      'count': values.length,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  List<_TelegramMessage> _parsePage(String channel, String source) {
    final document = html_parser.parse(source);
    final result = <_TelegramMessage>[];
    for (final card in document.querySelectorAll('[data-post]')) {
      final dataPost = card.attributes['data-post'] ?? '';
      final slash = dataPost.lastIndexOf('/');
      if (slash <= 0) continue;
      final sourceId = dataPost.substring(0, slash).replaceFirst('@', '');
      final messageId = dataPost.substring(slash + 1);
      if (sourceId.toLowerCase() != channel.toLowerCase() ||
          messageId.length > 20 ||
          int.tryParse(messageId) == null) {
        continue;
      }
      final textNode =
          card.querySelector('.tgme_widget_message_text') ??
          card.querySelector('.js-message_text');
      if (textNode == null) continue;
      final text = _truncate(
        _normalizeText(_renderText(textNode)),
        _maximumTelegramMessageChars,
      );
      if (text.isEmpty) continue;
      final timeValue = card
          .querySelector('time[datetime]')
          ?.attributes['datetime'];
      final publishedAt =
          DateTime.tryParse(timeValue ?? '')?.toUtc() ?? DateTime.now().toUtc();
      final links = card
          .querySelectorAll('a[href]')
          .map((element) => element.attributes['href'])
          .whereType<String>()
          .map((value) => _truncate(value, 2048))
          .toSet()
          .take(50)
          .toList(growable: false);
      final formattedCodes = textNode
          .querySelectorAll('code')
          .map((element) => element.text.trim())
          .where((value) => value.isNotEmpty)
          .map((value) => _truncate(value, 256))
          .toSet()
          .take(50)
          .toList(growable: false);
      result.add(
        _TelegramMessage(
          channel: sourceId,
          messageId: messageId,
          publishedAt: publishedAt,
          text: text,
          links: links,
          formattedCodes: formattedCodes,
        ),
      );
    }
    return result;
  }

  bool _isAllowed(_TelegramMessage message) {
    final text = _normalized(message.text);
    if (_blockedKeywords.any(text.contains)) return false;
    if (message.formattedCodes.isNotEmpty) return true;
    return _offerKeywords.any(text.contains);
  }

  List<Map<String, dynamic>> _extractOffers(_TelegramMessage message) {
    final codes = _promoCodes(message);
    if (codes.isEmpty && _offerType(message.text, false) == 'unknown') {
      return const [];
    }
    final values = codes.isEmpty ? <String?>[null] : codes;
    return [
      for (var index = 0; index < values.length; index++)
        _buildOffer(message, values[index], index),
    ];
  }

  Map<String, dynamic> _buildOffer(
    _TelegramMessage message,
    String? promoCode,
    int index,
  ) {
    final context = promoCode == null
        ? message.text
        : _codeContext(message.text, promoCode);
    final displayText = _cleanDisplayText(context);
    final merchant = _merchant(displayText);
    final discount = _discount(context);
    final minimumOrder = _amount(_minimumPattern, context);
    final maximumDiscount = _amount(_maximumPattern, context);
    final customerType = _customerType(context);
    final validUntil = _validUntil(context, message.publishedAt);
    final targetUrl = _targetUrl(message.links);
    final type = _offerType(context, promoCode != null);
    final confidence = _confidence(
      hasCode: promoCode != null,
      hasMerchant: merchant != null,
      type: type,
      discountValue: discount.$2,
      minimumOrder: minimumOrder,
      validUntil: validUntil,
      targetUrl: targetUrl,
    );
    final dedupe = promoCode == null
        ? 'source:telegram:${message.channel}:${message.messageId}:$index'
        : 'promo:${_normalized(promoCode)}';
    final now = DateTime.now().toUtc().toIso8601String();
    return {
      'id': _stableId(dedupe),
      'type': type,
      'merchant_id': merchant?.$1,
      'merchant_name': merchant?.$2,
      'title': _title(
        displayText,
        merchant?.$2,
        type,
        discount.$1,
        discount.$2,
        customerType,
      ),
      'display_text': displayText,
      'promo_code': promoCode,
      'discount_type': discount.$1,
      'discount_value': discount.$2,
      'currency': discount.$1 == 'fixed' ? 'RUB' : null,
      'minimum_order': minimumOrder,
      'maximum_discount': maximumDiscount,
      'customer_type': customerType,
      'valid_until': validUntil,
      'target_url': targetUrl,
      'original_text': message.text,
      'source': {
        'type': 'telegram',
        'channel': message.channel,
        'message_id': message.messageId,
        'url': 'https://t.me/${message.channel}/${message.messageId}',
      },
      'confidence': confidence,
      'created_at': now,
      'updated_at': message.publishedAt.toIso8601String(),
    };
  }

  List<String> _promoCodes(_TelegramMessage message) {
    final candidates = <({String value, bool formatted})>[
      for (final code in message.formattedCodes) (value: code, formatted: true),
      for (final match in _promoPattern.allMatches(message.text))
        (value: match.group(1) ?? '', formatted: false),
    ];
    final result = <String>[];
    for (final candidate in candidates) {
      final value = candidate.value
          .trim()
          .replaceAll(_promoCodeTrimPattern, ' ')
          .trim()
          .toUpperCase();
      if (_validCode(value, candidate.formatted) && !result.contains(value)) {
        result.add(value);
      }
    }
    return result;
  }

  bool _validCode(String value, bool formatted) {
    final folded = _normalized(value);
    if (!_validPromoCodePattern.hasMatch(value) ||
        _codeStopWords.contains(folded) ||
        _digitsOnlyPattern.hasMatch(value) ||
        folded.startsWith('http') ||
        folded.startsWith('www') ||
        folded.startsWith('erid') ||
        folded.startsWith('инн')) {
      return false;
    }
    if (_dateLikeCodePattern.hasMatch(value)) {
      return false;
    }
    if (_uppercaseOrDigitPattern.hasMatch(value)) return true;
    return formatted && value == value.toUpperCase();
  }

  String _codeContext(String text, String code) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final escaped = RegExp.escape(code);
    final token = RegExp(
      '(^|[^A-Za-zА-Яа-яЁё0-9_-])$escaped([^A-Za-zА-Яа-яЁё0-9_-]|\u0024)',
      caseSensitive: false,
    );
    final indexes = <int>[
      for (var i = 0; i < lines.length; i++)
        if (token.hasMatch(lines[i])) i,
    ];
    if (indexes.isEmpty) return text;
    final selected = <int>{...indexes};
    for (final index in indexes) {
      if (index > 0 && _looksLikeDescription(lines[index - 1])) {
        selected.add(index - 1);
      }
    }
    String? heading;
    for (final line in lines.take(indexes.first).toList().reversed) {
      final normalized = _normalized(line);
      if (line.length <= 180 &&
          _numberedHeadingPattern.hasMatch(line) &&
          [
            'промокод',
            'перв',
            'повтор',
            'магазин',
            'ресторан',
          ].any(normalized.contains)) {
        heading = line;
        break;
      }
    }
    return [
      ?heading,
      for (final i in selected.toList()..sort()) lines[i],
    ].join('\n');
  }

  bool _looksLikeDescription(String line) {
    final value = _normalized(line);
    if (value.contains('промокод') || value.contains('купон')) return false;
    return line.startsWith('➡') ||
        ['скидк', 'бесплат', 'кэшбэк', 'кешбек', '₽', '%'].any(value.contains);
  }

  (String, String)? _merchant(String text) {
    final normalized = _normalized(text);
    for (final merchant in _merchantAliases) {
      for (final alias in merchant.$3) {
        if (normalized.contains(_normalized(alias))) {
          return (merchant.$1, merchant.$2);
        }
      }
    }
    return null;
  }

  (String, int?) _discount(String text) {
    final percent = _percentPattern.firstMatch(text);
    final percentValue = int.tryParse(percent?.group(1) ?? '');
    if (percentValue != null && percentValue > 0 && percentValue <= 100) {
      return ('percent', percentValue);
    }
    final fixed = _fixedPattern.firstMatch(text);
    final fixedValue = _digits(fixed?.group(1));
    if (fixedValue != null) return ('fixed', fixedValue);
    final pair = _pricePairPattern.firstMatch(text);
    final current = _digits(pair?.group(1));
    final previous = _digits(pair?.group(2));
    if (current != null && previous != null && previous > current) {
      return ('fixed', previous - current);
    }
    return ('unknown', null);
  }

  int? _amount(RegExp pattern, String text) =>
      _digits(pattern.firstMatch(text)?.group(1));

  String _customerType(String text) {
    final value = _normalized(text);
    if (_newCustomerMarkers.any(value.contains)) return 'new';
    if (_repeatCustomerMarkers.any(value.contains)) return 'repeat';
    if (value.contains('для всех')) return 'all';
    return 'unknown';
  }

  String _offerType(String text, bool hasCode) {
    if (hasCode) return 'promo_code';
    final value = _normalized(text);
    if (value.contains('кэшбэк') || value.contains('cashback')) {
      return 'cashback';
    }
    if (value.contains('бесплатн') && value.contains('достав')) {
      return 'free_delivery';
    }
    if (value.contains('подарок')) return 'gift';
    if ([
      'скидк',
      'акци',
      'распродаж',
      '₽',
      '%',
      'вместо',
    ].any(value.contains)) {
      return 'deal';
    }
    return 'unknown';
  }

  String? _validUntil(String text, DateTime publishedAt) {
    final value = _normalized(text);
    if (value.contains('только сегодня')) {
      return _dateOnly(publishedAt);
    }
    final numeric = _numericDatePattern.firstMatch(value);
    if (numeric != null) {
      return _safeDate(
        int.parse(numeric.group(1)!),
        int.parse(numeric.group(2)!),
        _fullYear(numeric.group(3), publishedAt.year),
        publishedAt,
      );
    }
    final textual = _textDatePattern.firstMatch(value);
    if (textual != null) {
      return _safeDate(
        int.parse(textual.group(1)!),
        _months[textual.group(2)]!,
        int.tryParse(textual.group(3) ?? '') ?? publishedAt.year,
        publishedAt,
      );
    }
    return null;
  }

  String? _targetUrl(List<String> links) {
    for (final raw in links) {
      final uri = Uri.tryParse(raw.replaceAll('&amp;', '&'));
      if (uri == null || !{'http', 'https'}.contains(uri.scheme)) continue;
      final host = uri.host.toLowerCase().replaceFirst(_wwwPrefixPattern, '');
      if (host.isEmpty ||
          _blockedHosts.any(
            (blocked) => host == blocked || host.endsWith('.$blocked'),
          ) ||
          _mediaPathPattern.hasMatch(uri.path)) {
        continue;
      }
      return uri.toString();
    }
    return null;
  }

  int _confidence({
    required bool hasCode,
    required bool hasMerchant,
    required String type,
    required int? discountValue,
    required int? minimumOrder,
    required String? validUntil,
    required String? targetUrl,
  }) {
    var score = hasCode ? 30 : (hasMerchant ? 35 : 0);
    if (hasCode && hasMerchant) score += 30;
    if (!hasCode && type != 'unknown') score += 20;
    if (discountValue != null) score += hasCode ? 15 : 25;
    if (hasCode && minimumOrder != null) score += 10;
    if (validUntil != null) score += hasCode ? 5 : 10;
    if (targetUrl != null) score += 10;
    return score.clamp(0, 100);
  }

  String _title(
    String displayText,
    String? merchantName,
    String type,
    String discountType,
    int? discountValue,
    String customerType,
  ) {
    final subject =
        merchantName ??
        switch (type) {
          'cashback' => 'Кэшбэк',
          'free_delivery' => 'Бесплатная доставка',
          'gift' => 'Подарок при покупке',
          'promo_code' => 'Промокод',
          _ => 'Акция',
        };
    final discount = discountValue == null
        ? ''
        : discountType == 'percent'
        ? ' — скидка $discountValue%'
        : ' — скидка $discountValue ₽';
    final customer = switch (customerType) {
      'new' => ' на первый заказ',
      'repeat' => ' на повторный заказ',
      'all' => ' для всех',
      _ => '',
    };
    final generated = '$subject$discount$customer'.trim();
    if (generated != 'Акция' && generated != 'Промокод') {
      return _truncate(generated, 140);
    }
    final firstLine = displayText
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => generated);
    return _truncate(firstLine, 140);
  }
}

class _TelegramMessage {
  const _TelegramMessage({
    required this.channel,
    required this.messageId,
    required this.publishedAt,
    required this.text,
    required this.links,
    required this.formattedCodes,
  });

  final String channel;
  final String messageId;
  final DateTime publishedAt;
  final String text;
  final List<String> links;
  final List<String> formattedCodes;
}

String _renderText(Node node) {
  final buffer = StringBuffer();
  void visit(Node current) {
    if (current is Text) {
      buffer.write(current.data);
      return;
    }
    if (current is Element && current.localName == 'br') {
      buffer.write('\n');
      return;
    }
    for (final child in current.nodes) {
      visit(child);
    }
    if (current is Element &&
        const {'div', 'p', 'li'}.contains(current.localName)) {
      buffer.write('\n');
    }
  }

  visit(node);
  return buffer.toString();
}

String _normalizeText(String value) => value
    .replaceAll('\r', '')
    .split('\n')
    .map((line) => line.replaceAll(_whitespacePattern, ' ').trim())
    .where((line) => line.isNotEmpty)
    .join('\n')
    .trim();

String _cleanDisplayText(String value) {
  final lines = _normalizeText(value).split('\n').where((line) {
    final normalized = _normalized(line);
    return !_legalLinePattern.hasMatch(normalized) &&
        ![
          'подписывайтесь',
          'подпишись',
          'наш канал',
          'канал в max',
          'канал в вк',
        ].any(normalized.contains) &&
        !_channelSignaturePattern.hasMatch(line.trim());
  });
  return lines.join('\n').trim();
}

String _normalized(String value) => value.toLowerCase().replaceAll('ё', 'е');

int? _digits(String? value) {
  if (value == null) return null;
  final digits = value.replaceAll(_nonDigitPattern, '');
  return digits.isEmpty ? null : int.tryParse(digits);
}

int _fullYear(String? value, int fallback) {
  final parsed = int.tryParse(value ?? '');
  if (parsed == null) return fallback;
  return parsed < 100 ? 2000 + parsed : parsed;
}

String? _safeDate(int day, int month, int year, DateTime publishedAt) {
  final candidate = DateTime.utc(year, month, day);
  if (candidate.day != day ||
      candidate.month != month ||
      candidate.year != year) {
    return null;
  }
  var result = candidate;
  if (publishedAt.difference(result).inDays > 180) {
    result = DateTime.utc(year + 1, month, day);
  }
  return _dateOnly(result);
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _truncate(String value, int length) {
  if (value.length <= length) return value;
  return String.fromCharCodes(value.runes.take(length));
}

String _stableId(String value) {
  int hash(int seed) {
    var result = seed;
    for (final byte in utf8.encode(value)) {
      result ^= byte;
      result = (result * 16777619) & 0xffffffff;
    }
    return result;
  }

  return '${hash(2166136261).toRadixString(16).padLeft(8, '0')}'
      '${hash(3339675911).toRadixString(16).padLeft(8, '0')}';
}

final _promoCodeTrimPattern = RegExp(
  r'^[\s:—–.,!()\[\]{}"-]+|[\s:—–.,!()\[\]{}"-]+$',
);
final _validPromoCodePattern = RegExp(r'^[A-Za-zА-Яа-яЁё0-9_-]{4,20}$');
final _digitsOnlyPattern = RegExp(r'^\d+$');
final _dateLikeCodePattern = RegExp(r'^\d{1,2}[._-]\d{1,2}(?:[._-]\d{2,4})?$');
final _uppercaseOrDigitPattern = RegExp(r'[0-9A-Z]');
final _numberedHeadingPattern = RegExp(r'^\d+[.)]\s*');
final _wwwPrefixPattern = RegExp(r'^www\.');
final _mediaPathPattern = RegExp(
  r'\.(?:jpe?g|png|gif|webp|svg|mp4)$',
  caseSensitive: false,
);
final _whitespacePattern = RegExp(r'\s+');
final _legalLinePattern = RegExp(r'^(реклама\.?|инн\b|erid\b|рид\b)');
final _channelSignaturePattern = RegExp(r'^@[-_a-zA-Z0-9]{4,}$');
final _nonDigitPattern = RegExp(r'\D');

final _promoPattern = RegExp(
  r'(?:промокод(?:ом|у)?|промо(?:код)?|код|купон)\s*(?::|—|-|–)?\s*([A-Za-zА-Яа-яЁё0-9_-]{4,20})',
  caseSensitive: false,
);
final _percentPattern = RegExp(
  r'(?:скидк[^\s]*\s*)?[−–-]?\s*(\d{1,3})\s*%',
  caseSensitive: false,
);
final _fixedPattern = RegExp(
  r'(?:скидк[^\s]*|минус)\s*(?:до\s*)?(\d[\d\s]{0,8})\s*(?:₽|руб(?:лей|ля|ль)?\.?)',
  caseSensitive: false,
);
final _pricePairPattern = RegExp(
  r'(?:за|теперь)\s*(\d[\d\s]{0,8})\s*₽?\s*(?:вместо|было)\s*(\d[\d\s]{0,8})\s*₽?',
  caseSensitive: false,
);
final _minimumPattern = RegExp(
  r'(?:при\s+заказе\s+от|на\s+заказ\s+от|от\s+сумм[ыа]|покупк[^\s]*\s+от|заказ[^\s]*\s+от|\bот)\s*(\d[\d\s]{0,8})\s*(?:₽|руб(?:лей|ля|ль)?\.?)?',
  caseSensitive: false,
);
final _maximumPattern = RegExp(
  r'(?:максим(?:ум|альная\s+скидка)|макс\.?|не\s+более)\s*(\d[\d\s]{0,8})\s*(?:₽|руб(?:лей|ля|ль)?\.?)?',
  caseSensitive: false,
);
final _numericDatePattern = RegExp(
  r'(?:до|по|только)\s+(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?',
  caseSensitive: false,
);
final _textDatePattern = RegExp(
  r'(?:до|по|только)\s+(\d{1,2})\s+(января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря)(?:\s+(\d{4}))?',
  caseSensitive: false,
);

const _blockedKeywords = <String>[
  'алкоголь',
  'алкогольный',
  'пиво',
  'вино',
  'водка',
  'виски',
  'коньяк',
  'шампанское',
  'табак',
  'сигареты',
  'вейп',
  'казино',
  'ставки на спорт',
  'букмекер',
  'микрозайм',
  'займ до зарплаты',
  'кредитн',
  'дебетов',
  'обслуживание карт',
  'оформить кредит',
  'ипотек',
  'оружие',
  'наркотик',
  '18+ контент',
];
const _offerKeywords = <String>[
  'промокод',
  'промо',
  'скидка',
  'скидки',
  'купон',
  'акция',
  'распродажа',
  'кэшбэк',
  'cashback',
  'бесплатная доставка',
  'подарок',
  '₽',
  '%',
];
const _blockedHosts = <String>[
  't.me',
  'telegram.me',
  'vk.com',
  'vk.ru',
  'max.ru',
  'prf.su',
  'prfl.me',
  'clck.ru',
  'vk.cc',
  'ya.cc',
  'bit.ly',
  'tinyurl.com',
];
const _codeStopWords = <String>{
  'промокод',
  'скидка',
  'купон',
  'акция',
  'можно',
  'действует',
  'используйте',
  'примените',
  'заказ',
  'первый',
  'повторный',
  'сегодня',
  'erid',
  'инн',
  'коды',
  'кодов',
  'коду',
  'кода',
  'кодам',
  'кодами',
  'активируем',
  'показываем',
  'суммируется',
};
const _newCustomerMarkers = <String>[
  'первый заказ',
  'первые заказы',
  'на первый',
  'для новых',
  'новым пользовател',
  'новые пользовател',
  'первая покупк',
];
const _repeatCustomerMarkers = <String>[
  'повторный заказ',
  'повторные заказ',
  'повторные покупк',
  'старых пользовател',
];
const _months = <String, int>{
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

const _merchantAliases = <(String, String, List<String>)>[
  ('magnit_cosmetic', 'Магнит Косметик', ['Магнит Косметик']),
  ('magnit_delivery', 'Магнит Доставка', ['Магнит Доставка']),
  (
    'yandex_market',
    'Яндекс Маркет',
    ['Яндекс Маркет', 'Яндекс.Маркет', 'Yandex Market'],
  ),
  ('yandex_food', 'Яндекс Еда', ['Яндекс Еда', 'Яндекс.Еда', 'Yandex Eda']),
  ('yandex_lavka', 'Яндекс Лавка', ['Яндекс Лавка', 'Яндекс.Лавка']),
  ('wildberries', 'Wildberries', ['Wildberries', 'Вайлдберриз', 'WB']),
  ('ozon', 'Ozon', ['Ozon', 'Озон']),
  ('samokat', 'Самокат', ['Самокат']),
  ('kuper', 'Купер', ['Купер', 'СберМаркет', 'Сбер Маркет']),
  ('magnit', 'Магнит', ['Магнит']),
  ('dixy', 'Дикси', ['Дикси']),
  ('verny', 'Верный', ['Верный']),
  ('globus', 'Глобус', ['Глобус']),
  ('okey', "О'КЕЙ", ["О'КЕЙ", 'ОКЕЙ']),
  ('fix_price', 'Fix Price', ['Fix Price', 'Фикс Прайс']),
  ('super_lenta', 'Супер Лента', ['Супер Лента']),
  ('ulybka_radugi', 'Улыбка Радуги', ['Улыбка Радуги']),
  ('pyaterochka', 'Пятёрочка', ['Пятёрочка', 'Пятерочка']),
  ('perekrestok', 'Перекрёсток', ['Перекрёсток', 'Перекресток']),
  ('lenta', 'Лента', ['Лента']),
  ('vkusvill', 'ВкусВилл', ['ВкусВилл', 'Вкус Вилл']),
  ('gold_apple', 'Золотое Яблоко', ['Золотое Яблоко']),
  ('rive_gauche', 'РИВ ГОШ', ['РИВ ГОШ', 'Rive Gauche']),
  ('sportmaster', 'Спортмастер', ['Спортмастер']),
  ('detmir', 'Детский мир', ['Детский мир']),
  ('lamoda', 'Lamoda', ['Lamoda', 'Ламода']),
  ('mvideo', 'М.Видео', ['М.Видео', 'МВидео', 'M.Video']),
  ('eldorado', 'Эльдорадо', ['Эльдорадо']),
  ('aliexpress', 'AliExpress', ['AliExpress', 'АлиЭкспресс']),
  ('rostics', "ROSTIC'S", ["ROSTIC'S", 'Ростикс', 'Rostics']),
  ('burger_king', 'Burger King', ['Burger King', 'Бургер Кинг']),
  ('dodo', 'Додо Пицца', ['Додо Пицца', 'Додо']),
  ('citydrive', 'Ситидрайв', ['Ситидрайв', 'Citydrive']),
  ('yandex_travel', 'Яндекс Путешествия', ['Яндекс Путешествия']),
  ('yandex_afisha', 'Яндекс Афиша', ['Яндекс Афиша']),
];
