import '../enrichment/enrichment.dart';
import '../ingestion/adapter.dart';
import '../reconciliation/deduplication.dart';
import '../reconciliation/source_trust_policy.dart';
import 'models.dart';

class IngestionOutcome {
  const IngestionOutcome({
    required this.ingestionRecordId,
    required this.createdTransactionIds,
    required this.matchedTransactionIds,
    required this.pendingCandidateIds,
    this.importBatchId,
    this.warnings = const [],
  });

  final String ingestionRecordId;
  final List<String> createdTransactionIds;
  final List<String> matchedTransactionIds;
  final List<String> pendingCandidateIds;
  final String? importBatchId;
  final List<String> warnings;
}

class SynoballCore {
  SynoballCore({
    SynoballState initialState = const SynoballState(),
    this._deduplicator = const TransactionDeduplicator(),
    this._trustPolicy = const SourceTrustPolicy(),
    this._enrichment = const EnrichmentEngine(),
    SynoballIdFactory? ids,
  }) : _ids = ids ?? SynoballIdFactory(),
       _entities = List.of(initialState.entities),
       _institutions = List.of(initialState.institutions),
       _connections = List.of(initialState.connections),
       _consents = List.of(initialState.consents),
       _accounts = List.of(initialState.accounts),
       _rawPayloads = List.of(initialState.rawPayloads),
       _ingestionRecords = List.of(initialState.ingestionRecords),
       _candidates = List.of(initialState.candidates),
       _transactions = List.of(initialState.transactions),
       _evidence = List.of(initialState.evidence),
       _receipts = List.of(initialState.receipts),
       _importBatches = List.of(initialState.importBatches),
       _recurringStreams = List.of(initialState.recurringStreams),
       _events = List.of(initialState.events),
       _auditEntries = List.of(initialState.auditEntries) {
    _transactionIndexById = _buildPositionIndex(
      _transactions,
      (value) => value.id,
    );
    _candidateIndexById = _buildPositionIndex(_candidates, (value) => value.id);
    _ingestionRecordIndexById = _buildPositionIndex(
      _ingestionRecords,
      (value) => value.id,
    );
    _importBatchIndexById = _buildPositionIndex(
      _importBatches,
      (value) => value.id,
    );
    _evidenceByTransactionId = <String, List<SourceEvidence>>{};
    _providerTransactionIds = <String>{};
    _providerEvidenceKeys = <_ProviderEvidenceKey>{};
    for (final item in _evidence) {
      _indexEvidence(item);
    }
  }

  final TransactionDeduplicator _deduplicator;
  final SourceTrustPolicy _trustPolicy;
  final EnrichmentEngine _enrichment;
  final SynoballIdFactory _ids;

  final List<SynoballEntity> _entities;
  final List<Institution> _institutions;
  final List<SynoballConnection> _connections;
  final List<SynoballConsent> _consents;
  final List<SynoballAccount> _accounts;
  final List<RawPayload> _rawPayloads;
  final List<IngestionRecord> _ingestionRecords;
  final List<TransactionCandidate> _candidates;
  final List<CanonicalTransaction> _transactions;
  final List<SourceEvidence> _evidence;
  final List<SynoballReceipt> _receipts;
  final List<ImportBatch> _importBatches;
  final List<RecurringStream> _recurringStreams;
  final List<SynoballEvent> _events;
  final List<SynoballAuditEntry> _auditEntries;
  late final Map<String, int> _transactionIndexById;
  late final Map<String, int> _candidateIndexById;
  late final Map<String, int> _ingestionRecordIndexById;
  late final Map<String, int> _importBatchIndexById;
  late final Map<String, List<SourceEvidence>> _evidenceByTransactionId;
  late final Set<String> _providerTransactionIds;
  late final Set<_ProviderEvidenceKey> _providerEvidenceKeys;

