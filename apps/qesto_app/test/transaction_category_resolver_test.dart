import 'package:flutter_test/flutter_test.dart';
import 'package:qesto/features/transaction_import/services/transaction_category_resolver.dart';

void main() {
  const resolver = TransactionCategoryResolver();

  test('classifies the known merchant corpus from Sber history', () {
    const expectations = <String, String>{
      'Лента-0304 Москва RUS': 'groceries',
      'DIXY-77055D MOSCOW RUS': 'groceries',
      'PEREKRESTOK FILEVSKIJ BI MOSCOW RUS': 'groceries',
      'Московский транспорт': 'transport',
      'STRELKACARD_1 MOSCOW RUS': 'transport',
      'CPPK-2000400-APB09 Chekhov RUS': 'transport',
      'YANDEX 7999 SCOOTERS MOSCOW RUS': 'transport',
      "Rostic's": 'cafes',
      'restopay Мурманск RUS': 'cafes',
      'STARIK HINKALYCH_5 MOSCOW RUS': 'cafes',
      'EVO_CVETY. MOSCOW RUS': 'gifts',
      'YM CIAN MOSCOW RUS': 'housing',
      'KUPIBILET.RU город Санкт-Петербург RUS': 'travel',
      'МГУ Оплата услуг': 'education',
      'KINOMAKS MOSCOW 643': 'fun',
      'Ароматный Мир': 'habits',
      '32links.ru Уральск KZ': 'business',
    };

    for (final entry in expectations.entries) {
      expect(
        resolver.resolve(entry.key).categoryId,
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('does not invent a category for payment intermediaries or people', () {
    expect(resolver.resolve('YM yandex pay MOSKVA RUS').categoryId, 'other');
    expect(resolver.resolve('Дмитрий Аркадьевич Л.').categoryId, 'other');
    expect(resolver.resolve('BPA 629 KHIMKI RUS').categoryId, 'other');
  });
}
