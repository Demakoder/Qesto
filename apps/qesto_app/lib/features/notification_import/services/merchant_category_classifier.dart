import '../domain/parsed_bank_transaction.dart';

class MerchantCategoryClassifier {
  const MerchantCategoryClassifier();

  CategorySuggestion classify(String merchant) {
    final value = _normalize(merchant);

    if (_containsAny(value, const [
      'burger king',
      'burgerrus',
      'бургер кинг',
      'kfc',
      'ростикс',
      'rostics',
      'вкусно и точка',
      'vkusnoitochka',
      'mcdonald',
    ])) {
      return const CategorySuggestion(
        categoryId: 'cafes',
        subcategoryId: 'Фастфуд',
      );
    }

    if (_containsAny(value, const [
      'пятерочка',
      'pyaterochka',
      'перекресток',
      'perekrestok',
      'вкусвилл',
      'vkusvill',
      'магнит',
      'magnit',
      'magnoliya',
      'auchan',
      'avokado',
      'metro store',
    ])) {
      return const CategorySuggestion(
        categoryId: 'groceries',
        subcategoryId: 'Супермаркеты',
      );
    }

    if (_containsAny(value, const [
      'mos transport',
      'moskva metro',
      'sbscr',
      'аэроэкспресс',
      'aeroexpress',
      'scooters',
      'такси',
      'taxi',
    ])) {
      return const CategorySuggestion(categoryId: 'transport');
    }

    if (_containsAny(value, const ['ozon', 'avito', 'market'])) {
      return const CategorySuggestion(categoryId: 'shopping');
    }

    if (_containsAny(value, const ['playerok', 'whoosh'])) {
      return const CategorySuggestion(categoryId: 'fun');
    }

    return const CategorySuggestion(categoryId: 'other');
  }

  bool _containsAny(String value, List<String> patterns) =>
      patterns.any(value.contains);

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp('[^a-zа-я0-9]+'), ' ')
      .trim();
}