  SynoballState get state => SynoballState(
    entities: List.unmodifiable(_entities),
    institutions: List.unmodifiable(_institutions),
    connections: List.unmodifiable(_connections),
    consents: List.unmodifiable(_consents),
    accounts: List.unmodifiable(_accounts),
    rawPayloads: List.unmodifiable(_rawPayloads),
    ingestionRecords: List.unmodifiable(_ingestionRecords),
    candidates: List.unmodifiable(_candidates),
    transactions: List.unmodifiable(_transactions),
    evidence: List.unmodifiable(_evidence),
    receipts: List.unmodifiable(_receipts),
    importBatches: List.unmodifiable(_importBatches),
    recurringStreams: List.unmodifiable(_recurringStreams),
    events: List.unmodifiable(_events),
    auditEntries: List.unmodifiable(_auditEntries),
  );

  List<CanonicalTransaction> get transactions => _transactions
      .where((item) => item.status != CanonicalTransactionStatus.deleted)
      .toList(growable: false);

  List<TransactionCandidate> get pendingCandidates => _candidates
      .where((item) => item.status == CandidateStatus.pending)
      .toList(growable: false);

  CanonicalTransaction? transactionById(String id) {
    final index = _transactionIndexById[id];
    return index == null ? null : _transactions[index];
  }

  bool hasTransactionOrProviderId(String id) =>
      transactionById(id)?.status == CanonicalTransactionStatus.posted ||
      _providerTransactionIds.contains(id);

  IngestionOutcome ingest<T>(SynoballAdapter<T> adapter, T input) {
    final adapted = adapter.parse(input);
    _upsertMany(_institutions, adapted.institutions, (value) => value.id);
    _upsertMany(_connections, adapted.connections, (value) => value.id);
    _upsertMany(_consents, adapted.consents, (value) => value.id);
    _upsertMany(_accounts, adapted.accounts, (value) => value.id);
    _rawPayloads.add(adapted.rawPayload);
    _ingestionRecordIndexById[adapted.record.id] = _ingestionRecords.length;
    _ingestionRecords.add(adapted.record);
    for (final candidate in adapted.candidates) {
      _candidateIndexById[candidate.id] = _candidates.length;
      _candidates.add(candidate);
    }
    _upsertMany(_receipts, adapted.receipts, (value) => value.id);
    if (adapted.importBatch != null) {
      _importBatchIndexById[adapted.importBatch!.id] = _importBatches.length;
      _importBatches.add(adapted.importBatch!);
    }

    final created = <String>[];
    final matched = <String>[];
    final pending = <String>[];
    var failures = 0;
    for (final candidate in adapted.candidates) {
      if (candidate.requiresConfirmation) {
        pending.add(candidate.id);
        continue;
      }
      try {
        final result = _reconcile(candidate, adapted.record.sourceType);
        (result.created ? created : matched).add(result.transactionId);
      } on Object {
        failures += 1;
      }
    }

    final recordIndex = _ingestionRecordIndexById[adapted.record.id]!;
    _ingestionRecords[recordIndex] = adapted.record.copyWith(
      status: failures > 0
          ? IngestionStatus.needsReview
          : pending.isNotEmpty
          ? IngestionStatus.needsReview
          : IngestionStatus.completed,
      errorCode: failures > 0 ? SynoballErrorCode.partialSync : null,
      errorMessage: failures > 0 ? '$failures record(s) failed' : null,
    );

    if (adapted.importBatch != null) {
      final index = _importBatchIndexById[adapted.importBatch!.id]!;
      _importBatches[index] = adapted.importBatch!.copyWith(
        status: failures > 0
            ? ImportBatchStatus.partial
            : ImportBatchStatus.completed,
        createdTransactions: created.length,
        matchedTransactions: matched.length,
        failedRecords: failures,
        warnings: adapted.warnings,
      );
    }
    _refreshDerivedData();
    _emit(
      type: 'financial_state.updated',
      entityId: adapted.record.entityId,
      payload: {'ingestionRecordId': adapted.record.id},
    );
    for (final connection in adapted.connections) {
      _emit(
        type: connection.status == ConnectionStatus.active
            ? 'connection.synced'
            : 'connection.error',
        entityId: connection.entityId,
        subjectId: connection.id,
        payload: {
          'adapterId': connection.adapterId,
          'adapterVersion': connection.adapterVersion,
          if (connection.lastErrorCode != null)
            'errorCode': connection.lastErrorCode!.name,
        },
      );
    }
    return IngestionOutcome(
      ingestionRecordId: adapted.record.id,
      createdTransactionIds: created,
      matchedTransactionIds: matched,
      pendingCandidateIds: pending,
      importBatchId: adapted.importBatch?.id,
      warnings: adapted.warnings,
    );
  }

