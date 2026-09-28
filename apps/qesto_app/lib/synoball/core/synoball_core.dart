import '../enrichment/enrichment.dart';
import '../enrichment/category_policy.dart';
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
    this.failedCandidateIds = const [],
    this.resolvedTransactionIds = const [],
    this.suppressedTransactionIds = const [],
  });

  final String ingestionRecordId;
  final List<String> createdTransactionIds;
  final List<String> matchedTransactionIds;
  final List<String> pendingCandidateIds;
  final String? importBatchId;
  final List<String> warnings;
  final List<String> failedCandidateIds;

  /// One entry per adapted candidate, in source order. Null means review or
  /// failure; a non-null ID is the actual reconciled canonical target.
  /// This is a command result, not a change to the persisted data schema.
  final List<String?> resolvedTransactionIds;

  /// Recognised identities that remain in the user's trash; not active merges.
  final List<String> suppressedTransactionIds;
}

class SynoballCore {
  SynoballCore({
    SynoballState initialState = const SynoballState(),
    this._deduplicator = const TransactionDeduplicator(),
    this._trustPolicy = const SourceTrustPolicy(),
    CategoryPolicy categoryPolicy = const CategoryPolicy(),
    SynoballIdFactory? ids,
  }) : _enrichment = EnrichmentEngine(categoryPolicy: categoryPolicy),
       _ids = ids ?? SynoballIdFactory(),
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
    // Recurring streams are derived data. Rebuild on restore as well as import
    // so an algorithm upgrade does not leave an old empty/stale UI indefinitely.
    setCategoryPolicy(categoryPolicy);
  }

  final TransactionDeduplicator _deduplicator;
  final SourceTrustPolicy _trustPolicy;
  EnrichmentEngine _enrichment;

  /// Reapply user policy to existing canonical facts without changing financial
  /// values/status or update timestamps. Includes trash for safe later restore.
  void setCategoryPolicy(CategoryPolicy policy) {
    _enrichment = EnrichmentEngine(categoryPolicy: policy);
    for (var i = 0; i < _transactions.length; i++) {
      _transactions[i] = policy.apply(
        _transactions[i],
        identity: _enrichment.merchantIdentity(_transactions[i]),
      );
    }
    _refreshDerivedData();
  }

  void removeUserTag(String id, {required String actorId}) {
    for (var i = 0; i < _transactions.length; i++) {
      final t = _transactions[i];
      if (!t.tags.contains('$userLabelPrefix$id')) continue;
      _transactions[i] = t.copyWith(
        tags: t.tags.where((s) => s != '$userLabelPrefix$id').toList(),
      );
    }
    _audit(
      actorId: actorId,
      action: 'user-tag.deleted',
      entityId: 'ent-$actorId',
      purpose: 'Remove user tag without deleting transactions',
      subjectId: id,
    );
  }

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
    // A retry of an unresolved native delivery must not grow the review inbox.
    // Never deduplicate new manual commands by their text/content.
    if (adapted.candidates.length == 1 &&
        (adapted.record.sourceType == SynoballSourceType.androidNotification ||
            adapted.record.sourceType == SynoballSourceType.smsNotification)) {
      final incoming = adapted.candidates.single;
      for (final previous in _candidates) {
        if (previous.status != CandidateStatus.pending ||
            !previous.requiresConfirmation ||
            incoming.providerTransactionId == null ||
            previous.providerTransactionId != incoming.providerTransactionId ||
            previous.entityId != incoming.entityId ||
            previous.accountId != incoming.accountId ||
            previous.amount.minorUnits != incoming.amount.minorUnits ||
            previous.amount.currency != incoming.amount.currency ||
            previous.direction != incoming.direction ||
            previous.occurredAt != incoming.occurredAt ||
            previous.categoryGuess != incoming.categoryGuess ||
            previous.merchantGuess != incoming.merchantGuess) {
          continue;
        }
        final recordIndex =
            _ingestionRecordIndexById[previous.ingestionRecordId];
        if (recordIndex == null) continue;
        final record = _ingestionRecords[recordIndex];
        if (record.sourceType != adapted.record.sourceType ||
            record.adapterVersion != adapted.record.adapterVersion ||
            record.connectionId != adapted.record.connectionId ||
            record.institutionId != adapted.record.institutionId) {
          continue;
        }
        if (!_rawPayloads.any(
          (raw) =>
              raw.id == record.rawPayloadId &&
              raw.body == adapted.rawPayload.body,
        )) {
          continue;
        }
        return IngestionOutcome(
          ingestionRecordId: record.id,
          createdTransactionIds: const [],
          matchedTransactionIds: const [],
          pendingCandidateIds: [previous.id],
          resolvedTransactionIds: const [null],
        );
      }
    }
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
    final failed = <String>[];
    final resolved = <String?>[];
    final suppressed = <String>[];
    final batchConflicts = _deduplicator.batchConflicts(
      candidates: adapted.candidates,
      sourceType: adapted.record.sourceType,
      transactions: _transactions,
      evidence: _evidence,
      ingestionRecords: _ingestionRecords,
      accounts: _accounts,
      sourceCandidates: _candidates,
    );
    var failures = 0;
    for (final candidate in adapted.candidates) {
      if (candidate.requiresConfirmation) {
        pending.add(candidate.id);
        resolved.add(null);
        continue;
      }
      try {
        final conflict = batchConflicts[candidate.id];
        if (conflict != null) throw ReconciliationConflict(conflict);
        final result = _reconcile(candidate, adapted.record.sourceType);
        (result.created
                ? created
                : result.suppressed
                ? suppressed
                : matched)
            .add(result.transactionId);
        resolved.add(result.transactionId);
      } on ReconciliationConflict catch (conflict) {
        final index = _candidateIndexById[candidate.id]!;
        _candidates[index] = candidate.copyWith(
          requiresConfirmation: true,
          tags: {...candidate.tags, 'review-${conflict.reason}'}.toList(),
        );
        pending.add(candidate.id);
        resolved.add(null);
      } on Object {
        failures += 1;
        failed.add(candidate.id);
        resolved.add(null);
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

    final warnings = [
      ...adapted.warnings,
      if (suppressed.isNotEmpty) 'user_deleted_suppressed:${suppressed.length}',
    ];
    if (adapted.importBatch != null) {
      final index = _importBatchIndexById[adapted.importBatch!.id]!;
      _importBatches[index] = adapted.importBatch!.copyWith(
        status: failures > 0 || pending.isNotEmpty
            ? ImportBatchStatus.partial
            : ImportBatchStatus.completed,
        createdTransactions: created.length,
        matchedTransactions: matched.length,
        failedRecords: failures,
        warnings: warnings,
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
      failedCandidateIds: failed,
      resolvedTransactionIds: resolved,
      suppressedTransactionIds: suppressed,
      importBatchId: adapted.importBatch?.id,
      warnings: warnings,
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
    final _ReconciliationResult result;
    try {
      result = _reconcile(confirmed, record.sourceType);
    } on ReconciliationConflict {
      // An unresolved identity must remain retryable in the review inbox.
      _candidates[index] = candidate;
      rethrow;
    }
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

  String? sourceAccountMapping(String entityId, String sourceKey) {
    String resolveMerged(String id) {
      final visited = <String>{};
      while (visited.add(id)) {
        final next = _events
            .where(
              (e) =>
                  e.entityId == entityId &&
                  e.type == 'account.merged' &&
                  e.payload['duplicateAccountId'] == id,
            )
            .map((e) => e.subjectId)
            .whereType<String>()
            .toSet();
        if (next.length != 1) break;
        id = next.single;
      }
      return id;
    }

    final matches = _events
        .where(
          (e) =>
              e.entityId == entityId &&
              e.type == 'account.source-linked' &&
              e.payload['sourceKey'] == sourceKey,
        )
        .map((e) => e.subjectId)
        .whereType<String>()
        .map(resolveMerged)
        .toSet();
    if (matches.length != 1 ||
        !_accounts.any(
          (a) => a.entityId == entityId && a.id == matches.single,
        )) {
      return null;
    }
    return matches.single;
  }

  /// Explicit user confirmation links two source representations. No guessing
  /// by balance/name/suffix; the canonical account schema remains unchanged.
  void linkSourceAccount({
    required String entityId,
    required String sourceKey,
    required String accountId,
    required String actorId,
  }) {
    if (sourceKey.isEmpty ||
        !_accounts.any((a) => a.id == accountId && a.entityId == entityId)) {
      throw StateError('Unknown source or account');
    }
    final existing = sourceAccountMapping(entityId, sourceKey);
    if (existing == accountId) return;
    if (existing != null ||
        _events.any(
          (e) =>
              e.entityId == entityId &&
              e.type == 'account.source-linked' &&
              e.payload['sourceKey'] == sourceKey,
        )) {
      throw StateError('Source account is already linked; review required');
    }
    _emit(
      type: 'account.source-linked',
      entityId: entityId,
      subjectId: accountId,
      payload: {'sourceKey': sourceKey, 'confirmedBy': actorId},
    );
    _audit(
      actorId: actorId,
      action: 'account.source-linked',
      entityId: entityId,
      subjectId: accountId,
      purpose: 'User confirmed the statement account mapping',
    );
  }

  void removeAccountIfUnused(String accountId) {
    final used = _transactions.any(
      (item) =>
          item.status == CanonicalTransactionStatus.posted &&
          item.accountId == accountId,
    );
    if (!used) _accounts.removeWhere((item) => item.id == accountId);
  }

  /// Repoints every canonical operation from a duplicate account to the
  /// authoritative account and then removes the duplicate. This is used when
  /// a provider exposes the same bank account through both an account route
  /// and one of its linked cards, or changes an unstable DOM identifier.
  int mergeAccountInto({
    required String duplicateAccountId,
    required String primaryAccountId,
    required String actorId,
    String purpose = 'Merge duplicate financial accounts',
  }) {
    if (duplicateAccountId == primaryAccountId) return 0;
    if (!_accounts.any((item) => item.id == primaryAccountId)) {
      throw StateError('Primary account not found: $primaryAccountId');
    }
    if (!_accounts.any((item) => item.id == duplicateAccountId)) return 0;
    final primary = _accounts.firstWhere((a) => a.id == primaryAccountId);
    final duplicate = _accounts.firstWhere((a) => a.id == duplicateAccountId);
    if (primary.entityId != duplicate.entityId ||
        primary.currency != duplicate.currency) {
      throw StateError(
        'Cannot merge accounts of different entities or currencies',
      );
    }

    var migrated = 0;
    final now = DateTime.now();
    for (var index = 0; index < _transactions.length; index++) {
      final transaction = _transactions[index];
      if (transaction.accountId != duplicateAccountId) continue;
      _transactions[index] = transaction.copyWith(
        accountId: primaryAccountId,
        updatedAt: now,
      );
      migrated += 1;
    }
    _accounts.removeWhere((item) => item.id == duplicateAccountId);
    _audit(
      actorId: actorId,
      action: 'account.merged',
      entityId: _accounts
          .firstWhere((item) => item.id == primaryAccountId)
          .entityId,
      purpose: purpose,
      subjectId: primaryAccountId,
    );
    _emit(
      type: 'account.merged',
      entityId: _accounts
          .firstWhere((item) => item.id == primaryAccountId)
          .entityId,
      subjectId: primaryAccountId,
      payload: {
        'duplicateAccountId': duplicateAccountId,
        'migratedTransactions': migrated,
      },
    );
    _refreshDerivedData();
    return migrated;
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
    if (_transactions[index].status == CanonicalTransactionStatus.deleted) {
      throw StateError('Restore the transaction from trash before editing');
    }
    final previous = _transactions[index];
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
      payload: {
        'actorId': actorId,
        'previousCategory': previous.effectiveCategory,
        'newCategory': _transactions[index].effectiveCategory,
        'previousMerchant': previous.merchantName,
        'newMerchant': _transactions[index].merchantName,
        'previousStatus': previous.status.name,
        'newStatus': _transactions[index].status.name,
      },
    );
    _refreshDerivedData();
  }

  void deleteTransaction(String id, {required String actorId}) {
    final index = _transactionIndexById[id];
    if (index == null) return;
    final transaction = _transactions[index];
    if (transaction.status == CanonicalTransactionStatus.deleted) return;
    final deletedAt = DateTime.now();
    _transactions[index] = transaction.copyWith(
      status: CanonicalTransactionStatus.deleted,
      tags: [
        ...transaction.tags.where((tag) => !tag.startsWith('trash:')),
        'trash:previous-status:${transaction.status.name}',
      ],
      updatedAt: deletedAt,
    );
    _audit(
      actorId: actorId,
      action: 'transaction.deleted',
      entityId: transaction.entityId,
      purpose: 'User removed a transaction from the financial picture',
      subjectId: id,
    );
    _emit(
      type: 'transaction.deleted',
      entityId: transaction.entityId,
      subjectId: id,
      payload: {
        'actorId': actorId,
        'status': 'deleted',
        'previousStatus': transaction.status.name,
        'changedAt': deletedAt.toIso8601String(),
        if (_accounts.any((account) => account.id == transaction.accountId))
          'accountSnapshot': _accounts
              .firstWhere((account) => account.id == transaction.accountId)
              .toJson(),
      },
    );
    _refreshDerivedData();
  }

  void restoreTransaction(CanonicalTransaction transaction) {
    final index = _transactionIndexById[transaction.id];
    if (index != null &&
        _transactions[index].status == CanonicalTransactionStatus.deleted) {
      throw StateError('Use the explicit restore-from-trash command');
    }
    final restored = _enrichment.enrich(
      transaction.copyWith(updatedAt: DateTime.now()),
    );
    if (index == null) {
      _transactionIndexById[restored.id] = _transactions.length;
      _transactions.add(restored);
    } else {
      _transactions[index] = restored;
    }
    _refreshDerivedData();
  }

  bool restoreDeletedTransaction(String id, {required String actorId}) {
    final index = _transactionIndexById[id];
    if (index == null) return false;
    final transaction = _transactions[index];
    if (transaction.status != CanonicalTransactionStatus.deleted) return false;
    var status = CanonicalTransactionStatus.posted;
    final previous = transaction.tags
        .where((tag) => tag.startsWith('trash:previous-status:'))
        .firstOrNull;
    if (previous != null) {
      status = CanonicalTransactionStatus.values.firstWhere(
        (value) =>
            value.name == previous.split(':').last &&
            value != CanonicalTransactionStatus.deleted,
        orElse: () => CanonicalTransactionStatus.posted,
      );
    } else if (transaction.tags.any(
      (tag) => tag == 'status-pending' || tag == 'sber-status-pending',
    )) {
      status = CanonicalTransactionStatus.pending;
    } else if (transaction.tags.any(
      (tag) => tag == 'status-cancelled' || tag == 'sber-status-cancelled',
    )) {
      status = CanonicalTransactionStatus.reversed;
    }
    if (!_accounts.any((account) => account.id == transaction.accountId)) {
      final deletion = _events
          .where(
            (event) =>
                event.subjectId == id && event.type == 'transaction.deleted',
          )
          .lastOrNull;
      final snapshot = deletion?.payload['accountSnapshot'];
      final name = snapshot is Map ? snapshot['name'] as String? : null;
      // Restoring a purchase cannot reconstruct a bank's current balance.
      _accounts.add(
        SynoballAccount(
          id: transaction.accountId,
          entityId: transaction.entityId,
          name: '${name ?? 'Восстановленный счёт'} · баланс не подтверждён',
          type: SynoballAccountType.other,
          currency: transaction.amount.currency,
          balance: Money(minorUnits: 0, currency: transaction.amount.currency),
          isVirtual: true,
        ),
      );
    }
    final restoredAt = DateTime.now();
    _transactions[index] = transaction.copyWith(
      status: status,
      tags: transaction.tags.where((tag) => !tag.startsWith('trash:')).toList(),
      updatedAt: restoredAt,
    );
    _audit(
      actorId: actorId,
      action: 'transaction.restored',
      entityId: transaction.entityId,
      purpose: 'User restored a transaction from trash',
      subjectId: id,
    );
    _emit(
      type: 'transaction.restored',
      entityId: transaction.entityId,
      subjectId: id,
      payload: {
        'actorId': actorId,
        'status': status.name,
        'changedAt': restoredAt.toIso8601String(),
      },
    );
    _refreshDerivedData();
    return true;
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
      ingestionRecords: _ingestionRecords,
      accounts: _accounts,
      sourceCandidates: _candidates,
    );
    final now = DateTime.now();
    late final String transactionId;
    late final bool created;
    if (match == null) {
      if (candidate.canonicalId != null &&
          _transactionIndexById.containsKey(candidate.canonicalId)) {
        // A tombstone or conflicting identity must never produce two rows
        // with the same canonical id. Restoration is a separate user command.
        throw const ReconciliationConflict('existing_canonical_identity');
      }
      transactionId = candidate.canonicalId ?? 'txn-${candidate.id}';
      final createdTransaction = CanonicalTransaction(
        id: transactionId,
        entityId: candidate.entityId,
        accountId: candidate.accountId,
        status: _statusFromCandidate(
          candidate,
          fallback: CanonicalTransactionStatus.posted,
        ),
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
    } else if (match.transaction.status == CanonicalTransactionStatus.deleted) {
      // Record the delivery/evidence below but do not touch the deleted
      // financial values, original lifecycle status, or deletion timestamp.
      transactionId = match.transaction.id;
      created = false;
    } else {
      transactionId = match.transaction.id;
      final index = _transactionIndexById[transactionId]!;
      final current = _transactions[index];
      final existingSources =
          (_evidenceByTransactionId[transactionId] ?? const <SourceEvidence>[])
              .map((item) => item.sourceType)
              .toSet();
      final hasFieldLocks = current.tags.any(
        (tag) => tag.startsWith('user-field:'),
      );
      bool locked(String field) =>
          current.tags.contains('user-field:$field') ||
          (current.fieldTrust == SourceTrustLevel.userConfirmed &&
              !hasFieldLocks);
      var sourceRank = _trustPolicy.rank(current.fieldTrust);
      if (hasFieldLocks &&
          current.fieldTrust == SourceTrustLevel.userConfirmed) {
        sourceRank = 0;
        for (final item
            in _evidenceByTransactionId[transactionId] ?? <SourceEvidence>[]) {
          final rank = _trustPolicy.rank(item.trust);
          if (rank > sourceRank) sourceRank = rank;
        }
      }
      final incomingRecord =
          _ingestionRecords[_ingestionRecordIndexById[candidate
              .ingestionRecordId]!];
      final stale =
          (_evidenceByTransactionId[transactionId] ?? <SourceEvidence>[]).any((
            item,
          ) {
            final index = _ingestionRecordIndexById[item.ingestionRecordId];
            return item.sourceType == sourceType &&
                index != null &&
                item.observedAt.isAfter(incomingRecord.receivedAt);
          });
      final replace =
          !stale && _trustPolicy.rank(candidate.sourceTrust) >= sourceRank;
      final currentAccountIsVirtual = _accounts.any(
        (account) =>
            account.id == current.accountId &&
            account.entityId == current.entityId &&
            account.isVirtual,
      );
      final incomingAccountIsVirtual = _accounts.any(
        (account) =>
            account.id == candidate.accountId &&
            account.entityId == candidate.entityId &&
            account.isVirtual,
      );
      final replaceAccount =
          !incomingAccountIsVirtual &&
          ((replace && !locked('account')) ||
              (currentAccountIsVirtual &&
                  !current.tags.contains('user-field:account')));
      var status = _statusFromCandidate(candidate, fallback: current.status);
      if (stale || _trustPolicy.rank(candidate.sourceTrust) < sourceRank) {
        status = current.status;
      }
      // A pending observation cannot downgrade a posted economic fact.
      if (current.status == CanonicalTransactionStatus.posted &&
          status == CanonicalTransactionStatus.pending) {
        status = current.status;
      }
      final replaceType =
          replace &&
          !locked('type') &&
          candidate.tags.any((tag) => tag.startsWith('legacy-type-'));
      final tags = {
        ...current.tags.where(
          (tag) =>
              !(replaceType && tag.startsWith('legacy-type-')) &&
              !(replaceType &&
                  candidate.tags.any(
                    (value) =>
                        value == 'qesto-internal-transfer' ||
                        value == 'qesto-external-transfer',
                  ) &&
                  (tag == 'qesto-internal-transfer' ||
                      tag == 'qesto-external-transfer')) &&
              !tag.startsWith('sber-status-') &&
              !tag.startsWith('status-'),
        ),
        ...candidate.tags.where(
          (tag) =>
              !tag.startsWith(userLabelPrefix) &&
              (replaceType || !tag.startsWith('legacy-type-')) &&
              !tag.startsWith('sber-status-') &&
              !tag.startsWith('status-'),
        ),
        'status-${status == CanonicalTransactionStatus.reversed ? 'cancelled' : status.name}',
      }.toList();
      if ((replaceAccount
              ? incomingAccountIsVirtual
              : currentAccountIsVirtual) ==
          false) {
        tags.remove('sber-account-unresolved');
      }
      final replaceTime =
          !stale &&
          !locked('date') &&
          _shouldReplaceOccurredAt(
            current: current,
            candidate: candidate,
            incomingSource: sourceType,
            existingSources: existingSources,
          );
      final replaceMerchant =
          !stale &&
          !locked('merchant') &&
          candidate.merchantGuess?.trim().isNotEmpty == true &&
          (_sourceDetailRank(sourceType) >=
                  _bestSourceDetailRank(existingSources) ||
              current.merchantName == null);
      final replaceDescription =
          !stale &&
          !locked('description') &&
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
          accountId: replaceAccount ? candidate.accountId : current.accountId,
          amount: replace && !locked('amount')
              ? candidate.amount
              : current.amount,
          direction: replaceType ? candidate.direction : current.direction,
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
          userCategoryOverride: locked('category')
              ? current.userCategoryOverride
              : candidate.userCategoryOverride ?? current.userCategoryOverride,
          categoryConfidence:
              candidate.categoryGuess != null &&
                  mergedSynoballCategory == candidate.categoryGuess
              ? candidate.confidence
              : current.categoryConfidence,
          subcategoryId:
              !locked('subcategory') &&
                  candidate.subcategoryId != null &&
                  (replace || current.subcategoryId == null)
              ? candidate.subcategoryId
              : current.subcategoryId,
          transferDirection: replaceType
              ? candidate.transferDirection ?? current.transferDirection
              : current.transferDirection,
          clearTransferDirection:
              replaceType && candidate.transferDirection == null,
          status: status,
          receiptId: candidate.receiptId ?? current.receiptId,
          tags: tags,
          updatedAt: now,
          fieldTrust: hasFieldLocks
              ? current.fieldTrust
              : replace
              ? candidate.sourceTrust
              : current.fieldTrust,
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
    SourceEvidence? repeated;
    if (providerTransactionId != null) {
      for (final item
          in _evidenceByTransactionId[transactionId] ?? <SourceEvidence>[]) {
        if (item.sourceType != sourceType ||
            item.providerTransactionId != providerTransactionId) {
          continue;
        }
        if (_candidates.any(
          (prior) =>
              prior.id != candidate.id &&
              prior.ingestionRecordId == item.ingestionRecordId &&
              _sameObservation(prior, candidate),
        )) {
          repeated = item;
        }
      }
    }
    final alreadyObserved = repeated != null;
    final observedAt =
        _ingestionRecords[_ingestionRecordIndexById[candidate
                .ingestionRecordId]!]
            .receivedAt;
    if (!alreadyObserved) {
      final item = SourceEvidence(
        id: _ids.next('evd'),
        transactionId: transactionId,
        sourceType: sourceType,
        ingestionRecordId: candidate.ingestionRecordId,
        confidence: candidate.confidence,
        trust: candidate.sourceTrust,
        observedAt: observedAt,
        providerTransactionId: providerTransactionId,
      );
      _evidence.add(item);
      _indexEvidence(item);
    } else if (observedAt.isAfter(repeated.observedAt)) {
      // Coalesce an identical observation but retain the latest delivery link
      // and observation time. Changed provider observations get new evidence.
      final refreshed = SourceEvidence(
        id: repeated.id,
        transactionId: transactionId,
        sourceType: sourceType,
        ingestionRecordId: candidate.ingestionRecordId,
        confidence: candidate.confidence,
        trust: candidate.sourceTrust,
        observedAt: observedAt,
        providerTransactionId: providerTransactionId,
      );
      _evidence[_evidence.indexWhere((item) => item.id == repeated!.id)] =
          refreshed;
      final indexed = _evidenceByTransactionId[transactionId]!;
      indexed[indexed.indexWhere((item) => item.id == repeated!.id)] =
          refreshed;
    }
    final candidateIndex = _candidateIndexById[candidate.id]!;
    _candidates[candidateIndex] = candidate.copyWith(
      status: created ? CandidateStatus.confirmed : CandidateStatus.merged,
      tags: [
        ...candidate.tags,
        if (match?.transaction.status == CanonicalTransactionStatus.deleted)
          'user-deletion-suppressed',
      ],
    );
    return _ReconciliationResult(
      transactionId: transactionId,
      created: created,
      suppressed:
          match?.transaction.status == CanonicalTransactionStatus.deleted,
    );
  }

  bool _sameObservation(
    TransactionCandidate left,
    TransactionCandidate right,
  ) =>
      left.providerTransactionId == right.providerTransactionId &&
      left.accountId == right.accountId &&
      left.entityId == right.entityId &&
      left.amount.minorUnits == right.amount.minorUnits &&
      left.amount.currency == right.amount.currency &&
      left.direction == right.direction &&
      left.occurredAt == right.occurredAt &&
      left.rawDescription == right.rawDescription &&
      left.merchantGuess == right.merchantGuess &&
      left.categoryGuess == right.categoryGuess &&
      left.providerCategory == right.providerCategory &&
      left.userCategoryOverride == right.userCategoryOverride &&
      left.subcategoryId == right.subcategoryId &&
      left.transferDirection == right.transferDirection &&
      left.receiptId == right.receiptId &&
      _observationTags(left).length == _observationTags(right).length &&
      _observationTags(left).containsAll(_observationTags(right));

  Set<String> _observationTags(TransactionCandidate candidate) =>
      candidate.tags.where((tag) => tag != 'user-deletion-suppressed').toSet();

  /// Bank feeds may observe the same operation while it is processing and
  /// later report it as posted (or cancelled).  Keep that lifecycle in the
  /// canonical transaction instead of treating the status tag as UI-only.
  /// The adapter remains the owner of provider-specific tags; Synoball only
  /// understands the small, stable status vocabulary below.
  CanonicalTransactionStatus _statusFromCandidate(
    TransactionCandidate candidate, {
    required CanonicalTransactionStatus fallback,
  }) {
    final tags = candidate.tags.map((value) => value.toLowerCase()).toSet();
    if (tags.contains('sber-status-pending') ||
        tags.contains('status-pending')) {
      return CanonicalTransactionStatus.pending;
    }
    if (tags.contains('sber-status-cancelled') ||
        tags.contains('status-cancelled')) {
      return CanonicalTransactionStatus.reversed;
    }
    if (tags.contains('sber-status-posted') ||
        tags.contains('status-posted') ||
        tags.contains('sber-status-refund') ||
        tags.contains('status-refund')) {
      return CanonicalTransactionStatus.posted;
    }
    return fallback;
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
  if ((incomingSource == SynoballSourceType.statement ||
          incomingSource == SynoballSourceType.bankScreenshot) &&
      incomingIsDateOnly &&
      currentHasTime) {
    return false;
  }
  return true;
}

int _timePrecisionRank(SynoballSourceType source) => switch (source) {
  SynoballSourceType.receipt => 6,
  SynoballSourceType.manual || SynoballSourceType.manualVoice => 5,
  SynoballSourceType.androidNotification ||
  SynoballSourceType.smsNotification => 5,
  SynoballSourceType.bankWeb ||
  SynoballSourceType.directApi ||
  SynoballSourceType.regulatedApi => 4,
  SynoballSourceType.bankScreenshot => 3,
  SynoballSourceType.statement => 2,
  SynoballSourceType.legacy || SynoballSourceType.modelInference => 1,
};

int _sourceDetailRank(SynoballSourceType source) => switch (source) {
  SynoballSourceType.receipt => 6,
  SynoballSourceType.manual || SynoballSourceType.manualVoice => 5,
  SynoballSourceType.bankWeb ||
  SynoballSourceType.directApi ||
  SynoballSourceType.regulatedApi => 5,
  SynoballSourceType.bankScreenshot => 4,
  SynoballSourceType.statement => 4,
  SynoballSourceType.androidNotification ||
  SynoballSourceType.smsNotification => 3,
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
    this.suppressed = false,
  });
  final String transactionId;
  final bool created;
  final bool suppressed;
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
