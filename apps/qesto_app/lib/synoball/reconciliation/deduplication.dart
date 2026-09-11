import '../core/models.dart';

/// Safe, non-financial outcome. The caller retains this observation for review.
class ReconciliationConflict implements Exception {
  const ReconciliationConflict(this.reason);
  final String reason;
}

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

  /// Reserve cross-source matches against the state BEFORE this batch. Two
  /// different observations cannot claim one payment merely by arriving first.
  Map<String, String> batchConflicts({
    required Iterable<TransactionCandidate> candidates,
    required SynoballSourceType sourceType,
    required Iterable<CanonicalTransaction> transactions,
    required Iterable<SourceEvidence> evidence,
    Iterable<IngestionRecord> ingestionRecords = const [],
    Iterable<SynoballAccount> accounts = const [],
    Iterable<TransactionCandidate> sourceCandidates = const [],
  }) {
    final conflicts = <String, String>{};
    final claims = <String, List<(TransactionCandidate, DeduplicationMatch)>>{};
    for (final candidate in candidates.where((c) => !c.requiresConfirmation)) {
      try {
        final match = findMatch(
          candidate: candidate,
          sourceType: sourceType,
          transactions: transactions,
          evidence: evidence,
          ingestionRecords: ingestionRecords,
          accounts: accounts,
          sourceCandidates: sourceCandidates,
        );
        if (match != null) {
          claims.putIfAbsent(match.transaction.id, () => []).add((
            candidate,
            match,
          ));
        }
      } on ReconciliationConflict catch (error) {
        conflicts[candidate.id] = error.reason;
      }
    }
    for (final group in claims.values.where((g) => g.length > 1)) {
      // Repeated delivery of the same stable source observation is legitimate.
      final identities = group.map((g) => g.$1.providerTransactionId).toSet();
      if (identities.length == 1 && identities.single?.isNotEmpty == true) {
        continue;
      }
      for (final (candidate, match) in group) {
        if (match.reasons.contains('cross_source')) {
          conflicts[candidate.id] = 'ambiguous_batch_cross_source';
        }
      }
    }
    return conflicts;
  }

  DeduplicationMatch? findMatch({
    required TransactionCandidate candidate,
    required SynoballSourceType sourceType,
    required Iterable<CanonicalTransaction> transactions,
    required Iterable<SourceEvidence> evidence,
    Iterable<IngestionRecord> ingestionRecords = const [],
    Iterable<SynoballAccount> accounts = const [],
    Iterable<TransactionCandidate> sourceCandidates = const [],
  }) {
    final records = {for (final record in ingestionRecords) record.id: record};
    final observationsByIdentity =
        <(String, String?), List<TransactionCandidate>>{};
    for (final observation in sourceCandidates) {
      if (observation.entityId == candidate.entityId &&
          (observation.status == CandidateStatus.confirmed ||
              observation.status == CandidateStatus.merged)) {
        observationsByIdentity
            .putIfAbsent((
              observation.ingestionRecordId,
              observation.providerTransactionId,
            ), () => [])
            .add(observation);
      }
    }
    final virtualAccounts = {
      for (final account in accounts)
        if (account.entityId == candidate.entityId && account.isVirtual)
          account.id,
    };
    bool compatibleAccount(CanonicalTransaction transaction) =>
        candidate.accountId == transaction.accountId ||
        virtualAccounts.contains(candidate.accountId) ||
        virtualAccounts.contains(transaction.accountId);
    bool compatibleScope(SourceEvidence item) {
      final incoming = records[candidate.ingestionRecordId];
      final existing = records[item.ingestionRecordId];
      if (incoming == null || existing == null) return true;
      return !(incoming.connectionId != null &&
              existing.connectionId != null &&
              incoming.connectionId != existing.connectionId) &&
          !(incoming.institutionId != null &&
              existing.institutionId != null &&
              incoming.institutionId != existing.institutionId);
    }

    final activeById = <String, CanonicalTransaction>{};
    for (final transaction in transactions) {
      // Tombstones participate in identity checks. Otherwise the same provider
      // delivery would create a new active transaction after a user deletion.
      if (transaction.entityId == candidate.entityId) {
        activeById[transaction.id] = transaction;
      }
    }

    if (candidate.canonicalId != null) {
      final transaction = activeById[candidate.canonicalId];
      if (transaction != null) {
        if (!compatibleAccount(transaction) ||
            candidate.amount.currency != transaction.amount.currency ||
            evidence.any(
              (item) =>
                  item.transactionId == transaction.id &&
                  !compatibleScope(item),
            )) {
          throw const ReconciliationConflict('canonical_identity_conflict');
        }
        return DeduplicationMatch(
          transaction: transaction,
          score: 1,
          reasons: const ['canonical_id'],
        );
      }
    }

    final evidenceByTransactionId = <String, List<SourceEvidence>>{};
    final providerMatches = <String, CanonicalTransaction>{};
    final providerId = candidate.providerTransactionId;
    for (final item in evidence) {
      evidenceByTransactionId
          .putIfAbsent(item.transactionId, () => <SourceEvidence>[])
          .add(item);
      // Provider identifiers are scoped to their adapter/source. A receipt
      // fiscal key and a bank transaction id may legally have equal text.
      if (providerId != null &&
          providerId.isNotEmpty &&
          item.sourceType == sourceType &&
          item.providerTransactionId == providerId &&
          activeById.containsKey(item.transactionId) &&
          compatibleAccount(activeById[item.transactionId]!) &&
          candidate.amount.currency ==
              activeById[item.transactionId]!.amount.currency &&
          compatibleScope(item)) {
        providerMatches[item.transactionId] = activeById[item.transactionId]!;
      }
    }
    if (providerMatches.length > 1) {
      throw const ReconciliationConflict('ambiguous_provider_identity');
    }
    if (providerMatches.isNotEmpty) {
      return DeduplicationMatch(
        transaction: providerMatches.values.single,
        score: 1,
        reasons: const ['provider_transaction_id'],
      );
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
    var ambiguous = false;
    final incomingMerchant = _merchantKey(
      candidate.merchantGuess ?? candidate.normalizedDescription ?? '',
    );
    for (final transaction in activeById.values) {
      if (!compatibleAccount(transaction)) continue;
      final transactionEvidence =
          evidenceByTransactionId[transaction.id] ?? const <SourceEvidence>[];
      if (transaction.status != CanonicalTransactionStatus.deleted &&
          candidate.tags.contains('excel-period-aggregate') !=
              transaction.tags.contains('excel-period-aggregate') &&
          candidate.amount.currency == transaction.amount.currency &&
          candidate.direction == transaction.direction &&
          candidate.occurredAt.year == transaction.occurredAt.year &&
          candidate.occurredAt.month == transaction.occurredAt.month &&
          candidate.categoryGuess != null &&
          candidate.categoryGuess != 'other' &&
          candidate.categoryGuess == transaction.effectiveCategory &&
          !transactionEvidence.any((item) => !compatibleScope(item))) {
        throw const ReconciliationConflict('aggregate_detail_overlap');
      }

      // One fuzzy observation per source. Re-imports are reconciled through a
      // stable provider/canonical id above; otherwise repeating purchases from
      // the same bank or notification channel must remain separate.
      if (transaction.status != CanonicalTransactionStatus.deleted &&
          transactionEvidence.any((item) => item.sourceType == sourceType)) {
        continue;
      }
      if (transactionEvidence.any((item) => !compatibleScope(item))) continue;

      var scored = _score(
        candidate,
        incomingMerchant,
        transaction,
        sourceType,
        transactionEvidence.map((item) => item.sourceType).toSet(),
      );
      // User edits are the display truth, not a rewrite of bank evidence.
      // Match against accepted source facts as well, without overwriting locks.
      for (final observation in transactionEvidence.expand(
        (e) =>
            observationsByIdentity[(
              e.ingestionRecordId,
              e.providerTransactionId,
            )] ??
            <TransactionCandidate>[],
      )) {
        if (observation.entityId != candidate.entityId ||
            (observation.status != CandidateStatus.confirmed &&
                observation.status != CandidateStatus.merged) ||
            observation.providerTransactionId == null ||
            !transactionEvidence.any(
              (e) =>
                  e.ingestionRecordId == observation.ingestionRecordId &&
                  e.providerTransactionId == observation.providerTransactionId,
            )) {
          continue;
        }
        final original = transaction.copyWith(
          amount: observation.amount,
          direction: observation.direction,
          occurredAt: observation.occurredAt,
          normalizedDescription:
              observation.normalizedDescription ?? observation.rawDescription,
          merchantName:
              observation.merchantGuess ??
              observation.normalizedDescription ??
              observation.rawDescription,
        );
        final fromSource = _score(
          candidate,
          incomingMerchant,
          original,
          sourceType,
          transactionEvidence.map((e) => e.sourceType).toSet(),
        );
        if (fromSource != null &&
            (scored == null || fromSource.score > scored.score)) {
          scored = DeduplicationMatch(
            transaction: transaction,
            score: fromSource.score,
            reasons: [...fromSource.reasons, 'preserved_source_fact'],
          );
        }
      }
      if (scored == null || scored.score < defaultThreshold) continue;
      if (best == null || scored.score > best.score + 0.000001) {
        best = scored;
        ambiguous = false;
      } else if ((scored.score - best.score).abs() <= 0.000001) {
        ambiguous = true;
      }
    }
    if (ambiguous) throw const ReconciliationConflict('ambiguous_cross_source');
    if (best?.transaction.status == CanonicalTransactionStatus.deleted) {
      // Similarity alone cannot prove a deletion applies to another purchase.
      // Keep it for review, neither resurrecting nor silently discarding it.
      throw const ReconciliationConflict('possible_deleted_transaction');
    }
    return best != null && best.score >= defaultThreshold ? best : null;
  }

  DeduplicationMatch? _score(
    TransactionCandidate candidate,
    String incomingMerchant,
    CanonicalTransaction transaction,
    SynoballSourceType incomingSource,
    Set<SynoballSourceType> existingSources,
  ) {
    if (candidate.amount.minorUnits != transaction.amount.minorUnits ||
        candidate.amount.currency != transaction.amount.currency ||
        candidate.direction != transaction.direction) {
      return null;
    }

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
        incomingSource == SynoballSourceType.bankScreenshot ||
        existingSources.contains(SynoballSourceType.statement) ||
        existingSources.contains(SynoballSourceType.bankScreenshot);
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
      .replaceAll(_businessFormPattern, ' ')
      .replaceAll(_nonMerchantCharacterPattern, ' ')
      .replaceAll(_longNumberPattern, ' ')
      .replaceAll(_whitespacePattern, ' ')
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

final RegExp _businessFormPattern = RegExp(
  r'\b(ооо|оао|пао|зао|ао|ип|ooo|oao|pao|zao|moscow|москва|rus|russia)\b',
);
final RegExp _nonMerchantCharacterPattern = RegExp(r'[^a-zа-я0-9]+');
final RegExp _longNumberPattern = RegExp(r'\b\d{3,}\b');
final RegExp _whitespacePattern = RegExp(r'\s+');
