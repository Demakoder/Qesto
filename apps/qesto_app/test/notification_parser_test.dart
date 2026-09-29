import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/notification_import/data/notification_capture_service.dart';
import 'package:qesto/features/notification_import/services/bank_notification_parser.dart';

void main() {
  const parser = SberbankNotificationParser();
  final postedAt = DateTime(2026, 7, 21, 14, 32);

  CapturedNotification notification({
    String packageName = 'ru.sberbankmobile',
    String title = 'Покупка Burger King',
    String text = '50 ₽ - Баланс: ... ₽ Счёт карты МИР ...',
  }) {
    return CapturedNotification(
      packageName: packageName,
      notificationKey: 'sber-test',
      postedAt: postedAt,
      title: title,
      text: text,
    );
  }

  test('распознаёт покупку Burger King из уведомления Сбербанка', () {
    final result = parser.parse(notification());

    expect(result, isNotNull);
    expect(result!.amountMinor, 5000);
    expect(result.merchant, 'Burger King');
    expect(result.categoryId, 'cafes');
    expect(result.subcategoryId, 'Фастфуд');
    expect(result.currency, 'RUB');
    expect(result.accountHint, 'МИР ...');
  });

  test('не принимает баланс за сумму покупки', () {
    final result = parser.parse(
      notification(text: '50 ₽ - Баланс: 123 456,78 ₽\nСчёт карты МИР *1234'),
    );

    expect(result?.amountMinor, 5000);
  });

  test('поддерживает рубли с копейками', () {
    final result = parser.parse(
      notification(text: '1 299,50 ₽ - Баланс: ... ₽'),
    );

    expect(result?.amountMinor, 129950);
    expect(result?.hasWholeCurrencyAmount, isFalse);
  });

  test('игнорирует другой пакет и принимает зачисление', () {
    expect(parser.parse(notification(packageName: 'com.example.bank')), isNull);
    expect(
      parser.parse(notification(title: 'Зачисление Burger King'))?.kind.name,
      'income',
    );
  });

  test('читает банковское SMS из Android-уведомления', () {
    final result = parser.parse(
      notification(
        packageName: 'com.google.android.apps.messaging',
        title: '900',
        text: 'Покупка 1 299,50 ₽ PYATEROCHKA. Карта *1234. Баланс 7000 ₽',
      ),
    );

    expect(result, isNotNull);
    expect(result!.isSmsNotification, isTrue);
    expect(result.amountMinor, 129950);
    expect(result.accountHint, '*1234');
    expect(result.categoryId, 'groceries');
  });

  test('отсекает OTP, рекламу и одинокий баланс', () {
    expect(
      parser.parse(notification(title: 'Код подтверждения', text: '1234')),
      isNull,
    );
    expect(
      parser.parse(
        notification(title: 'Предложение', text: 'Кредит до 50 000 ₽'),
      ),
      isNull,
    );
    expect(
      parser.parse(notification(title: 'Баланс', text: '50 000 ₽')),
      isNull,
    );
  });
}
