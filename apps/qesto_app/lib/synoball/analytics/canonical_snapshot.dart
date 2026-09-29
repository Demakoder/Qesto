import 'dart:convert';
import '../core/models.dart';
import '../reconciliation/deduplication.dart';
import '../reconciliation/bank_web_identity_quality.dart';

/// Read-only canonical resolution shared by financial consumers. No LLM, no
/// storage mutation, no raw payload parsing. Similarity never proves identity.
class CanonicalSnapshot {
  CanonicalSnapshot({
    required Map<String, CanonicalTransaction> transactions,
    required Map<String, String> aliases,
    required Map<String, CanonicalOperationFacts> facts,
    required Map<String, CanonicalAccountFacts> accounts,
    required this.historyCompleteness,
    this.verifiedRanges = const [],
  }) : transactions = Map.unmodifiable(transactions),
       aliases = Map.unmodifiable(aliases),
       facts = Map.unmodifiable(facts),
       accounts = Map.unmodifiable(accounts);
  final Map<String, CanonicalTransaction> transactions;
  final Map<String, String> aliases;
  final Map<String, CanonicalOperationFacts> facts;
  final Map<String, CanonicalAccountFacts> accounts;
  final String historyCompleteness;
  final List<CanonicalVerifiedRange> verifiedRanges;

  /// Discard source text before the export snapshot crosses an async boundary.
  CanonicalSnapshot metadataOnly() => CanonicalSnapshot(
    transactions: const {},
    aliases: aliases,
    facts: facts,
    accounts: accounts,
    historyCompleteness: historyCompleteness,
    verifiedRanges: verifiedRanges,
  );
  String historyFor(DateTime from, DateTime to) =>
      accounts.isNotEmpty &&
          accounts.keys.every(
            (id) => verifiedRanges.any(
              (r) =>
                  r.accountId == id &&
                  !r.start.isAfter(from) &&
                  !r.end.isBefore(DateTime(to.year, to.month, to.day)),
            ),
          )
      ? 'complete'
      : 'not_verified';
}

class CanonicalVerifiedRange {
  const CanonicalVerifiedRange(this.accountId, this.start, this.end);
  final String accountId;
  final DateTime start, end;
}

class CanonicalAccountFacts {
  const CanonicalAccountFacts({
    required this.type,
    required this.subtype,
    required this.balanceNature,
    required this.resolutionStatus,
    required this.balanceStatus,
    this.balanceCapturedAt,
  });
  final String type, subtype, balanceNature, resolutionStatus, balanceStatus;
  final DateTime? balanceCapturedAt;
}

class CanonicalOperationFacts {
  CanonicalOperationFacts({
    required Iterable<String> sourceTypes,
    required this.evidenceCount,
    required this.merged,
    required this.deduplicationStatus,
    this.duplicateGroupId,
    this.deduplicationConfidence,
    required this.timePrecision,
    required this.categorySource,
    required Map<String, double> confidence,
    required Iterable<String> userEditedFields,
    this.refundOriginalId,
    this.refundStatus = 'unmatched',
    this.transferId,
    this.counterpartyAccountId,
  }) : sourceTypes = List.unmodifiable(sourceTypes),
       confidence = Map.unmodifiable(confidence),
       userEditedFields = List.unmodifiable(userEditedFields);
  final List<String> sourceTypes, userEditedFields;
  final int evidenceCount;
  final bool merged;
  final String deduplicationStatus, timePrecision, categorySource;
  final String? duplicateGroupId,
      refundOriginalId,
      transferId,
      counterpartyAccountId;
  final String refundStatus;
  final double? deduplicationConfidence;
  final Map<String, double> confidence;
}

class CanonicalSnapshotResolver {
  const CanonicalSnapshotResolver();

