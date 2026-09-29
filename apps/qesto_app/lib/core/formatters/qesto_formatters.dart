const _monthNames = <String>[
  'январь',
  'февраль',
  'март',
  'апрель',
  'май',
  'июнь',
  'июль',
  'август',
  'сентябрь',
  'октябрь',
  'ноябрь',
  'декабрь',
];

const _monthGenitiveNames = <String>[
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

String currencySymbol(String currency) => switch (currency) {
  'RUB' => '₽',
  'USD' => r'$',
  'EUR' => '€',
  _ => currency,
};

String formatMoney(int amount, String currency, {bool showSign = false}) {
  final absolute = amount.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < absolute.length; index++) {
    if (index > 0 && (absolute.length - index) % 3 == 0) {
      buffer.write(' ');
    }
    buffer.write(absolute[index]);
  }

  final sign = amount < 0 ? '−' : (showSign && amount > 0 ? '+' : '');
  return '$sign$buffer ${currencySymbol(currency)}';
}

String formatBudgetPeriod(int month, int year, {bool includeYear = false}) {
  final name = _monthNames[(month - 1).clamp(0, 11)];
  return includeYear ? '$name $year' : name;
}

/// Exact two-decimal monetary label without a floating-point conversion.
String formatMinorMoney(int amountMinor, String currency) {
  final magnitude = amountMinor.abs();
  final major = formatMoney(magnitude ~/ 100, '').trimRight();
  final cents = (magnitude % 100).toString().padLeft(2, '0');
  return '${amountMinor < 0 ? '−' : ''}$major,$cents ${currencySymbol(currency)}';
}

String capitalize(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

String formatPercent(double value, {int decimals = 0}) {
  return '${(value * 100).toStringAsFixed(decimals)}%';
}

String formatDate(DateTime date, {bool includeYear = false}) {
  final month = _monthGenitiveNames[(date.month - 1).clamp(0, 11)];
  return includeYear ? '${date.day} $month ${date.year}' : '${date.day} $month';
}

String formatCompactMoney(num amount, String currency) {
  final rounded = amount.round();
  if (rounded.abs() >= 1000000) {
    final value = rounded / 1000000;
    return '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} млн ${currencySymbol(currency)}';
  }
  if (rounded.abs() >= 1000) {
    return '${(rounded / 1000).round()} тыс. ${currencySymbol(currency)}';
  }
  return formatMoney(rounded, currency);
}
