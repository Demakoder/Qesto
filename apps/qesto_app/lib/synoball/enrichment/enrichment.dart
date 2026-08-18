import '../core/models.dart';

class EnrichmentEngine {
  const EnrichmentEngine();

  CanonicalTransaction enrich(CanonicalTransaction transaction) {
    final merchant = _resolveMerchant(
      transaction.merchantName ?? transaction.normalizedDescription,
    );
    final category = transaction.userCategoryOverride == null
        ? transaction.synoballCategory ??
              _categoryFor(merchant.name, transaction.providerCategory)
        : transaction.synoballCategory;
    return transaction.copyWith(
      merchantId: merchant.id,
      merchantName: merchant.name,
      merchantConfidence: merchant.confidence,
      synoballCategory: category,
      categoryConfidence: transaction.userCategoryOverride != null
          ? 1
          : category == null
          ? 0
          : transaction.synoballCategory != null
          ? transaction.categoryConfidence ?? 0.9
          : 0.82,
    );
  }

  List<RecurringStream> detectRecurring(
    Iterable<CanonicalTransaction> transactions,
  ) {
    final groups = <_RecurringKey, List<CanonicalTransaction>>{};
    for (final transaction in transactions) {
      if (transaction.status != CanonicalTransactionStatus.posted ||
          transaction.direction != FinancialDirection.outflow) {
        continue;
      }
      final merchant = transaction.merchantName?.trim();
      if (merchant == null || merchant.isEmpty) continue;
      final key = (
        entityId: transaction.entityId,
        merchant: _key(merchant),
        minorUnits: transaction.amount.minorUnits,
        currency: transaction.amount.currency,
      );
      groups.putIfAbsent(key, () => []).add(transaction);
    }
    final streams = <RecurringStream>[];
    for (final entry in groups.entries) {
      final items = entry.value
        ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      if (items.length < 3) continue;
      final intervals = <int>[];
      for (var index = 1; index < items.length; index++) {
        intervals.add(
          items[index].occurredAt
              .difference(items[index - 1].occurredAt)
              .inDays,
        );
      }
      final monthly = intervals.every((days) => days >= 25 && days <= 35);
      final weekly = intervals.every((days) => days >= 6 && days <= 8);
      if (!monthly && !weekly) continue;
      final last = items.last;
      final frequency = monthly
          ? RecurrenceFrequency.monthly
          : RecurrenceFrequency.weekly;
      final next = monthly
          ? _sameTimeNextMonth(last.occurredAt)
          : last.occurredAt.add(const Duration(days: 7));
      streams.add(
        RecurringStream(
          id:
              'rec-${last.entityId}-${entry.key.merchant}-'
              '${last.amount.minorUnits}-${last.amount.currency.toLowerCase()}',
          entityId: last.entityId,
          merchantKey: entry.key.merchant,
          title: last.merchantName!,
          typicalAmount: last.amount,
          frequency: frequency,
          nextExpectedAt: next,
          confidence: monthly ? 0.92 : 0.88,
          transactionIds: items.map((item) => item.id).toList(),
        ),
      );
    }
    return streams;
  }

  _MerchantResolution _resolveMerchant(String source) {
    final key = _key(source);
    if (key.contains('pyaterochka') ||
        key.contains('пятерочка') ||
        key == '5ka') {
      return const _MerchantResolution('mrc-pyaterochka', 'Пятёрочка', 0.99);
    }
    if (key.contains('yandexgo') ||
        key.contains('yandex go') ||
        key.contains('яндекс go')) {
      return const _MerchantResolution('mrc-yandex-go', 'Яндекс Go', 0.98);
    }
    if (key.contains('burger king')) {
      return const _MerchantResolution('mrc-burger-king', 'Burger King', 0.99);
    }
    if (key.contains('vkusvill') || key.contains('вкусвилл')) {
      return const _MerchantResolution('mrc-vkusvill', 'ВкусВилл', 0.98);
    }
    final name = source.trim().isEmpty ? 'Неизвестный продавец' : source.trim();
    return _MerchantResolution(
      'mrc-${_key(name).replaceAll(' ', '-')}',
      name,
      0.7,
    );
  }

  String? _categoryFor(String merchant, String? providerCategory) {
    final key = _key(merchant);
    if (key.contains('пятерочка') ||
        key.contains('вкусвилл') ||
        key.contains('supermarket')) {
      return 'groceries';
    }
    if (key.contains('burger king') ||
        key.contains('coffee') ||
        key.contains('кафе')) {
      return 'cafes';
    }
    if (key.contains('яндекс go') ||
        key.contains('taxi') ||
        key.contains('такси')) {
      return 'transport';
    }
    return providerCategory;
  }
}

typedef _RecurringKey = ({
  String entityId,
  String merchant,
  int minorUnits,
  String currency,
});

class _MerchantResolution {
  const _MerchantResolution(this.id, this.name, this.confidence);
  final String id;
  final String name;
  final double confidence;
}

final RegExp _nonMerchantCharacterPattern = RegExp(r'[^a-zа-я0-9]+');
final RegExp _whitespacePattern = RegExp(r'\s+');

String _key(String value) => value
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(_nonMerchantCharacterPattern, ' ')
    .replaceAll(_whitespacePattern, ' ')
    .trim();

DateTime _sameTimeNextMonth(DateTime value) {
  final nextYear = value.month == 12 ? value.year + 1 : value.year;
  final nextMonth = value.month == 12 ? 1 : value.month + 1;
  final followingMonthYear = nextMonth == 12 ? nextYear + 1 : nextYear;
  final followingMonth = nextMonth == 12 ? 1 : nextMonth + 1;
  final lastDay = value.isUtc
      ? DateTime.utc(
          followingMonthYear,
          followingMonth,
        ).subtract(const Duration(days: 1)).day
      : DateTime(
          followingMonthYear,
          followingMonth,
        ).subtract(const Duration(days: 1)).day;
  final day = value.day > lastDay ? lastDay : value.day;
  return value.isUtc
      ? DateTime.utc(
          nextYear,
          nextMonth,
          day,
          value.hour,
          value.minute,
          value.second,
          value.millisecond,
          value.microsecond,
        )
      : DateTime(
          nextYear,
          nextMonth,
          day,
          value.hour,
          value.minute,
          value.second,
          value.millisecond,
          value.microsecond,
        );
}
