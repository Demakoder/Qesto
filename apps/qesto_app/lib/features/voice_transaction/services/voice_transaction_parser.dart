import '../../../data/models/qesto_models.dart';
import '../domain/voice_transaction_models.dart';

class VoiceTransactionParser {
  const VoiceTransactionParser();

  VoiceTransactionDraft parse({
    required String text,
    required List<BudgetCategory> categories,
    required List<QestoAccount> accounts,
  }) {
    final normalized = _normalize(text);
    if (normalized.isEmpty) {
      throw const VoiceTransactionParseException('Фраза оказалась пустой');
    }

    final amount = _extractAmount(normalized);
    if (amount == null || amount <= 0) {
      throw const VoiceTransactionParseException(
        'Не услышал сумму. Например: «потратил 850 рублей на продукты»',
      );
    }

    final kind = _findKind(normalized);
    final category = kind == VoiceTransactionKind.expense
        ? _findCategory(normalized, categories)
        : null;
    final accountPair = kind == VoiceTransactionKind.transfer
        ? _findTransferAccounts(normalized, accounts)
        : const _AccountPair();
    final defaultAccount = accounts
        .where((account) => account.type != AccountType.liability)
        .firstOrNull;

    return VoiceTransactionDraft(
      rawText: text.trim(),
      kind: kind,
      amount: amount,
      title: _findTitle(normalized, kind, category),
      categoryId: category?.id,
      sourceAccountId: accountPair.sourceId ?? defaultAccount?.id,
      destinationAccountId: accountPair.destinationId,
    );
  }

  VoiceTransactionKind _findKind(String text) {
    if (RegExp(
      r'(перевел|перевёл|перевести|перевод|перекинул|перекинула)|'
      r'между\s+(?:моими\s+)?счетами|(?:^| )со?\s+.+\s+на\s+.+',
    ).hasMatch(text)) {
      return VoiceTransactionKind.transfer;
    }
    if (RegExp(
      r'(доход|зарплат[а-я]*|аванс[а-я]*|преми[а-я]*|кешб[эе]к[а-я]*|'
      r'заработал[а-я]*|получил[а-я]*|начислил[а-я]*|поступил[а-я]*|пришло)',
    ).hasMatch(text)) {
      return VoiceTransactionKind.income;
    }
    return VoiceTransactionKind.expense;
  }

  BudgetCategory? _findCategory(String text, List<BudgetCategory> categories) {
    BudgetCategory? best;
    var bestScore = 0;
    for (final category in categories) {
      var score = 0;
      for (final value in [
        category.name,
        if (category.shortName != null) category.shortName!,
        ...category.subcategories,
      ]) {
        final candidate = _normalize(value);
        if (candidate.length >= 3 && text.contains(candidate)) {
          score = score < candidate.length ? candidate.length : score;
        }
      }
      for (final alias in _categoryAliases[category.id] ?? const <String>[]) {
        if (RegExp(alias).hasMatch(text)) score += 20;
      }
      if (score > bestScore) {
        bestScore = score;
        best = category;
      }
    }
    return best ?? categories.where((item) => item.id == 'other').firstOrNull;
  }

  _AccountPair _findTransferAccounts(String text, List<QestoAccount> accounts) {
    final parts = RegExp(r'(?:^| )со?\s+(.+?)\s+на\s+(.+)$').firstMatch(text);
    if (parts == null) return const _AccountPair();
    final source = _matchAccount(parts.group(1)!, accounts);
    final destination = _matchAccount(parts.group(2)!, accounts);
    return _AccountPair(
      sourceId: source?.id,
      destinationId: destination?.id == source?.id ? null : destination?.id,
    );
  }

