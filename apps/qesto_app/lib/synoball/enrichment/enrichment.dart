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
      updatedAt: DateTime.now(),
    );
  }

  List<RecurringStream> detectRecurring(
    Iterable<CanonicalTransaction> transactions,
  ) {
    final groups = <String, List<CanonicalTransaction>>{};
    for (final transaction in transactions) {
      if (transaction.status != CanonicalTransactionStatus.posted ||
          transaction.direction != FinancialDirection.outflow) {
        continue;
      }
      final merchant = transaction.merchantName?.trim();
      if (merchant == null || merchant.isEmpty) continue;
      final key =
          '${_key(merchant)}:${transaction.amount.minorUnits}:'
          '${transaction.amount.currency}';
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
          ? DateTime(
              last.occurredAt.year,
              last.occurredAt.month + 1,
              last.occurredAt.day,
              last.occurredAt.hour,
              last.occurredAt.minute,
            )
          : last.occurredAt.add(const Duration(days: 7));
      streams.add(
        RecurringStream(
          id: 'rec-${_key(last.merchantName!)}-${last.amount.minorUnits}',
          entityId: last.entityId,
          merchantKey: _key(last.merchantName!),
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

class _MerchantResolution {
  const _MerchantResolution(this.id, this.name, this.confidence);
  final String id;
  final String name;
  final double confidence;
}

String _key(String value) => value
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
