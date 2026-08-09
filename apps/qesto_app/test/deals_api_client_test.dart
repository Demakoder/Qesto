import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qesto/data/models/qesto_models.dart';
import 'package:qesto/features/benefits/data/deals_api_client.dart';

void main() {
  test('maps promo codes and deals from the ingestion API', () async {
    final client = DealsApiClient(
      baseUrl: 'http://deals.test',
      client: MockClient((request) async {
        expect(request.url.path, '/offers');
        return http.Response(
          '''
          {
            "offers": [
              {
                "id": "promo-1",
                "type": "promo_code",
                "merchant_id": "samokat",
                "merchant_name": "Самокат",
                "title": "Самокат — скидка 50% на первый заказ",
                "display_text": "Скидка 50% по промокоду SALE50",
                "promo_code": "SALE50",
                "discount_type": "percent",
                "discount_value": 50,
                "minimum_order": 700,
                "maximum_discount": 500,
                "customer_type": "new",
                "valid_until": "2026-08-31",
                "target_url": "https://samokat.ru/offer",
                "confidence": 100,
                "source": {"url": "https://t.me/skidki/1"}
              },
              {
                "id": "deal-1",
                "type": "deal",
                "merchant_id": "ozon",
                "merchant_name": "Ozon",
                "title": "Ozon — специальная цена",
                "display_text": "Товар за 1990 ₽ вместо 3490 ₽",
                "promo_code": null,
                "discount_type": "fixed",
                "discount_value": 1500,
                "customer_type": "all",
                "confidence": 80,
                "source": {"url": "https://t.me/pepperru/2"}
              }
            ]
          }
          ''',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final values = client.decodeOffers(await client.fetchOffersJson());

    expect(values, hasLength(2));
    expect(values.first.kind, DealKind.coupon);
    expect(values.first.promoCode, 'SALE50');
    expect(values.first.badge, 'SALE50');
    expect(values.first.minimumOrder, 700);
    expect(values.last.kind, DealKind.promotion);
    expect(values.last.badge, '−1500 ₽');
  });

  test('throws on a non-success API response', () async {
    final client = DealsApiClient(
      baseUrl: 'http://deals.test',
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );

    expect(client.fetchOffersJson(), throwsA(isA<DealsApiException>()));
  });
}
