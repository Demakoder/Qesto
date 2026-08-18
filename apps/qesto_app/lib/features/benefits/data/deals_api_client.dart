import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../data/models/qesto_models.dart';
import 'bounded_http_response.dart';
import 'platform_deals_source.dart';

class DealsApiClient {
  DealsApiClient({
    http.Client? client,
    String? baseUrl,
    this.timeout = const Duration(seconds: 3),
    this.maximumResponseBytes = 12 * 1024 * 1024,
  }) : _client = client ?? http.Client(),
       baseUrl =
           baseUrl ??
           const String.fromEnvironment(
             'QESTO_DEALS_API_URL',
             defaultValue: 'http://127.0.0.1:8787',
           );

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;
  final int maximumResponseBytes;

  Future<String> fetchOffersJson() async {
    final platformResult = await fetchPlatformDealsJson(client: _client);
    if (platformResult != null) {
      if (utf8.encode(platformResult).length > maximumResponseBytes) {
        throw const DealsApiException('Deals API response is too large');
      }
      return platformResult;
    }
    final request = http.Request('GET', Uri.parse('$baseUrl/offers?limit=300'));
    final response = await _client.send(request).timeout(timeout);
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      throw DealsApiException('Deals API returned ${response.statusCode}');
    }
    try {
      return await readBoundedHttpBody(
        response,
        maximumBytes: maximumResponseBytes,
        timeout: timeout,
      );
    } on BoundedHttpBodyException catch (error) {
      throw DealsApiException(error.message);
    }
  }

  List<Deal> decodeOffers(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;
    final values = root['offers'] as List<dynamic>? ?? const [];
    return values
        .map((value) => _dealFromJson(value as Map<String, dynamic>))
        .toList(growable: false);
  }

  Deal _dealFromJson(Map<String, dynamic> json) {
    final offerType = json['type'] as String? ?? 'unknown';
    final merchantName = json['merchant_name'] as String?;
    final promoCode = json['promo_code'] as String?;
    final discountType = json['discount_type'] as String?;
    final discountValue = json['discount_value'] as int?;
    final source = json['source'] as Map<String, dynamic>?;
    return Deal(
      id: json['id'] as String,
      userId: 'public-deals',
      kind: offerType == 'promo_code' ? DealKind.coupon : DealKind.promotion,
      category: merchantName ?? _typeLabel(offerType),
      title: json['title'] as String? ?? 'Предложение',
      description:
          json['display_text'] as String? ??
          json['original_text'] as String? ??
          '',
      visualKey: _visualKey(json['merchant_id'] as String?, offerType),
      badge: promoCode ?? _discountBadge(discountType, discountValue),
      promoCode: promoCode,
      merchantName: merchantName,
      targetUrl: json['target_url'] as String?,
      sourceUrl: source?['url'] as String?,
      discountType: discountType,
      discountValue: discountValue,
      minimumOrder: json['minimum_order'] as int?,
      maximumDiscount: json['maximum_discount'] as int?,
      customerType: json['customer_type'] as String?,
      validUntil: json['valid_until'] == null
          ? null
          : DateTime.tryParse(json['valid_until'] as String),
      confidence: json['confidence'] as int?,
    );
  }
}

class DealsApiException implements Exception {
  const DealsApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

String? _discountBadge(String? type, int? value) {
  if (value == null) return null;
  return type == 'percent' ? '−$value%' : '−$value ₽';
}

String _typeLabel(String value) => switch (value) {
  'cashback' => 'Кэшбэк',
  'free_delivery' => 'Доставка',
  'gift' => 'Подарок',
  _ => 'Акция',
};

String _visualKey(String? merchantId, String offerType) {
  if (offerType == 'free_delivery') return 'delivery';
  if (offerType == 'cashback') return 'fuel';
  return switch (merchantId) {
    'pyaterochka' ||
    'perekrestok' ||
    'lenta' ||
    'vkusvill' ||
    'magnit' ||
    'magnit_delivery' => 'groceries',
    'rostics' || 'burger_king' || 'dodo' || 'yandex_food' => 'restaurant',
    'mvideo' || 'eldorado' => 'electronics',
    'lamoda' || 'sportmaster' || 'detmir' => 'fashion',
    'samokat' || 'kuper' || 'yandex_lavka' => 'delivery',
    'citydrive' => 'taxi',
    _ => 'offer',
  };
}