  String confirmCandidate(String candidateId, {required String actorId}) {
    final index = _candidateIndexById[candidateId];
    if (index == null) throw StateError('Candidate not found: $candidateId');
    final candidate = _candidates[index];
    if (candidate.status != CandidateStatus.pending) {
      throw StateError('Candidate is not pending: $candidateId');
    }
    final recordIndex = _ingestionRecordIndexById[candidate.ingestionRecordId];
    if (recordIndex == null) {
      throw StateError(
        'Ingestion record not found: ${candidate.ingestionRecordId}',
      );
    }
    final record = _ingestionRecords[recordIndex];
    final confirmed = candidate.copyWith(
      confidence: 1,
      sourceTrust: SourceTrustLevel.userConfirmed,
      status: CandidateStatus.pending,
      requiresConfirmation: false,
    );
    _candidates[index] = confirmed;
    final result = _reconcile(confirmed, record.sourceType);
    _audit(
      actorId: actorId,
      action: 'candidate.confirmed',
      entityId: candidate.entityId,
      purpose: 'Create user-confirmed financial transaction',
      subjectId: result.transactionId,
    );
    _refreshDerivedData();
    return result.transactionId;
  }

  void upsertEntity(SynoballEntity entity) =>
      _upsertMany(_entities, [entity], (value) => value.id);

  void upsertAccount(SynoballAccount account) =>
      _upsertMany(_accounts, [account], (value) => value.id);

  void removeAccountIfUnused(String accountId) {
    final used = _transactions.any(
      (item) =>
          item.status == CanonicalTransactionStatus.posted &&
          item.accountId == accountId,
    );
    if (!used) _accounts.removeWhere((item) => item.id == accountId);
  }

  void updateTransaction(
    CanonicalTransaction transaction, {
    required String actorId,
    String purpose = 'User corrected a transaction',
  }) {
    final index = _transactionIndexById[transaction.id];
    if (index == null) {
      throw StateError('Transaction not found: ${transaction.id}');
    }
    _transactions[index] = _enrichment.enrich(
      transaction.copyWith(
        updatedAt: DateTime.now(),
        fieldTrust: SourceTrustLevel.userConfirmed,
      ),
    );
    _audit(
      actorId: actorId,
      action: 'transaction.updated',
      entityId: transaction.entityId,
      purpose: purpose,
      subjectId: transaction.id,
    );
    _emit(
      type: 'transaction.updated',
      entityId: transaction.entityId,
      subjectId: transaction.id,
    );
    _refreshDerivedData();
  }

  void deleteTransaction(String id, {required String actorId}) {
    final index = _transactionIndexById[id];
    if (index == null) return;
    final transaction = _transactions[index];
    _transactions[index] = transaction.copyWith(
      status: CanonicalTransactionStatus.deleted,
      updatedAt: DateTime.now(),
    );
    _audit(
      actorId: actorId,
      action: 'transaction.deleted',
      entityId: transaction.entityId,
      purpose: 'User removed a transaction from the financial picture',
      subjectId: id,
    );
    _emit(
      type: 'transaction.updated',
      entityId: transaction.entityId,
      subjectId: id,
    );
    _refreshDerivedData();
  }

