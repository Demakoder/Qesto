import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qesto/features/benefits/data/telegram_deals_ingestion.dart';

void main() {
  const page = '''
  <html><body>
    <div class="tgme_widget_message js-widget_message" data-post="skidki/101">
      <div class="tgme_widget_message_text js-message_text">
        1. Промокоды для новых пользователей<br>
        ➡️ Самокат — скидка 50% на первый заказ от 700 ₽<br>
        🔖 промокод <code>NEW50</code><br>
        ➡️ Ozon — скидка 500 ₽ на заказ от 2500 ₽<br>
        🔖 код <code>OZON500</code><br>
        Реклама. ООО Тест, erid 123
        <a href="https://samokat.ru/promo">получить</a>
      </div>
      <time datetime="2026-08-09T10:00:00+00:00"></time>
    </div>
    <div class="tgme_widget_message js-widget_message" data-post="skidki/102">
      <div class="tgme_widget_message_text js-message_text">
        Скидка на вино 30%, промокод <code>WINE30</code>
      </div>
      <time datetime="2026-08-09T11:00:00+00:00"></time>
    </div>
  </body></html>
  ''';

  test(
    'splits a Telegram post into code-specific offers and blocks alcohol',
    () {
      final source = TelegramDealsIngestion().buildOffersJson({'skidki': page});
      final root = jsonDecode(source) as Map<String, dynamic>;
      final offers = root['offers'] as List<dynamic>;

      expect(offers, hasLength(2));
      final byCode = {
        for (final value in offers.cast<Map<String, dynamic>>())
          value['promo_code'] as String: value,
      };
      expect(byCode.keys, containsAll(<String>['NEW50', 'OZON500']));
      expect(byCode['NEW50']!['merchant_id'], 'samokat');
      expect(byCode['NEW50']!['discount_value'], 50);
      expect(byCode['NEW50']!['minimum_order'], 700);
      expect(byCode['NEW50']!['display_text'], isNot(contains('Ozon')));
      expect(byCode['NEW50']!['display_text'], isNot(contains('Реклама.')));
      expect(byCode['OZON500']!['merchant_id'], 'ozon');
      expect(source, isNot(contains('WINE30')));
    },
  );

  test('deduplicates the same promo code from different channels', () {
    const duplicatePage = '''
    <div class="tgme_widget_message js-widget_message" data-post="kuponych/55">
      <div class="tgme_widget_message_text js-message_text">
        Самокат — скидка 50% на первый заказ<br>
        промокод <code>NEW50</code>
      </div>
      <time datetime="2026-08-09T12:00:00+00:00"></time>
    </div>
    ''';
    final source = TelegramDealsIngestion().buildOffersJson({
      'skidki': page,
      'kuponych': duplicatePage,
    });
    final root = jsonDecode(source) as Map<String, dynamic>;
    final offers = (root['offers'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(
      offers.where((offer) => offer['promo_code'] == 'NEW50'),
      hasLength(1),
    );
  });

  test('bounds Telegram pages and individual messages', () async {
    final oversizedClient = TelegramDealsIngestion(
      maximumPageBytes: 4,
      client: MockClient((_) async => http.Response('12345', 200)),
    );
    await expectLater(
      oversizedClient.fetchOffersJson(),
      throwsA(isA<StateError>()),
    );

    final longText = 'Ozon — скидка 10% ${List.filled(12_100, 'x').join()}';
    final source = TelegramDealsIngestion().buildOffersJson({
      'skidki':
          '<div data-post="skidki/1"><div class="js-message_text">'
          '$longText</div></div>',
    });
    final offer =
        ((jsonDecode(source) as Map<String, dynamic>)['offers']
                    as List<dynamic>)
                .single
            as Map<String, dynamic>;
    expect(
      (offer['original_text'] as String).length,
      lessThanOrEqualTo(12_000),
    );
  });
}
