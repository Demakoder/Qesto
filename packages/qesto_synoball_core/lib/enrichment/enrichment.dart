import 'dart:math' as math;

import '../core/models.dart';
import 'category_policy.dart';
import 'recurrence_calendar.dart';

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

  /// The same alias resolution used for transaction enrichment and recurring
  /// detection. Upcoming projections use this only to suppress obvious manual
  /// versus inferred duplicates, never as proof of periodicity.
  String normalizedMerchantKey(String source) =>
      _key(_resolveMerchant(source).name);

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
      final whole = _recurringCandidate(items);
      // A merchant is an entity, not a subscription. Try distinct temporal
      // chains only when the whole merchant history is not one sound series.
      final candidates = whole == null
          ? _splitRecurringCandidates(items)
          : [whole];
      if (candidates.isEmpty) {
        final amounts = items.map((t) => t.amount.minorUnits).toList()..sort();
        final median = amounts[amounts.length ~/ 2];
        final amountScore = (1 - (amounts.last - amounts.first) / median).clamp(
          0.0,
          1.0,
        );
        diagnose(
          amounts.last / amounts.first > 1.6
              ? 'incoherent_amounts'
              : 'irregular_intervals',
          amount: amountScore,
        );
        continue;
      }
      for (final candidate in candidates) {
        final chain = candidate.items;
        final fit = candidate.fit;
        final last = chain.last;
        onDiagnostic?.call(
          RecurringDiagnostic(
            cluster: cluster,
            occurrences: chain.length,
            reason: chain.length == 2 ? 'tentative' : 'detected',
            amountScore: candidate.amountScore,
            intervalScore: fit.score,
            coverage: fit.coverage,
            confidence: candidate.confidence,
            frequency: fit.frequency,
          ),
        );
        streams.add(
          RecurringStream(
            id:
                'rec-${last.entityId}-${entry.key.merchant}-'
                '${last.amount.currency.toLowerCase()}-${fit.frequency.name}'
                '${whole == null ? '-${chain.first.id}' : ''}',
            entityId: last.entityId,
            merchantKey: entry.key.merchant,
            title: _resolveMerchant(last.merchantName!).name,
            typicalAmount: Money(
              minorUnits: candidate.medianAmount,
              currency: last.amount.currency,
            ),
            frequency: fit.frequency,
            nextExpectedAt: advanceOccurrence(
              chain.first.occurredAt,
              fit.frequency,
              fit.cycles + 1,
            ),
            confidence: candidate.confidence,
            transactionIds: chain.map((item) => item.id).toList(),
          ),
        );
      }
    }
    return streams;
  }

  _MerchantResolution _resolveMerchant(String source) {
    final key = _key(source);
    // Merchant aliases only, NOT a subscription whitelist: these names still
    // need the same temporal/amount evidence as any previously unknown service.
    final unwrapped = key.replaceFirst(RegExp(r'^ym '), '');
    if (RegExp(
      r'^(yandex|яндекс)\s*(plus|плюс)(\s+moscow)?$',
    ).hasMatch(unwrapped)) {
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

const _recurringFrequencies = [
  RecurrenceFrequency.weekly,
  RecurrenceFrequency.biweekly,
  RecurrenceFrequency.monthly,
  RecurrenceFrequency.bimonthly,
  RecurrenceFrequency.quarterly,
  RecurrenceFrequency.halfYearly,
  RecurrenceFrequency.yearly,
];

class _RecurringCandidate {
  const _RecurringCandidate(
    this.items,
    this.fit,
    this.medianAmount,
    this.amountScore,
    this.confidence,
  );
  final List<CanonicalTransaction> items;
  final _CadenceFit fit;
  final int medianAmount;
  final double amountScore, confidence;
}

_RecurringCandidate? _recurringCandidate(List<CanonicalTransaction> items) {
  if (items.length < 2) return null;
  final amounts = items.map((t) => t.amount.minorUnits).toList()..sort();
  final median = amounts[amounts.length ~/ 2];
  final spread = (amounts.last - amounts.first) / median;
  final amountScore = (1 - spread).clamp(0.0, 1.0);
  // Amount coherence separates multiple products of the same merchant while
  // still allowing variable tariffs and household bills.
  if (amounts.last / amounts.first > 1.6) return null;
  _CadenceFit? fit;
  for (final frequency in _recurringFrequencies) {
    final candidate = _fitCadence(items, frequency);
    if (candidate != null &&
        (fit == null ||
            candidate.score * candidate.coverage > fit.score * fit.coverage)) {
      fit = candidate;
    }
  }
  if (fit == null) return null;
  // A single monthly interval is a *candidate*, never a confirmed expense.
  // Longer cadences need at least three observations to avoid false positives.
  if (items.length == 2 && fit.frequency != RecurrenceFrequency.monthly) {
    return null;
  }
  var confidence =
      0.96 *
      (0.45 * fit.score +
              0.20 * amountScore +
              0.20 * math.min(items.length / 4, 1) +
              0.15 * fit.coverage)
          .clamp(0.0, 1.0);
  if (items.length == 2) confidence = math.min(confidence, 0.70);
  if (confidence < 0.65) return null;
  return _RecurringCandidate(items, fit, median, amountScore, confidence);
}

List<_RecurringCandidate> _splitRecurringCandidates(
  List<CanonicalTransaction> items,
) {
  if (items.length < 4) return const [];
  // Splitting a large, noisy merchant history is both expensive and prone to
  // finding a coincidental cadence. A clean full-history stream was already
  // considered above; for a dense mixed history prefer no prediction.
  if (items.length > 96) return const [];
  // Two indistinguishable payments on one day may be separate purchases or an
  // unresolved duplicate. Do not silently discard one to manufacture cadence.
  for (var i = 1; i < items.length; i++) {
    if (_calendarDay(items[i - 1].occurredAt) ==
            _calendarDay(items[i].occurredAt) &&
        items[i - 1].amount.minorUnits == items[i].amount.minorUnits) {
      return const [];
    }
  }
  final remaining = <String, CanonicalTransaction>{
    for (final item in items) item.id: item,
  };
  final result = <_RecurringCandidate>[];
  while (remaining.length >= 3) {
    _RecurringCandidate? best;
    for (final anchor in remaining.values) {
      for (final frequency in _recurringFrequencies) {
        final chain = <CanonicalTransaction>[anchor];
        final lastDay = _calendarDay(items.last.occurredAt);
        for (var cycle = 1; cycle <= 240; cycle++) {
          final expected = _calendarDay(
            advanceOccurrence(anchor.occurredAt, frequency, cycle),
          );
          if (expected.difference(lastDay).inDays > _tolerance(frequency)) {
            break;
          }
          final matches =
              remaining.values.where((item) {
                if (chain.any((member) => member.id == item.id) ||
                    !item.occurredAt.isAfter(chain.last.occurredAt)) {
                  return false;
                }
                final ratio = item.amount.minorUnits / anchor.amount.minorUnits;
                return ratio >= 1 / 1.6 &&
                    ratio <= 1.6 &&
                    _calendarDay(
                          item.occurredAt,
                        ).difference(expected).inDays.abs() <=
                        _tolerance(frequency);
              }).toList()..sort((a, b) {
                final dateA = _calendarDay(
                  a.occurredAt,
                ).difference(expected).inDays.abs();
                final dateB = _calendarDay(
                  b.occurredAt,
                ).difference(expected).inDays.abs();
                if (dateA != dateB) return dateA.compareTo(dateB);
                return (a.amount.minorUnits - anchor.amount.minorUnits)
                    .abs()
                    .compareTo(
                      (b.amount.minorUnits - anchor.amount.minorUnits).abs(),
                    );
              });
          if (matches.isNotEmpty) chain.add(matches.first);
        }
        // A few weekly purchases inside one month often fit a cadence by
        // accident. Splitting a noisy merchant needs a longer independent
        // series; clean unsplit groups still confirm after three observations.
        final minimum =
            frequency == RecurrenceFrequency.weekly ||
                frequency == RecurrenceFrequency.biweekly
            ? 5
            : 3;
        if (chain.length < minimum) continue;
        final candidate = _recurringCandidate(chain);
        if (candidate != null &&
            (best == null ||
                candidate.items.length > best.items.length ||
                (candidate.items.length == best.items.length &&
                    candidate.confidence > best.confidence))) {
          best = candidate;
        }
      }
    }
    if (best == null) break;
    result.add(best);
    for (final item in best.items) {
      remaining.remove(item.id);
    }
  }
  return result;
}

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
  // Calendar coincidence is common for everyday purchases in imported
  // histories. These categories are open-ended consumption, not a contracted
  // bill; users can still plan a future grocery/cafe payment manually.
  final category =
      t.userCategoryOverride ?? t.synoballCategory ?? t.providerCategory;
  if (const {
    'groceries',
    'cafes',
    'transport',
    'fun',
    'entertainment',
    'shopping',
  }.contains(category)) {
    return 'everyday_spending';
  }
  return null;
}

class _CadenceFit {
  const _CadenceFit(this.frequency, this.score, this.coverage, this.cycles);
  final RecurrenceFrequency frequency;
  final double score, coverage;
  final int cycles;
}

int _tolerance(RecurrenceFrequency frequency) => switch (frequency) {
  RecurrenceFrequency.weekly => 1,
  RecurrenceFrequency.biweekly => 2,
  RecurrenceFrequency.monthly => 4,
  RecurrenceFrequency.bimonthly => 5,
  RecurrenceFrequency.quarterly => 7,
  RecurrenceFrequency.halfYearly => 10,
  RecurrenceFrequency.yearly => 14,
  RecurrenceFrequency.irregular => 0,
};

_CadenceFit? _fitCadence(
  List<CanonicalTransaction> items,
  RecurrenceFrequency frequency,
) {
  final tolerance = _tolerance(frequency);
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
      final expected = advanceOccurrence(previous, frequency, gap);
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
  return _CadenceFit(
    frequency,
    1 - 0.3 * error / (items.length - 1),
    coverage,
    cycles,
  );
}

DateTime _calendarDay(DateTime t) => DateTime.utc(t.year, t.month, t.day);

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