  void restoreTransaction(CanonicalTransaction transaction) {
    final index = _transactionIndexById[transaction.id];
    final restored = transaction.copyWith(
      status: CanonicalTransactionStatus.posted,
      updatedAt: DateTime.now(),
    );
    if (index == null) {
      _transactionIndexById[restored.id] = _transactions.length;
      _transactions.add(restored);
    } else {
      _transactions[index] = restored;
    }
    _refreshDerivedData();
  }

  _ReconciliationResult _reconcile(
    TransactionCandidate candidate,
    SynoballSourceType sourceType,
  ) {
    final match = _deduplicator.findMatch(
      candidate: candidate,
      sourceType: sourceType,
      transactions: _transactions,
      evidence: _evidence,
    );
    final now = DateTime.now();
    late final String transactionId;
    late final bool created;
    if (match == null) {
      transactionId = candidate.canonicalId ?? 'txn-${candidate.id}';
      final createdTransaction = CanonicalTransaction(
        id: transactionId,
        entityId: candidate.entityId,
        accountId: candidate.accountId,
        status: CanonicalTransactionStatus.posted,
        amount: candidate.amount,
        direction: candidate.direction,
        occurredAt: candidate.occurredAt,
        rawDescription: candidate.rawDescription,
        normalizedDescription:
            candidate.normalizedDescription ?? candidate.rawDescription,
        merchantName: candidate.merchantGuess,
        merchantConfidence: candidate.merchantGuess == null
            ? null
            : candidate.confidence,
        providerCategory: candidate.providerCategory,
        synoballCategory: candidate.categoryGuess,
        userCategoryOverride: candidate.userCategoryOverride,
        categoryConfidence: candidate.categoryGuess == null
            ? null
            : candidate.confidence,
        subcategoryId: candidate.subcategoryId,
        transferDirection: candidate.transferDirection,
        eventType: FinancialEventType.observed,
        receiptId: candidate.receiptId,
        tags: candidate.tags,
        createdAt: now,
        updatedAt: now,
        fieldTrust: candidate.sourceTrust,
      );
      _transactionIndexById[transactionId] = _transactions.length;
      _transactions.add(_enrichment.enrich(createdTransaction));
      created = true;
      _emit(
        type: 'transaction.created',
        entityId: candidate.entityId,
        subjectId: transactionId,
      );
    } else {
      transactionId = match.transaction.id;
      final index = _transactionIndexById[transactionId]!;
      final current = _transactions[index];
      final existingSources =
          (_evidenceByTransactionId[transactionId] ?? const <SourceEvidence>[])
              .map((item) => item.sourceType)
              .toSet();
      final replace =
          (candidate.canonicalId == current.id &&
              sourceType == SynoballSourceType.statement) ||
          _trustPolicy.shouldReplace(
            current: current.fieldTrust,
            incoming: candidate.sourceTrust,
          );
      final tags = {...current.tags, ...candidate.tags}.toList();
      final replaceTime = _shouldReplaceOccurredAt(
        current: current,
        candidate: candidate,
        incomingSource: sourceType,
        existingSources: existingSources,
      );
      final replaceMerchant =
          candidate.merchantGuess?.trim().isNotEmpty == true &&
          (_sourceDetailRank(sourceType) >=
                  _bestSourceDetailRank(existingSources) ||
              current.merchantName == null);
      final replaceDescription =
          candidate.rawDescription.trim().isNotEmpty &&
          (_sourceDetailRank(sourceType) >=
                  _bestSourceDetailRank(existingSources) ||
              current.rawDescription.trim().isEmpty);
      final mergedSynoballCategory = _mergeCategory(
        current.synoballCategory,
        candidate.categoryGuess,
        replace: replace,
      );
      _transactions[index] = _enrichment.enrich(
        current.copyWith(
          accountId: replace ? candidate.accountId : current.accountId,
          amount: replace ? candidate.amount : current.amount,
          direction: replace ? candidate.direction : current.direction,
          occurredAt: replaceTime ? candidate.occurredAt : current.occurredAt,
          rawDescription: replaceDescription
              ? candidate.rawDescription
              : current.rawDescription,
          normalizedDescription: replaceDescription
              ? candidate.normalizedDescription ?? candidate.rawDescription
              : current.normalizedDescription,
          merchantName: replaceMerchant
              ? candidate.merchantGuess
              : current.merchantName,
          merchantConfidence: replaceMerchant
              ? candidate.confidence
              : current.merchantConfidence,
          providerCategory: _mergeCategory(
            current.providerCategory,
            candidate.providerCategory,
            replace: replace,
          ),
          synoballCategory: mergedSynoballCategory,
          userCategoryOverride:
              candidate.userCategoryOverride ?? current.userCategoryOverride,
          categoryConfidence:
              candidate.categoryGuess != null &&
                  mergedSynoballCategory == candidate.categoryGuess
              ? candidate.confidence
              : current.categoryConfidence,
          subcategoryId:
              candidate.subcategoryId != null &&
                  (replace || current.subcategoryId == null)
              ? candidate.subcategoryId
              : current.subcategoryId,
          transferDirection:
              candidate.transferDirection ?? current.transferDirection,
          receiptId: candidate.receiptId ?? current.receiptId,
          tags: tags,
          updatedAt: now,
          fieldTrust: replace ? candidate.sourceTrust : current.fieldTrust,
        ),
      );
      created = false;
      _emit(
        type: 'transaction.merged',
        entityId: candidate.entityId,
        subjectId: transactionId,
        payload: {'score': match.score, 'reasons': match.reasons},
      );
    }

    final providerTransactionId = candidate.providerTransactionId;
    final alreadyObserved =
        providerTransactionId != null &&
        _providerEvidenceKeys.contains((
          transactionId: transactionId,
          sourceType: sourceType,
          providerTransactionId: providerTransactionId,
        ));
    if (!alreadyObserved) {
      final item = SourceEvidence(
        id: _ids.next('evd'),
        transactionId: transactionId,
        sourceType: sourceType,
        ingestionRecordId: candidate.ingestionRecordId,
        confidence: candidate.confidence,
        trust: candidate.sourceTrust,
        observedAt: candidate.occurredAt,
        providerTransactionId: providerTransactionId,
      );
      _evidence.add(item);
      _indexEvidence(item);
    }
    final candidateIndex = _candidateIndexById[candidate.id]!;
    _candidates[candidateIndex] = candidate.copyWith(
      status: created ? CandidateStatus.confirmed : CandidateStatus.merged,
    );
    return _ReconciliationResult(
      transactionId: transactionId,
      created: created,
    );
  }