  CanonicalSnapshot resolve(
    SynoballState state,
    String entityId, {
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    final accounts = {
      for (final a in state.accounts)
        if (a.entityId == entityId) a.id: a,
    };
    final rows = {
      for (final t in state.transactions)
        if (t.entityId == entityId &&
            t.status == CanonicalTransactionStatus.posted &&
            t.eventType == FinancialEventType.observed &&
            !t.tags.any(
              const {
                'qesto-unconfirmed',
                'qesto-non-cash',
                'sber-loyalty-only',
                'status-cancelled',
                'sber-status-cancelled',
                'status-pending',
                'sber-status-pending',
              }.contains,
            ))
          t.id: t,
    };
    final records = {
      for (final r in state.ingestionRecords)
        if (r.entityId == entityId) r.id: r,
    };
    final evidence = <String, List<SourceEvidence>>{};
    for (final e in state.evidence) {
      if (rows.containsKey(e.transactionId)) {
        evidence.putIfAbsent(e.transactionId, () => []).add(e);
      }
    }
    final parent = {for (final id in rows.keys) id: id};
    String root(String id) {
      var result = id;
      while (parent[result] != result) {
        result = parent[result]!;
      }
      return result;
    }

    final uncertain = <(String, String), double?>{};
    final identities = <String, Set<String>>{};
    for (final list in evidence.values) {
      for (final e in list) {
        final record = records[e.ingestionRecordId];
        final account = accounts[rows[e.transactionId]!.accountId];
        // An unscoped provider key is not proof across banks or profiles.
        final bank = record?.institutionId ?? account?.institutionId;
        final connection = record?.connectionId ?? account?.connectionId;
        if (e.providerTransactionId?.isNotEmpty != true ||
            (bank == null && connection == null) ||
            record == null) {
          continue;
        }
        final key = jsonEncode([
          e.sourceType.name,
          bank,
          connection,
          e.providerTransactionId,
        ]);
        identities.putIfAbsent(key, () => {}).add(e.transactionId);
      }
    }
    bool compatible(CanonicalTransaction a, CanonicalTransaction b) {
      final aa = accounts[a.accountId], ab = accounts[b.accountId];
      final accountCompatible =
          a.accountId == b.accountId ||
          aa?.isVirtual == true ||
          ab?.isVirtual == true;
      final locksA = _userFields(a), locksB = _userFields(b);
      // Conflicting manual edits require review rather than a winner heuristic.
      final conflictingEdits =
          locksA.isNotEmpty &&
          locksB.isNotEmpty &&
          (a.effectiveCategory != b.effectiveCategory ||
              a.normalizedDescription != b.normalizedDescription ||
              a.accountId != b.accountId);
      return accountCompatible &&
          !conflictingEdits &&
          _sameMoney(a.amount, b.amount) &&
          a.direction == b.direction &&
          _sameDay(a.occurredAt, b.occurredAt) &&
          a.tags.contains('refund') == b.tags.contains('refund') &&
          a.tags.contains('qesto-internal-transfer') ==
              b.tags.contains('qesto-internal-transfer');
    }

    final conflictedIdentities = <String>{};
    for (final ids in identities.values.where((g) => g.length > 1)) {
      final roots = ids.map(root).toSet();
      final list = rows.keys.where((id) => roots.contains(root(id))).toList()
        ..sort();
      // Validate the whole group before union; no unsafe transitive bridge.
      var safe = !list.any(conflictedIdentities.contains);
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          if (!compatible(rows[list[i]]!, rows[list[j]]!)) safe = false;
        }
      }
      for (var i = 1; i < list.length; i++) {
        if (safe) {
          parent[root(list[i])] = root(list.first);
        } else {
          uncertain[(list.first, list[i])] = null;
        }
      }
      if (!safe) {
        // Roll back tentative unions in a conflicting identity component.
        // Otherwise input order would choose which real account wins.
        for (final id in list) {
          parent[id] = id;
        }
        conflictedIdentities.addAll(list);
      }
    }
    final groups = <String, List<CanonicalTransaction>>{};
    for (final t in rows.values) {
      groups.putIfAbsent(root(t.id), () => []).add(t);
    }
    final canonical = <String, CanonicalTransaction>{};
    final aliases = <String, String>{};
    final mergedEvidence = <String, List<SourceEvidence>>{};
    final groupSizes = <String, int>{};
    for (final group in groups.values) {
      group.sort((a, b) {
        final order = a.createdAt.compareTo(b.createdAt);
        return order == 0 ? a.id.compareTo(b.id) : order;
      });
      // Keep the earliest canonical identity, resolving fields before export.
      final first = group.first;
      var chosen = first;
      final edited = group.where((r) => _userFields(r).isNotEmpty);
      if (edited.length == 1) chosen = edited.single;
      final realAccounts = group
          .map((t) => t.accountId)
          .where((id) => accounts[id]?.isVirtual == false)
          .toSet();
      final resolved = first.copyWith(
        accountId:
            !chosen.tags.contains('user-field:account') &&
                realAccounts.length == 1
            ? realAccounts.single
            : chosen.accountId,
        synoballCategory: chosen.synoballCategory,
        userCategoryOverride: chosen.userCategoryOverride,
        rawDescription: chosen.rawDescription,
        normalizedDescription: chosen.normalizedDescription,
        merchantName: chosen.merchantName,
        occurredAt: chosen.occurredAt,
        categoryConfidence: chosen.categoryConfidence,
        transferDirection: chosen.transferDirection,
        clearTransferDirection: chosen.transferDirection == null,
        tags: group.expand((t) => t.tags).toSet().toList(),
      );
      canonical[first.id] = resolved;
      groupSizes[first.id] = group.length;
      for (final t in group) {
        aliases[t.id] = first.id;
      }
      final observations = <String, SourceEvidence>{};
      for (final e in group.expand(
        (t) => evidence[t.id] ?? <SourceEvidence>[],
      )) {
        // Re-delivery of the same provider observation is not another source.
        final key = jsonEncode([
          e.sourceType.name,
          records[e.ingestionRecordId]?.institutionId,
          records[e.ingestionRecordId]?.connectionId,
          e.providerTransactionId ?? e.id,
        ]);
        observations[key] = e;
      }
      mergedEvidence[first.id] = observations.values.toList();
    }

