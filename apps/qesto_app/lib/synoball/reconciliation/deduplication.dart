import '../core/models.dart';

class DeduplicationMatch {
  const DeduplicationMatch({
    required this.transaction,
    required this.score,
    required this.reasons,
  });

  final CanonicalTransaction transaction;
  final double score;
  final List<String> reasons;
}

/// Reconciles observations of the same real-world payment without changing
/// Synoball's canonical transaction schema.
///
/// Stable source identifiers always win. Fuzzy reconciliation is deliberately
/// limited to different source types and requires an exact monetary identity,
/// a compatible time window and a recognisable merchant. This prevents two
/// equal purchases made close together from being silently collapsed.
class TransactionDeduplicator {
  const TransactionDeduplicator({this.defaultThreshold = 0.84});

  final double defaultThreshold;

  DeduplicationMatch? findMatch({
    required TransactionCandidate candidate,
    required SynoballSourceType sourceType,
    required Iterable<CanonicalTransaction> transactions,
    required Iterable<SourceEvidence> evidence,
  }) {
    final active = transactions
        .where(
          (item) =>
              item.status != CanonicalTransactionStatus.deleted &&
              item.entityId == candidate.entityId,
        )
        .toList(growable: false);
    final evidenceList = evidence.toList(growable: false);

    if (candidate.canonicalId != null) {
      for (final transaction in active) {
        if (transaction.id == candidate.canonicalId) {
          return DeduplicationMatch(
            transaction: transaction,
            score: 1,
            reasons: const ['canonical_id'],
          );
        }
      }
    }

    final providerId = candidate.providerTransactionId;
    if (providerId != null && providerId.isNotEmpty) {
      for (final item in evidenceList) {
        // Provider identifiers are scoped to their adapter/source. A receipt
        // fiscal key and a bank transaction id may legally have equal text.
        if (item.sourceType != sourceType ||
            item.providerTransactionId != providerId) {
          continue;
        }
        final transaction = active
            .where((value) => value.id == item.transactionId)
            .firstOrNull;
        if (transaction != null) {
          return DeduplicationMatch(
            transaction: transaction,
            score: 1,
            reasons: const ['provider_transaction_id'],
          );
        }
      }
    }

    // Explicit user input and legacy migration must remain distinct. A later
    // receipt, notification or statement can still enrich such a transaction.
    if (sourceType == SynoballSourceType.legacy ||
        sourceType == SynoballSourceType.manual ||
        sourceType == SynoballSourceType.manualVoice ||
        sourceType == SynoballSourceType.modelInference) {
      return null;
    }

    DeduplicationMatch? best;
    for (final transaction in active) {
      final transactionEvidence = evidenceList
          .where((item) => item.transactionId == transaction.id)
          .toList(growable: false);

      // One fuzzy observation per source. Re-imports are reconciled through a
      // stable provider/canonical id above; otherwise repeating purchases from
      // the same bank or notification channel must remain separate.
      if (transactionEvidence.any((item) => item.sourceType == sourceType)) {
        continue;
      }

      final scored = _score(
        candidate,
        transaction,
        sourceType,
        transactionEvidence.map((item) => item.sourceType).toSet(),
      );
      if (scored != null && (best == null || scored.score > best.score)) {
        best = scored;
      }
    }
    return best != null && best.score >= defaultThreshold ? best : null;
  }