  void _refreshDerivedData() {
    final streams = _enrichment.detectRecurring(_transactions);
    _recurringStreams
      ..clear()
      ..addAll(streams);
    final streamByTransaction = <String, RecurringStream>{};
    for (final stream in streams) {
      for (final id in stream.transactionIds) {
        streamByTransaction[id] = stream;
      }
    }
    for (var index = 0; index < _transactions.length; index++) {
      final transaction = _transactions[index];
      final stream = streamByTransaction[transaction.id];
      final isRecurring = stream != null;
      if (transaction.isRecurring != isRecurring ||
          transaction.recurringStreamId != stream?.id) {
        _transactions[index] = transaction.copyWith(
          isRecurring: isRecurring,
          recurringStreamId: stream?.id,
          clearRecurringStreamId: stream == null,
        );
      }
    }
  }

  void _indexEvidence(SourceEvidence item) {
    _evidenceByTransactionId
        .putIfAbsent(item.transactionId, () => <SourceEvidence>[])
        .add(item);
    final providerTransactionId = item.providerTransactionId;
    if (providerTransactionId == null) return;
    _providerTransactionIds.add(providerTransactionId);
    _providerEvidenceKeys.add((
      transactionId: item.transactionId,
      sourceType: item.sourceType,
      providerTransactionId: providerTransactionId,
    ));
  }

  void _emit({
    required String type,
    required String entityId,
    String? subjectId,
    Map<String, dynamic> payload = const {},
  }) {
    _events.add(
      SynoballEvent(
        id: _ids.next('evt'),
        type: type,
        entityId: entityId,
        subjectId: subjectId,
        occurredAt: DateTime.now(),
        payload: payload,
      ),
    );
  }

