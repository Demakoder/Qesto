import 'package:flutter_test/flutter_test.dart';

import 'package:qesto/features/bank_browser/sber/sber_connector_models.dart';
import 'package:qesto/features/bank_browser/sber/sber_page_detector.dart';

void main() {
  const detector = SberPageDetector();

  SberPageSnapshot page(String text, {String path = '/'}) => SberPageSnapshot(
    url: Uri.https('online.sberbank.ru', path),
    title: text,
    text: text,
    pinMarkers: const [],
    loginMarkers: const [],
  );

  test('classifies authenticated read-only sections', () {
    expect(detector.detect(page('Мои счета Баланс')), SberPageType.accounts);
    expect(
      detector.detect(page('История операций', path: '/history')),
      SberPageType.transactions,
    );
    expect(
      detector.detect(page('Портфель инвестиции', path: '/broker')),
      SberPageType.investments,
    );
  });

  test('does not classify the route-identical loading shell as dashboard', () {
    expect(
      detector.detect(page('Сбербанк Онлайн Идёт загрузка', path: '/app/main')),
      SberPageType.unknown,
    );
  });

  test('route identity wins over shared product labels', () {
    expect(
      detector.detect(
        page(
          'Все счета, карты и бонусы Накопления Привязана 1 карта',
          path: '/app/wallet',
        ),
      ),
      SberPageType.accounts,
    );
    expect(
      detector.detect(
        page('Платёжный счёт Баланс', path: '/app/cta/details/account-1'),
      ),
      SberPageType.accountDetails,
    );
    expect(
      detector.detect(
        page('Все операции Перевод в накопления', path: '/app/operations'),
      ),
      SberPageType.transactions,
    );
    expect(
      detector.detect(
        page('Накопления Вклады и счета Инвестиции', path: '/app/savings'),
      ),
      SberPageType.savings,
    );
  });

  test('requires multiple PIN markers before selecting PIN page', () {
    expect(
      detector.detect(
        SberPageSnapshot(
          url: Uri.https('online.sberbank.ru', '/'),
          title: 'Быстрый вход',
          text: 'PIN Войти',
          pinMarkers: const ['pin-heading'],
          loginMarkers: const [],
        ),
      ),
      SberPageType.login,
    );
    expect(
      detector.detect(
        SberPageSnapshot(
          url: Uri.https('online.sberbank.ru', '/'),
          title: 'PIN',
          text: 'PIN',
          pinMarkers: const ['pin-heading', 'keypad', 'pin-input'],
          loginMarkers: const [],
        ),
      ),
      SberPageType.pinLogin,
    );
  });
}
