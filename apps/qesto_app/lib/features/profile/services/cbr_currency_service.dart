import 'dart:convert';

import 'package:http/http.dart' as http;

class CbrCurrencyRate {
  const CbrCurrencyRate({
    required this.code,
    required this.name,
    required this.rublesPerUnit,
  });

  final String code;
  final String name;
  final double rublesPerUnit;
}

class CbrRateSnapshot {
  const CbrRateSnapshot({required this.date, required this.rates});

  final DateTime date;
  final Map<String, CbrCurrencyRate> rates;
}

class CbrCurrencyService {
  CbrCurrencyService({this.client});

  static const supportedCurrencies = <String>[
    'RUB',
    'USD',
    'EUR',
    'CNY',
    'GBP',
    'CHF',
    'KZT',
    'AED',
  ];

  static const currencyNames = <String, String>{
    'RUB': 'Российский рубль',
    'USD': 'Доллар США',
    'EUR': 'Евро',
    'CNY': 'Китайский юань',
    'GBP': 'Фунт стерлингов',
    'CHF': 'Швейцарский франк',
    'KZT': 'Казахстанский тенге',
    'AED': 'Дирхам ОАЭ',
  };

  final http.Client? client;

  Future<CbrRateSnapshot> loadLatest() async {
    final uri = Uri.https('www.cbr.ru', '/scripts/XML_daily.asp');
    final response = client == null
        ? await http.get(uri, headers: const {'Accept': 'application/xml'})
        : await client!.get(uri, headers: const {'Accept': 'application/xml'});
    if (response.statusCode != 200) {
      throw StateError('CBR returned HTTP ${response.statusCode}');
    }
    return parse(latin1.decode(response.bodyBytes));
  }

  CbrRateSnapshot parse(String xml) {
    final dateMatch = RegExp(
      r'<ValCurs[^>]*Date="(\d{2})\.(\d{2})\.(\d{4})"',
    ).firstMatch(xml);
    if (dateMatch == null) throw const FormatException('CBR date is missing');
    final date = DateTime(
      int.parse(dateMatch.group(3)!),
      int.parse(dateMatch.group(2)!),
      int.parse(dateMatch.group(1)!),
    );
    final rates = <String, CbrCurrencyRate>{
      'RUB': const CbrCurrencyRate(
        code: 'RUB',
        name: 'Российский рубль',
        rublesPerUnit: 1,
      ),
    };
    final blocks = RegExp(
      r'<Valute[^>]*>(.*?)</Valute>',
      dotAll: true,
    ).allMatches(xml);
    for (final block in blocks) {
      final value = block.group(1)!;
      final code = _tag(value, 'CharCode');
      if (code == null || !supportedCurrencies.contains(code)) continue;
      final nominal = int.tryParse(_tag(value, 'Nominal') ?? '') ?? 1;
      final unitValue = _decimal(_tag(value, 'VunitRate'));
      final totalValue = _decimal(_tag(value, 'Value'));
      final rublesPerUnit =
          unitValue ??
          (totalValue == null || nominal == 0 ? null : totalValue / nominal);
      if (rublesPerUnit == null) continue;
      rates[code] = CbrCurrencyRate(
        code: code,
        name: currencyNames[code] ?? code,
        rublesPerUnit: rublesPerUnit,
      );
    }
    return CbrRateSnapshot(date: date, rates: rates);
  }

  String? _tag(String source, String tag) => RegExp(
    '<$tag>(.*?)</$tag>',
    dotAll: true,
  ).firstMatch(source)?.group(1)?.trim();

  double? _decimal(String? value) => value == null
      ? null
      : double.tryParse(value.replaceAll(' ', '').replaceAll(',', '.'));
}