  void _audit({
    required String actorId,
    required String action,
    required String entityId,
    required String purpose,
    String? subjectId,
  }) {
    _auditEntries.add(
      SynoballAuditEntry(
        id: _ids.next('aud'),
        actorId: actorId,
        action: action,
        entityId: entityId,
        purpose: purpose,
        occurredAt: DateTime.now(),
        subjectId: subjectId,
      ),
    );
  }
}

bool _shouldReplaceOccurredAt({
  required CanonicalTransaction current,
  required TransactionCandidate candidate,
  required SynoballSourceType incomingSource,
  required Set<SynoballSourceType> existingSources,
}) {
  final incomingRank = _timePrecisionRank(incomingSource);
  final currentRank = existingSources.isEmpty
      ? 0
      : existingSources.map(_timePrecisionRank).reduce((a, b) => a > b ? a : b);
  if (incomingRank < currentRank) return false;

  // Statements frequently carry a posting date with an artificial midnight
  // time. Never let that erase the actual purchase time from a receipt or
  // Android notification.
  final incomingIsDateOnly =
      candidate.occurredAt.hour == 0 &&
      candidate.occurredAt.minute == 0 &&
      candidate.occurredAt.second == 0;
  final currentHasTime =
      current.occurredAt.hour != 0 ||
      current.occurredAt.minute != 0 ||
      current.occurredAt.second != 0;
  if (incomingSource == SynoballSourceType.statement &&
      incomingIsDateOnly &&
      currentHasTime) {
    return false;
  }
  return true;
}

int _timePrecisionRank(SynoballSourceType source) => switch (source) {
  SynoballSourceType.receipt => 6,
  SynoballSourceType.manual || SynoballSourceType.manualVoice => 5,
  SynoballSourceType.androidNotification => 5,
  SynoballSourceType.directApi || SynoballSourceType.regulatedApi => 4,
  SynoballSourceType.statement => 2,
  SynoballSourceType.legacy || SynoballSourceType.modelInference => 1,
};

int _sourceDetailRank(SynoballSourceType source) => switch (source) {
  SynoballSourceType.receipt => 6,
  SynoballSourceType.manual || SynoballSourceType.manualVoice => 5,
  SynoballSourceType.directApi || SynoballSourceType.regulatedApi => 5,
  SynoballSourceType.statement => 4,
  SynoballSourceType.androidNotification => 3,
  SynoballSourceType.legacy || SynoballSourceType.modelInference => 1,
};

int _bestSourceDetailRank(Set<SynoballSourceType> sources) => sources.isEmpty
    ? 0
    : sources.map(_sourceDetailRank).reduce((a, b) => a > b ? a : b);

String? _mergeCategory(
  String? current,
  String? incoming, {
  required bool replace,
}) {
  if (incoming == null || incoming.isEmpty) return current;
  if (current == null || current.isEmpty || current == 'other') return incoming;
  if (incoming == 'other') return current;
  return replace ? incoming : current;
}

class _ReconciliationResult {
  const _ReconciliationResult({
    required this.transactionId,
    required this.created,
  });
  final String transactionId;
  final bool created;
}

typedef _ProviderEvidenceKey = ({
  String transactionId,
  SynoballSourceType sourceType,
  String providerTransactionId,
});

Map<String, int> _buildPositionIndex<T>(
  List<T> values,
  String Function(T) idOf,
) => <String, int>{
  for (var index = 0; index < values.length; index++)
    idOf(values[index]): index,
};

void _upsertMany<T>(
  List<T> target,
  Iterable<T> incoming,
  String Function(T) idOf,
) {
  final positions = _buildPositionIndex(target, idOf);
  for (final value in incoming) {
    final id = idOf(value);
    final index = positions[id];
    if (index == null) {
      positions[id] = target.length;
      target.add(value);
    } else {
      target[index] = value;
    }
  }
}
