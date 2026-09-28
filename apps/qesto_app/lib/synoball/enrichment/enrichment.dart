import 'dart:math' as math;

import '../core/models.dart';
import 'category_policy.dart';

class EnrichmentEngine {
  const EnrichmentEngine({this.categoryPolicy = const CategoryPolicy()});
  final CategoryPolicy categoryPolicy;

  String? merchantIdentity(CanonicalTransaction transaction) {
    final name = transaction.merchantName?.trim();
    if (name == null ||
        {
          '',
          'неизвестный продавец',
          'операция',
          'покупка',
          'перевод',
        }.contains(_key(name))) {
      return null;
    }
    return _resolveMerchant(name).id;
  }

  CanonicalTransaction enrich(CanonicalTransaction transaction) {
    final merchant = _resolveMerchant(
      transaction.merchantName ?? transaction.normalizedDescription,
    );
    final category = transaction.userCategoryOverride == null
        ? transaction.synoballCategory ??
              _categoryFor(merchant.name, transaction.providerCategory)
        : transaction.synoballCategory;
    final enriched = transaction.copyWith(
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
    return categoryPolicy.apply(enriched, identity: merchantIdentity(enriched));
  }

  List<RecurringStream> detectRecurring(
    Iterable<CanonicalTransaction> transactions, {
    void Function(RecurringDiagnostic)? onDiagnostic,
  }) {
    final groups = <_RecurringKey, List<CanonicalTransaction>>{};
    final seen = <(String, String)>{};
    for (final transaction in transactions) {
      final rejection = _ineligibleReason(transaction);
      if (rejection != null) {
        onDiagnostic?.call(RecurringDiagnostic(reason: rejection));
        continue;
      }
      // Evidence/import count must never become occurrence count.
      if (!seen.add((transaction.entityId, transaction.id))) continue;
      final merchant = transaction.merchantName?.trim();
      if (merchant == null ||
          merchant.isEmpty ||
          _key(merchant) == 'неизвестный продавец') {
        onDiagnostic?.call(
          const RecurringDiagnostic(reason: 'missing_merchant'),
        );
        continue;
      }
      final key = (
        entityId: transaction.entityId,
        merchant: _key(_resolveMerchant(merchant).name),
        currency: transaction.amount.currency,
      );
      groups.putIfAbsent(key, () => []).add(transaction);
    }
    final streams = <RecurringStream>[];
    var cluster = 0;
    for (final entry in groups.entries) {
      cluster++;
      final items = entry.value
        ..sort((a, b) {
          final date = a.occurredAt.compareTo(b.occurredAt);
          return date != 0 ? date : a.id.compareTo(b.id);
        });
      void diagnose(
        String reason, {
        double amount = 0,
        _CadenceFit? fit,
        double confidence = 0,
      }) => onDiagnostic?.call(
        RecurringDiagnostic(
          cluster: cluster,
          occurrences: items.length,
          reason: reason,
          amountScore: amount,
          intervalScore: fit?.score ?? 0,
          coverage: fit?.coverage ?? 0,
          confidence: confidence,
          frequency: fit?.frequency,
        ),
      );
      if (items.length < 2) {
        diagnose('insufficient_occurrences');
        continue;
      }
      final amounts = items.map((t) => t.amount.minorUnits).toList()..sort();
      final median = amounts[amounts.length ~/ 2];
      final spread = (amounts.last - amounts.first) / median;
      final amountScore = (1 - spread).clamp(0.0, 1.0);
      // Coherence, not equality: tariffs and FX may vary, unrelated purchases
      // at a marketplace must not be fused just because dates happen to match.
      if (amounts.last / amounts.first > 1.6) {
        diagnose('incoherent_amounts', amount: amountScore);
        continue;
      }
      _CadenceFit? fit;
      for (final frequency in [
        RecurrenceFrequency.weekly,
        RecurrenceFrequency.monthly,
        RecurrenceFrequency.quarterly,
        RecurrenceFrequency.yearly,
      ]) {
        final candidate = _fitCadence(items, frequency);
        if (candidate != null &&
            (fit == null ||
                candidate.score * candidate.coverage >
                    fit.score * fit.coverage)) {
          fit = candidate;
        }
      }
      if (fit == null) {
        diagnose('irregular_intervals', amount: amountScore);
        continue;
      }
      // One monthly interval can be useful as a *tentative* forecast. Two
      // weekly purchases or widely spaced annual purchases are not enough.
      if (items.length == 2 && fit.frequency != RecurrenceFrequency.monthly) {
        diagnose('insufficient_occurrences', amount: amountScore, fit: fit);
        continue;
      }
      var confidence =
          0.96 *
          (0.45 * fit.score +
                  0.20 * amountScore +
                  0.20 * math.min(items.length / 4, 1) +
                  0.15 * fit.coverage)
              .clamp(0.0, 1.0);
      if (items.length == 2) confidence = math.min(confidence, 0.70);
      if (confidence < 0.65) {
        diagnose(
          'weak_pattern',
          amount: amountScore,
          fit: fit,
          confidence: confidence,
        );
        continue;
      }
      final last = items.last;
      diagnose(
        items.length == 2 ? 'tentative' : 'detected',
        amount: amountScore,
        fit: fit,
        confidence: confidence,
      );
      streams.add(
        RecurringStream(
          id:
              'rec-${last.entityId}-${entry.key.merchant}-'
              '${last.amount.currency.toLowerCase()}-${fit.frequency.name}',
          entityId: last.entityId,
          merchantKey: entry.key.merchant,
          title: _resolveMerchant(last.merchantName!).name,
          typicalAmount: last.amount,
          frequency: fit.frequency,
          nextExpectedAt: _advance(last.occurredAt, fit.frequency),
          confidence: confidence,
          transactionIds: items.map((item) => item.id).toList(),
        ),
      );
    }
    return streams;
  }

  _MerchantResolution _resolveMerchant(String source) {
    final key = _key(source);
    // Merchant aliases only, NOT a subscription whitelist: these names still
    // need the same temporal/amount evidence as any previously unknown service.
    final unwrapped = key.replaceFirst(RegExp(r'^ym '), '');
    if (RegExp(r'^(yandex|яндекс) (plus|плюс)$').hasMatch(unwrapped)) {
      return const _MerchantResolution('mrc-yandex-plus', 'Яндекс Плюс', 0.98);
    }
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

typedef _RecurringKey = ({String entityId, String merchant, String currency});

/// Opt-in diagnostics, deliberately without names, account IDs or raw text.
/// Cluster numbers are local to one invocation; nothing is logged or persisted.
class RecurringDiagnostic {
  const RecurringDiagnostic({
    required this.reason,
    this.cluster = 0,
    this.occurrences = 0,
    this.amountScore = 0,
    this.intervalScore = 0,
    this.coverage = 0,
    this.confidence = 0,
    this.frequency,
  });
  final String reason;
  final int cluster, occurrences;
  final double amountScore, intervalScore, coverage, confidence;
  final RecurrenceFrequency? frequency;
}

String? _ineligibleReason(CanonicalTransaction t) {
  if (t.status != CanonicalTransactionStatus.posted) return 'not_posted';
  if (t.eventType != FinancialEventType.observed) return 'not_observed';
  if (t.direction != FinancialDirection.outflow || t.amount.minorUnits <= 0) {
    return 'not_expense';
  }
  if (t.tags.any(
    (tag) => const {
      'refund',
      'legacy-type-refund',
      'sber-status-refund',
      'status-refund',
    }.contains(tag),
  )) {
    return 'refund';
  }
  // A transfer to a landlord/seller can be a real external expense. Match the
  // canonical cash-flow policy: exclude proven own-account movements, not all
  // rows carrying transfer metadata (Sber attaches it to outgoing SBP too).
  if (t.tags.contains('qesto-internal-transfer') ||
      t.tags.contains('legacy-type-savingsTransfer')) {
    return 'transfer';
  }
  if (t.tags.contains('qesto-non-cash') ||
      t.tags.contains('sber-loyalty-only')) {
    return 'non_cash';
  }
  if (t.tags.contains('excel-period-aggregate')) return 'period_aggregate';
  if (t.tags.contains('legacy-type-investment')) return 'investment';
  if (t.tags.contains('qesto-potential-duplicate')) return 'possible_duplicate';
  if (t.tags.contains('qesto-unconfirmed')) return 'unconfirmed';
  return null;
}

class _CadenceFit {
  const _CadenceFit(this.frequency, this.score, this.coverage);
  final RecurrenceFrequency frequency;
  final double score, coverage;
}

_CadenceFit? _fitCadence(
  List<CanonicalTransaction> items,
  RecurrenceFrequency frequency,
) {
  final tolerance = switch (frequency) {
    RecurrenceFrequency.weekly => 1,
    RecurrenceFrequency.monthly => 4,
    RecurrenceFrequency.quarterly => 7,
    RecurrenceFrequency.yearly => 14,
    RecurrenceFrequency.irregular => 0,
  };
  var cycles = 0;
  var direct = 0;
  var error = 0.0;
  for (var i = 1; i < items.length; i++) {
    final previous = _calendarDay(items[i - 1].occurredAt);
    final current = _calendarDay(items[i].occurredAt);
    if (!current.isAfter(previous)) return null;
    var matched = false;
    // One missing period is tolerated only with at least four observations.
    final maxGap = items.length >= 4 ? 2 : 1;
    for (var gap = 1; gap <= maxGap; gap++) {
      final expected = _advance(previous, frequency, gap);
      final delta = current.difference(expected).inDays.abs();
      if (delta > tolerance) continue;
      cycles += gap;
      if (gap == 1) direct++;
      error += delta / (tolerance + 1);
      matched = true;
      break;
    }
    if (!matched) return null;
  }
  final coverage = (items.length - 1) / cycles;
  if (direct == 0 || coverage < 0.65) return null;
  return _CadenceFit(frequency, 1 - 0.3 * error / (items.length - 1), coverage);
}

DateTime _calendarDay(DateTime t) => DateTime.utc(t.year, t.month, t.day);

DateTime _advance(
  DateTime value,
  RecurrenceFrequency frequency, [
  int count = 1,
]) {
  if (frequency == RecurrenceFrequency.weekly) {
    return value.add(Duration(days: 7 * count));
  }
  final months = switch (frequency) {
    RecurrenceFrequency.monthly => count,
    RecurrenceFrequency.quarterly => 3 * count,
    RecurrenceFrequency.yearly => 12 * count,
    _ => throw ArgumentError('Unsupported recurring cadence'),
  };
  return _sameTimeNextMonth(value, months);
}

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

DateTime _sameTimeNextMonth(DateTime value, [int months = 1]) {
  final target = DateTime.utc(value.year, value.month + months);
  final nextYear = target.year;
  final nextMonth = target.month;
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