    // Existing Synoball scoring is used only to FLAG, never merge, old ambiguous
    // records. Same-source repeated purchases cannot claim each other.
    final buckets =
        <(int, String, FinancialDirection), List<CanonicalTransaction>>{};
    for (final t in canonical.values) {
      if (mergedEvidence[t.id]!.isNotEmpty) {
        buckets
            .putIfAbsent((
              t.amount.minorUnits,
              t.amount.currency,
              t.direction,
            ), () => [])
            .add(t);
      }
    }
    for (final bucket in buckets.values.where((b) => b.length > 1)) {
      final kinds = bucket
          .expand((t) => mergedEvidence[t.id]!)
          .map((e) => e.sourceType)
          .toSet();
      if (kinds.length <= 1) continue;
      final byDay = <int, List<CanonicalTransaction>>{};
      for (final t in bucket) {
        byDay.putIfAbsent(_dayNumber(t.occurredAt), () => []).add(t);
      }
      for (final t in bucket) {
        final sources = mergedEvidence[t.id]!;
        for (final e in sources) {
          final day = _dayNumber(t.occurredAt);
          final nearby = [
            for (var offset = -2; offset <= 2; offset++)
              ...?byDay[day + offset],
          ];
          final others = nearby.where(
            (other) =>
                other.id != t.id &&
                !mergedEvidence[other.id]!.any(
                  (x) => x.sourceType == e.sourceType,
                ) &&
                other.occurredAt.difference(t.occurredAt).inDays.abs() <= 2,
          );
          if (others.isEmpty) continue;
          try {
            final match = const TransactionDeduplicator(defaultThreshold: 0.8)
                .findMatch(
                  candidate: TransactionCandidate(
                    id: t.id,
                    ingestionRecordId: e.ingestionRecordId,
                    entityId: entityId,
                    accountId: t.accountId,
                    amount: t.amount,
                    direction: t.direction,
                    occurredAt: t.occurredAt,
                    rawDescription: '',
                    merchantGuess: t.merchantName ?? t.normalizedDescription,
                    confidence: e.confidence,
                    sourceTrust: e.trust,
                    status: CandidateStatus.confirmed,
                  ),
                  sourceType: e.sourceType,
                  transactions: others,
                  evidence: others.expand((r) => mergedEvidence[r.id]!),
                  ingestionRecords: records.values,
                  accounts: accounts.values,
                );
            if (match != null) {
              final sourceConfidence = [
                ...sources.map((e) => e.confidence),
                ...mergedEvidence[match.transaction.id]!.map(
                  (e) => e.confidence,
                ),
                match.score,
              ].where((v) => v.isFinite && v >= 0 && v <= 1);
              uncertain[(t.id, match.transaction.id)] = sourceConfidence.reduce(
                (a, b) => a < b ? a : b,
              );
            }
          } on ReconciliationConflict {
            for (final other in others) {
              if (_sameDay(t.occurredAt, other.occurredAt) &&
                  t.normalizedDescription == other.normalizedDescription) {
                uncertain[(t.id, other.id)] = null;
              }
            }
          }
        }
      }
    }
    for (final group in bankWebIdentityAmbiguities(state, entityId)) {
      final ids = group.toList()..sort();
      for (final id in ids.skip(1)) {
        uncertain[(ids.first, id)] = null;
      }
    }
    final possibleParents = {for (final id in canonical.keys) id: id};
    String possibleRoot(String id) {
      while (possibleParents[id] != id) {
        id = possibleParents[id]!;
      }
      return id;
    }

