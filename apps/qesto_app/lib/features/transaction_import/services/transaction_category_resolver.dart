class ResolvedTransactionCategory {
  const ResolvedTransactionCategory({
    required this.categoryId,
    required this.confidence,
    this.subcategoryId,
  });

  final String categoryId;
  final String? subcategoryId;
  final double confidence;
}

/// One merchant/category vocabulary shared by every Qesto import adapter.
class TransactionCategoryResolver {
  const TransactionCategoryResolver();

  ResolvedTransactionCategory resolve(String text) {
    final value = _normalize(text);
    if (_containsAny(value, const [
      'пятерочка',
      'пятёрочка',
      'pyaterochka',
      '5ka',
      'перекресток',
      'перекрёсток',
      'perekrestok',
      'вкусвилл',
      'vkusvill',
      'магнит',
      'magnit',
      'магнолия',
      'magnoliya',
      'лента',
      'lenta',
      'дикси',
      'dixy',
      'auchan',
      'ашан',
      'avokado',
      'metro store',
      'продукт',
      'супермаркет',
      'бакалея',
      'grocery',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'groceries',
        subcategoryId: 'Супермаркеты',
        confidence: 0.96,
      );
    }
    if (_containsAny(value, const [
      'яндекс еда',
      'yandex eda',
      'delivery club',
      'самокат доставка',
      'доставка еды',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'delivery',
        confidence: 0.91,
      );
    }
    if (_containsAny(value, const [
      'общественный транспорт',
      'транспорт',
      'метро',
      'автобус',
      'трамвай',
      'троллейбус',
      'электричк',
      'проезд',
      'mos transport',
      'moskva metro',
      'sbscr',
      'аэроэкспресс',
      'aeroexpress',
      'scooters',
      'самокат',
      'whoosh',
      'московский транспорт',
      'moscow transport',
      'strelkacard',
      'стрелка кард',
      'цппк',
      'cppk',
      'такси',
      'taxi',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'transport',
        confidence: 0.94,
      );
    }
    if (_containsAny(value, const [
      'burger king',
      'burgerrus',
      'бургер кинг',
      'kfc',
      'ростикс',
      'rostic',
      'rostics',
      'вкусно и точка',
      'vkusnoitochka',
      'mcdonald',
      'blinberri',
      'gagawa',
      'еда вне дома',
      'фастфуд',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'cafes',
        subcategoryId: 'Фастфуд',
        confidence: 0.95,
      );
    }
    if (_containsAny(value, const [
      'restopay',
      'старик хинкалыч',
      'starik hinkalych',
      'sushi maximum',
      'herring cafe',
      'ikorniy',
      'khochu est',
      'ресторан',
      'restoran',
      'кафе',
      'cafe',
      'кофейн',
      'суши',
      'пицц',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'cafes',
        subcategoryId: 'Рестораны',
        confidence: 0.93,
      );
    }
    if (_containsAny(value, const [
      'аптек',
      'лекарств',
      'клиник',
      'медси',
      'гемотест',
      'инвитро',
      'стоматолог',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'health',
        confidence: 0.9,
      );
    }
    if (_containsAny(value, const [
      'салон красоты',
      'парикмах',
      'barbershop',
      'барбершоп',
      'маникюр',
      'nail',
      'косметик',
      'gold apple',
      'золотое яблоко',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'beauty',
        confidence: 0.88,
      );
    }
    if (_containsAny(value, const [
      'cian',
      'циан',
      'аренда квартир',
      'аренда жилья',
      'квартир',
      'жилье',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'housing',
        confidence: 0.91,
      );
    }
    if (_containsAny(value, const [
      'азс',
      'бензин',
      'топливо',
      'gazpromneft',
      'газпромнефть',
      'лукойл',
      'lukoil',
      'rosneft',
      'роснефть',
      'парковк',
      'автосервис',
      'шиномонтаж',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'car',
        confidence: 0.92,
      );
    }
    if (_containsAny(value, const [
      'жкх',
      'коммунал',
      'квартплат',
      'электроэнерг',
      'водоснаб',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'utilities',
        confidence: 0.9,
      );
    }
    if (_containsAny(value, const [
      'мтс',
      'megafon',
      'мегафон',
      'beeline',
      'билайн',
      'tele2',
      't2 mobile',
      'сотовая связь',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'mobile',
        confidence: 0.91,
      );
    }
    if (_containsAny(value, const [
      'ростелеком',
      'rostelecom',
      'дом ру',
      'dom ru',
      'интернет провайдер',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'internet',
        confidence: 0.91,
      );
    }
    if (_containsAny(value, const [
      'spotify',
      'netflix',
      'яндекс плюс',
      'yandex plus',
      'vk music',
      'яндекс музыка',
      'apple icloud',
      'google one',
      'подписка',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'subscriptions',
        confidence: 0.93,
      );
    }
    if (_containsAny(value, const ['кредит', 'займ', 'задолженн', 'ипотек'])) {
      return const ResolvedTransactionCategory(
        categoryId: 'loans',
        confidence: 0.88,
      );
    }
    if (_containsAny(value, const ['подарок', 'подарки'])) {
      return const ResolvedTransactionCategory(
        categoryId: 'gifts',
        confidence: 0.85,
      );
    }
    if (_containsAny(value, const [
      'evo cvety',
      'цветы',
      'цветочный',
      'букет',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'gifts',
        confidence: 0.9,
      );
    }
    if (_containsAny(value, const [
      'kupibilet',
      'купибилет',
      'авиабилет',
      'авиакомпан',
      'airlines',
      'аэропорт',
      'отель',
      'hotel',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'travel',
        confidence: 0.94,
      );
    }
    if (_containsAny(value, const [
      'мгу',
      'университет',
      'институт',
      'образован',
      'обучен',
      'курс',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'education',
        confidence: 0.9,
      );
    }
    if (_containsAny(value, const [
      'kinomaks',
      'киномакс',
      'кинотеатр',
      'cinema',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'fun',
        subcategoryId: 'Кино',
        confidence: 0.95,
      );
    }
    if (_containsAny(value, const [
      'lamoda',
      'ламода',
      'sportmaster',
      'спортмастер',
      'kari',
      'одежда',
      'обувь',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'clothes',
        confidence: 0.88,
      );
    }
    if (_containsAny(value, const [
      'fix price',
      'фикс прайс',
      'leroy merlin',
      'лемана про',
      'петрович',
      'товары для дома',
      'бытовые товары',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'household',
        confidence: 0.88,
      );
    }
    if (_containsAny(value, const [
      'зоомагазин',
      'petshop',
      'четыре лапы',
      'ветклиник',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'pets',
        confidence: 0.91,
      );
    }
    if (_containsAny(value, const [
      'налог',
      'госпошлин',
      'штраф гибдд',
      'фнс',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'taxes',
        confidence: 0.92,
      );
    }
    if (_containsAny(value, const [
      'страхован',
      'ингосстрах',
      'росгосстрах',
      'альфастрах',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'insurance',
        confidence: 0.92,
      );
    }
    if (_containsAny(value, const [
      'благотвор',
      'пожертвован',
      'charity',
      'donation',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'charity',
        confidence: 0.9,
      );
    }
    if (_containsAny(value, const ['айкос', 'iqos', 'табак', 'сигарет'])) {
      return const ResolvedTransactionCategory(
        categoryId: 'habits',
        confidence: 0.9,
      );
    }
    if (_containsAny(value, const [
      'ароматный мир',
      'красное белое',
      'красное и белое',
      'винлаб',
      'алкомаркет',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'habits',
        confidence: 0.93,
      );
    }
    if (_containsAny(value, const [
      '32links',
      'реклама',
      'продвижение',
      'хостинг',
      'рег ру',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'business',
        confidence: 0.84,
      );
    }
    if (_containsAny(value, const [
      'ozon',
      'озон',
      'яндекс маркет',
      'avito',
      'market',
      'маркет',
      'покупк',
      'wildberries',
      'вайлдберриз',
    ])) {
      return const ResolvedTransactionCategory(
        categoryId: 'shopping',
        confidence: 0.82,
      );
    }
    if (_containsAny(value, const ['playerok'])) {
      return const ResolvedTransactionCategory(
        categoryId: 'fun',
        confidence: 0.88,
      );
    }
    return const ResolvedTransactionCategory(
      categoryId: 'other',
      confidence: 0.55,
    );
  }

  bool _containsAny(String value, List<String> patterns) =>
      patterns.any(value.contains);

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