  QestoAccount? _matchAccount(String fragment, List<QestoAccount> accounts) {
    QestoAccount? best;
    var bestScore = 0;
    final fragmentTokens = _meaningfulTokens(fragment);
    for (final account in accounts) {
      final title = _normalize(account.title);
      var score = fragment.contains(title) ? 100 : 0;
      for (final titleToken in _meaningfulTokens(title)) {
        if (fragmentTokens.any(
          (token) =>
              token.startsWith(titleToken) || titleToken.startsWith(token),
        )) {
          score += titleToken.length;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = account;
      }
    }
    return bestScore >= 4 ? best : null;
  }

  String _findTitle(
    String text,
    VoiceTransactionKind kind,
    BudgetCategory? category,
  ) {
    if (kind == VoiceTransactionKind.transfer) return 'Перевод между счетами';
    if (kind == VoiceTransactionKind.income) {
      if (text.contains('зарплат')) return 'Зарплата';
      if (text.contains('аванс')) return 'Аванс';
      if (text.contains('преми')) return 'Премия';
      if (RegExp(r'кешб[эе]к').hasMatch(text)) return 'Кешбэк';
      return 'Доход';
    }

    final afterPurpose = RegExp(
      r'(?:^| )(?:на|за)\s+([а-яё][а-яё\s-]{2,})$',
    ).firstMatch(text)?.group(1);
    if (afterPurpose != null) {
      final cleaned = _removeMoneyWords(afterPurpose);
      if (cleaned.length >= 3) return _capitalize(cleaned);
    }
    return category?.name ?? 'Расход';
  }

  int? _extractAmount(String text) {
    RegExpMatch? fallback;
    for (final match in _numericAmount.allMatches(text)) {
      fallback ??= match;
      final tail = text.substring(match.end);
      if (RegExp(
        r'^\s*(?:₽|р\.?|руб[а-я]*|коп[а-я]*)(?:\s|$)',
      ).hasMatch(tail)) {
        return _numericMatchToRubles(match);
      }
    }
    if (fallback != null) return _numericMatchToRubles(fallback);
    return _extractWordAmount(text);
  }

  int _numericMatchToRubles(RegExpMatch match) {
    final whole = int.parse(match.group(1)!.replaceAll(RegExp(r'\s+'), ''));
    final fractionText = match.group(2);
    if (fractionText == null) return whole;
    final fraction = int.parse(fractionText.padRight(2, '0'));
    return (whole + fraction / 100).round();
  }

  int? _extractWordAmount(String text) {
    final tokens = text.split(' ');
    for (var start = 0; start < tokens.length; start++) {
      var current = 0;
      var total = 0;
      var consumed = 0;
      for (var index = start; index < tokens.length; index++) {
        final token = tokens[index];
        final value = _numberWords[token];
        if (value != null) {
          current += value;
          consumed++;
          continue;
        }
        if (_thousandWords.contains(token)) {
          total += (current == 0 ? 1 : current) * 1000;
          current = 0;
          consumed++;
          continue;
        }
        break;
      }
      if (consumed > 0) return total + current;
    }
    return null;
  }

  static final _numericAmount = RegExp(
    r'\b(\d+(?:\s\d{3})*)(?:[,.](\d{1,2}))?',
  );

  static const _numberWords = <String, int>{
    'ноль': 0,
    'один': 1,
    'одна': 1,
    'одно': 1,
    'два': 2,
    'две': 2,
    'три': 3,
    'четыре': 4,
    'пять': 5,
    'шесть': 6,
    'семь': 7,
    'восемь': 8,
    'девять': 9,
    'десять': 10,
    'одиннадцать': 11,
    'двенадцать': 12,
    'тринадцать': 13,
    'четырнадцать': 14,
    'пятнадцать': 15,
    'шестнадцать': 16,
    'семнадцать': 17,
    'восемнадцать': 18,
    'девятнадцать': 19,
    'двадцать': 20,
    'тридцать': 30,
    'сорок': 40,
    'пятьдесят': 50,
    'шестьдесят': 60,
    'семьдесят': 70,
    'восемьдесят': 80,
    'девяносто': 90,
    'сто': 100,
    'двести': 200,
    'триста': 300,
    'четыреста': 400,
    'пятьсот': 500,
    'шестьсот': 600,
    'семьсот': 700,
    'восемьсот': 800,
    'девятьсот': 900,
  };

  static const _thousandWords = {'тысяча', 'тысячи', 'тысяч', 'тысячу'};

  static const _categoryAliases = <String, List<String>>{
    'housing': [r'(аренд[а-я]*|квартир[а-я]*|жиль[её][а-я]*)'],
    'utilities': [r'(жкх|коммунал[а-я]*|электрич[а-я]*|вод[ау]|газ)'],
    'groceries': [
      r'(продукт[а-я]*|супермаркет[а-я]*|пят[её]рочк[а-я]*|магнит[а-я]*|перекр[её]ст[а-я]*|лента)',
    ],
    'cafes': [r'(кафе|ресторан[а-я]*|кофе|бургер[а-я]*|фастфуд[а-я]*)'],
    'delivery': [r'доставк[а-я]*'],
    'transport': [r'(такси|метро|автобус[а-я]*|проезд[а-я]*|транспорт[а-я]*)'],
    'car': [r'(бензин[а-я]*|заправк[а-я]*|автомобил[а-я]*|парковк[а-я]*)'],
    'health': [r'(аптек[а-я]*|лекарств[а-я]*|врач[а-я]*|медицин[а-я]*)'],
    'beauty': [r'(косметик[а-я]*|парикмах[а-я]*|маникюр[а-я]*|салон[а-я]*)'],
    'clothes': [r'(одежд[а-я]*|обув[а-я]*)'],
    'shopping': [
      r'(маркетплейс[а-я]*|озон[а-я]*|вайлдберриз[а-я]*|покупк[а-я]*)',
    ],
    'household': [r'(бытов[а-я]*|хозяйствен[а-я]*|для\s+дома)'],
    'mobile': [r'(мобильн[а-я]*|телефон[а-я]*|симк[а-я]*)'],
    'internet': [r'интернет[а-я]*'],
    'subscriptions': [r'подписк[а-я]*'],
    'fun': [r'(кино[а-я]*|игр[а-я]*|развлеч[а-я]*|концерт[а-я]*)'],
    'hobby': [r'хобби'],
    'gifts': [r'подар[а-я]*'],
    'family': [r'(семь[ея][а-я]*|близк[а-я]*|родител[а-я]*)'],
    'travel': [r'(путешеств[а-я]*|отпуск[а-я]*|отел[а-я]*|билет[а-я]*)'],
    'education': [r'(образован[а-я]*|курс[а-я]*|уч[её]б[а-я]*)'],
    'children': [r'(дет[а-я]*|реб[её]н[а-я]*)'],
    'pets': [r'(животн[а-я]*|кошк[а-я]*|собак[а-я]*|ветеринар[а-я]*)'],
    'taxes': [r'(налог[а-я]*|пошлин[а-я]*|штраф[а-я]*)'],
    'loans': [r'(кредит[а-я]*|долг[а-я]*|ипотек[а-я]*)'],
    'insurance': [r'страхов[а-я]*'],
    'charity': [r'(благотвор[а-я]*|пожертв[а-я]*)'],
    'business': [r'(бизнес[а-я]*|работ[а-я]*)'],
    'habits': [r'(алкогол[а-я]*|сигарет[а-я]*|табак[а-я]*)'],
  };
}

class _AccountPair {
  const _AccountPair({this.sourceId, this.destinationId});

  final String? sourceId;
  final String? destinationId;
}

Set<String> _meaningfulTokens(String value) => _normalize(value)
    .split(' ')
    .where(
      (token) =>
          token.length >= 3 &&
          !const {
            'карта',
            'карты',
            'счет',
            'счета',
            'счёт',
            'счёта',
          }.contains(token),
    )
    .toSet();

String _removeMoneyWords(String value) => value
    .replaceAll(RegExp(r'\b\d+(?:[,.]\d+)?\b'), ' ')
    .replaceAll(RegExp(r'(руб|коп)[а-я]*|₽'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9₽,.]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _capitalize(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