    final scores = <String, double?>{};
    for (final entry in uncertain.entries) {
      final a = aliases[entry.key.$1], b = aliases[entry.key.$2];
      if (a == null || b == null || a == b) continue;
      final roots = [possibleRoot(a), possibleRoot(b)]..sort();
      possibleParents[roots.last] = roots.first;
      scores[a] = entry.value;
      scores[b] = entry.value;
    }
    final duplicateGroups = <String, List<String>>{};
    for (final id in scores.keys) {
      duplicateGroups.putIfAbsent(possibleRoot(id), () => []).add(id);
    }
    final duplicateKeys = <String, String>{};
    for (final ids in duplicateGroups.values) {
      ids.sort();
      for (final id in ids) {
        duplicateKeys[id] = jsonEncode(ids);
      }
    }

    final facts = <String, CanonicalOperationFacts>{};
    for (final t in canonical.values) {
      final observations = mergedEvidence[t.id]!;
      final types =
          observations
              .map(
                (e) => _source(
                  e.sourceType,
                  records[e.ingestionRecordId]?.adapterId,
                  t.tags,
                ),
              )
              .toSet()
              .toList()
            ..sort();
      final merged = observations.length > 1 || groupSizes[t.id]! > 1;
      final userFields = _userFields(t);
      final categorySource =
          userFields.contains('categoryId') ||
              t.userCategoryOverride != null ||
              t.tags.contains('qesto-manual-category')
          ? 'user'
          : t.tags.contains('qesto-auto-category')
          ? 'rule'
          : observations.any(
              (e) => e.sourceType == SynoballSourceType.modelInference,
            )
          ? 'ai'
          : t.providerCategory != null
          ? 'bank'
          : observations.isNotEmpty
          ? 'import'
          : 'unknown';
      final confidence = <String, double>{};
      final values = observations
          .map((e) => e.confidence)
          .where((v) => v.isFinite && v >= 0 && v <= 1)
          .toList();
      if (values.isNotEmpty) {
        confidence['overall'] = values.reduce((a, b) => a < b ? a : b);
      }
      if (t.categoryConfidence case final value?
          when value.isFinite && value >= 0 && value <= 1) {
        confidence['category'] = value;
      }
      String? original;
      var refundStatus = 'unmatched';
      String? transferId, counterparty;
      for (final e in state.events.where((e) => e.entityId == entityId)) {
        if (e.type == 'transaction.refund-linked' &&
            aliases[e.subjectId] == t.id) {
          final target = aliases[e.payload['originalTransactionId']];
          final expense = canonical[target];
          if (expense != null &&
              t.direction == FinancialDirection.inflow &&
              expense.direction == FinancialDirection.outflow &&
              expense.amount.currency == t.amount.currency &&
              expense.amount.minorUnits >= t.amount.minorUnits &&
              !expense.occurredAt.isAfter(t.occurredAt)) {
            original = target;
            refundStatus = 'matched';
          }
        }
        if (e.type == 'transaction.transfer-linked') {
          final outgoing = aliases[e.payload['outgoingTransactionId']];
          final incoming = aliases[e.payload['incomingTransactionId']];
          final out = canonical[outgoing], inc = canonical[incoming];
          if ((t.id == outgoing || t.id == incoming) &&
              out != null &&
              inc != null &&
              out.accountId != inc.accountId &&
              accounts.containsKey(out.accountId) &&
              accounts.containsKey(inc.accountId) &&
              out.direction == FinancialDirection.outflow &&
              inc.direction == FinancialDirection.inflow &&
              _sameMoney(out.amount, inc.amount) &&
              out.tags.contains('qesto-internal-transfer') &&
              inc.tags.contains('qesto-internal-transfer')) {
            transferId = jsonEncode([outgoing, incoming]);
            counterparty = t.id == outgoing ? inc.accountId : out.accountId;
          }
        }
      }
      if (t.tags.contains('refund') && original == null) {
        final matches = canonical.values
            .where(
              (expense) =>
                  expense.direction == FinancialDirection.outflow &&
                  expense.accountId == t.accountId &&
                  accounts[t.accountId]?.isVirtual == false &&
                  expense.amount.currency == t.amount.currency &&
                  expense.amount.minorUnits >= t.amount.minorUnits &&
                  !expense.occurredAt.isAfter(t.occurredAt) &&
                  t.occurredAt.difference(expense.occurredAt).inDays <= 90 &&
                  t.merchantName?.isNotEmpty == true &&
                  t.merchantName == expense.merchantName &&
                  !expense.tags.contains('qesto-internal-transfer'),
            )
            .toList();
        if (matches.length == 1) {
          refundStatus = 'possible_match';
        }
      }
      facts[t.id] = CanonicalOperationFacts(
        sourceTypes: types,
        evidenceCount: observations.length,
        merged: merged,
        deduplicationStatus:
            duplicateKeys.containsKey(t.id) ||
                t.tags.contains('qesto-potential-duplicate')
            ? 'possible_duplicate'
            : merged
            ? 'merged'
            : observations.any(
                (e) => e.providerTransactionId?.isNotEmpty == true,
              )
            ? 'source_identified'
            : 'unresolved',
        duplicateGroupId: duplicateKeys[t.id] ?? (merged ? t.id : null),
        deduplicationConfidence: scores[t.id],
        timePrecision: _precision(t, observations),
        categorySource: categorySource,
        confidence: confidence,
        userEditedFields: userFields,
        refundOriginalId: original,
        refundStatus: refundStatus,
        transferId: transferId,
        counterpartyAccountId: counterparty,
      );
    }
    // Completeness needs an explicit verification of every account and range.
    // A successful import alone is never evidence of a complete history.
    final complete =
        accounts.isNotEmpty &&
        accounts.keys.every(
          (id) => state.events.any(
            (e) =>
                e.entityId == entityId &&
                e.type == 'history.verified' &&
                e.subjectId == id &&
                _covers(e.payload, periodStart, periodEnd),
          ),
        );
    return CanonicalSnapshot(
      transactions: canonical,
      aliases: aliases,
      facts: facts,
      accounts: {for (final a in accounts.values) a.id: _account(a)},
      historyCompleteness: complete ? 'complete' : 'not_verified',
      verifiedRanges: List.unmodifiable(
        state.events
            .where(
              (e) =>
                  e.entityId == entityId &&
                  e.type == 'history.verified' &&
                  accounts.containsKey(e.subjectId) &&
                  e.payload['status'] == 'complete' &&
                  DateTime.tryParse(e.payload['startDate']?.toString() ?? '') !=
                      null &&
                  DateTime.tryParse(
                        e.payload['endDateInclusive']?.toString() ?? '',
                      ) !=
                      null &&
                  !rows.values.any(
                    (t) =>
                        t.accountId == e.subjectId &&
                        t.updatedAt.isAfter(e.occurredAt),
                  ),
            )
            .map(
              (e) => CanonicalVerifiedRange(
                e.subjectId!,
                DateTime.parse(e.payload['startDate'] as String),
                DateTime.parse(e.payload['endDateInclusive'] as String),
              ),
            ),
      ),
    );
  }
}