  DeduplicationMatch? _score(
    TransactionCandidate candidate,
    CanonicalTransaction transaction,
    SynoballSourceType incomingSource,
    Set<SynoballSourceType> existingSources,
  ) {
    if (candidate.amount.minorUnits != transaction.amount.minorUnits ||
        candidate.amount.currency != transaction.amount.currency ||
        candidate.direction != transaction.direction) {
      return null;
    }

    final incomingMerchant = _merchantKey(
      candidate.merchantGuess ?? candidate.normalizedDescription ?? '',
    );
    final knownMerchant = _merchantKey(
      transaction.merchantName ?? transaction.normalizedDescription,
    );
    final merchantSimilarity = _merchantSimilarity(
      incomingMerchant,
      knownMerchant,
    );
    if (merchantSimilarity < 0.5) return null;

    final minutes = candidate.occurredAt
        .difference(transaction.occurredAt)
        .inMinutes
        .abs();
    final hasDateOnlySource =
        incomingSource == SynoballSourceType.statement ||
        existingSources.contains(SynoballSourceType.statement);
    final allowedMinutes = hasDateOnlySource ? 48 * 60 : 24 * 60;
    if (minutes > allowedMinutes) return null;

    var score = 0.6; // exact amount + currency + direction
    final reasons = <String>['amount', 'currency', 'direction', 'cross_source'];

    if (merchantSimilarity >= 0.85) {
      score += 0.2;
      reasons.add('merchant_strong');
    } else if (merchantSimilarity >= 0.65) {
      score += 0.16;
      reasons.add('merchant');
    } else {
      score += 0.12;
      reasons.add('merchant_partial');
    }

    if (minutes <= 30) {
      score += 0.2;
      reasons.add('time_30m');
    } else if (_sameLocalDay(candidate.occurredAt, transaction.occurredAt)) {
      score += 0.14;
      reasons.add('same_day');
    } else {
      score += 0.1;
      reasons.add('posting_window');
    }

    score += 0.02;
    if (candidate.accountId == transaction.accountId) {
      score += 0.04;
      reasons.add('account');
    }

    return DeduplicationMatch(
      transaction: transaction,
      score: score.clamp(0, 1).toDouble(),
      reasons: reasons,
    );
  }
}

bool _sameLocalDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _merchantKey(String value) {
  final normalized = value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(
        RegExp(
          r'\b(ооо|оао|пао|зао|ао|ип|ooo|oao|pao|zao|moscow|москва|rus|russia)\b',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .replaceAll(RegExp(r'\b\d{3,}\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.contains('pyaterochka') ||
      normalized.contains('пятерочка') ||
      normalized == '5ka') {
    return 'пятерочка';
  }
  if (normalized.contains('perekrestok') ||
      normalized.contains('перекресток')) {
    return 'перекресток';
  }
  if (normalized.contains('yandex go') ||
      normalized.contains('yandexgo') ||
      normalized.contains('яндекс go')) {
    return 'яндекс go';
  }
  if (normalized.contains('burger king') ||
      normalized.contains('burgerrus') ||
      normalized.contains('бургер кинг')) {
    return 'burger king';
  }
  return normalized;
}

double _merchantSimilarity(String left, String right) {
  if (left.isEmpty || right.isEmpty) return 0;
  if (left == right || left.contains(right) || right.contains(left)) return 1;

  final leftTokens = left.split(' ').where((item) => item.isNotEmpty).toSet();
  final rightTokens = right.split(' ').where((item) => item.isNotEmpty).toSet();
  final intersection = leftTokens.intersection(rightTokens).length;
  final union = leftTokens.union(rightTokens).length;
  final tokenScore = union == 0 ? 0.0 : intersection / union;
  final characterScore = _diceCoefficient(
    left.replaceAll(' ', ''),
    right.replaceAll(' ', ''),
  );
  return tokenScore > characterScore ? tokenScore : characterScore;
}

double _diceCoefficient(String left, String right) {
  if (left.length < 2 || right.length < 2) return left == right ? 1 : 0;
  final leftPairs = <String, int>{};
  for (var index = 0; index < left.length - 1; index++) {
    final pair = left.substring(index, index + 2);
    leftPairs[pair] = (leftPairs[pair] ?? 0) + 1;
  }
  var intersection = 0;
  for (var index = 0; index < right.length - 1; index++) {
    final pair = right.substring(index, index + 2);
    final remaining = leftPairs[pair] ?? 0;
    if (remaining <= 0) continue;
    intersection += 1;
    leftPairs[pair] = remaining - 1;
  }
  return (2 * intersection) / (left.length + right.length - 2);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