CanonicalAccountFacts _account(SynoballAccount a) {
  final unassigned =
      a.id == 'local-default-account' ||
      a.id.startsWith('sber-unassigned-') ||
      (a.isVirtual &&
          RegExp(
            r'не определ[её]н|неизвест',
            caseSensitive: false,
          ).hasMatch(a.name));
  final bank = a.institutionId != null || a.connectionId != null || unassigned;
  final type = switch (a.type) {
    SynoballAccountType.checking => 'bank_account',
    SynoballAccountType.card => 'debit_card',
    SynoballAccountType.credit => 'credit_card',
    SynoballAccountType.brokerage => 'brokerage',
    SynoballAccountType.cash => bank ? 'bank_account' : 'cash',
    _ => a.type.name == 'investment' ? 'other' : a.type.name,
  };
  return CanonicalAccountFacts(
    type: type,
    subtype: a.type == SynoballAccountType.checking ? 'payment' : 'unknown',
    balanceNature: a.type == SynoballAccountType.loan
        ? 'liability'
        : a.type == SynoballAccountType.credit
        ? 'mixed'
        : a.type == SynoballAccountType.other
        ? 'unknown'
        : 'asset',
    resolutionStatus: unassigned
        ? 'unresolved'
        : a.isVirtual
        ? 'virtual'
        : 'resolved',
    balanceStatus: unassigned || a.isVirtual && a.balance.minorUnits == 0
        ? 'unknown'
        : 'known',
  );
}

List<String> _userFields(CanonicalTransaction t) => {
  for (final entry in const {
    'account': 'accountId',
    'amount': 'amount',
    'date': 'occurredDate',
    'merchant': 'name',
    'description': 'name',
    'category': 'categoryId',
    'subcategory': 'categoryId',
    'type': 'type',
  }.entries)
    if (t.tags.contains('user-field:${entry.key}')) entry.value,
  if (t.userCategoryOverride != null ||
      t.tags.contains('qesto-manual-category'))
    'categoryId',
}.toList()..sort();

String _precision(CanonicalTransaction t, List<SourceEvidence> evidence) {
  if (t.tags.contains('time-precision:datetime')) return 'datetime';
  if (t.tags.contains('time-precision:unknown')) return 'unknown';
  if (t.tags.contains('time-precision:approximate')) return 'approximate';
  if (t.tags.contains('time-precision:date') ||
      t.occurredAt.hour == 0 &&
          t.occurredAt.minute == 0 &&
          t.occurredAt.second == 0 &&
          t.occurredAt.millisecond == 0) {
    return 'date';
  }
  // Notification receive time and screenshot fallback time are not purchase time.
  if (evidence.isEmpty ||
      evidence.every(
        (e) => const {
          SynoballSourceType.androidNotification,
          SynoballSourceType.smsNotification,
          SynoballSourceType.bankScreenshot,
          SynoballSourceType.legacy,
        }.contains(e.sourceType),
      )) {
    return 'approximate';
  }
  return 'datetime';
}

String _source(SynoballSourceType source, String? adapter, List<String> tags) =>
    switch (source) {
      SynoballSourceType.statement =>
        (adapter?.contains('excel') == true ||
                tags.any((t) => t.startsWith('excel-')))
            ? 'excel_statement'
            : 'bank_statement',
      SynoballSourceType.androidNotification => 'android_notification',
      SynoballSourceType.smsNotification => 'sms',
      SynoballSourceType.bankScreenshot => 'bank_screenshot',
      SynoballSourceType.bankWeb => 'bank_web',
      SynoballSourceType.manualVoice => 'voice',
      SynoballSourceType.regulatedApi => 'regulated_api',
      SynoballSourceType.directApi => 'direct_api',
      SynoballSourceType.modelInference => 'model_inference',
      _ => source.name,
    };

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _sameMoney(Money a, Money b) =>
    a.minorUnits == b.minorUnits && a.currency == b.currency;

int _dayNumber(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

bool _covers(Map<String, dynamic> payload, DateTime start, DateTime end) {
  if (payload['status'] != 'complete') return false;
  final from = DateTime.tryParse(payload['startDate']?.toString() ?? '');
  final to = DateTime.tryParse(payload['endDateInclusive']?.toString() ?? '');
  return from != null &&
      to != null &&
      !from.isAfter(start) &&
      !to.isBefore(end);
}
