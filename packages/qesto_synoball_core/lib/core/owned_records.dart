part of 'synoball_core.dart';

// Only the opt-in journal boundary uses these copies. No production serializer,
// IDs or model constructors are changed. Admission is O(N) once; writes freeze
// only their own nested collections. Forks reuse these owned immutable records.
T _ownRecord<T>(T record) {
  // A subclass may add mutable state or override financial semantics. Do not
  // silently erase it while copying into one of the reviewed base models.
  if (!const <Type>{
    SynoballEntity,
    Institution,
    SynoballConnection,
    SynoballConsent,
    SynoballAccount,
    RawPayload,
    IngestionRecord,
    TransactionCandidate,
    CanonicalTransaction,
    SourceEvidence,
    SynoballReceipt,
    ImportBatch,
    RecurringStream,
    SynoballEvent,
    SynoballAuditEntry,
  }.contains(record.runtimeType)) {
    throw UnsupportedError('Unreviewed journal model; use full path');
  }
  return (switch (record) {
        CanonicalTransaction t => t.copyWith(tags: List.unmodifiable(t.tags)),
        TransactionCandidate t => t.copyWith(tags: List.unmodifiable(t.tags)),
        ImportBatch t => t.copyWith(warnings: List.unmodifiable(t.warnings)),
        SynoballEvent e => SynoballEvent(
          id: e.id,
          type: e.type,
          entityId: e.entityId,
          subjectId: e.subjectId,
          occurredAt: e.occurredAt,
          payload: _freezeJson(e.payload) as Map<String, dynamic>,
        ),
        SynoballConsent c => SynoballConsent.fromJson(
          _freezeJson(c.toJson()) as Map<String, dynamic>,
        ),
        SynoballConnection c => SynoballConnection(
          id: c.id,
          entityId: c.entityId,
          institutionId: c.institutionId,
          status: c.status,
          method: c.method,
          capabilities: List.unmodifiable(c.capabilities),
          lastSyncedAt: c.lastSyncedAt,
          syncCursor: c.syncCursor,
          consentId: c.consentId,
          adapterId: c.adapterId,
          adapterVersion: c.adapterVersion,
          lastErrorCode: c.lastErrorCode,
          providerError: c.providerError,
        ),
        SynoballReceipt r => SynoballReceipt(
          id: r.id,
          ingestionRecordId: r.ingestionRecordId,
          purchasedAt: r.purchasedAt,
          total: r.total,
          fiscalFingerprint: r.fiscalFingerprint,
          rawText: r.rawText,
          merchant: r.merchant,
          items: List.unmodifiable(r.items),
          confidence: r.confidence,
          userCorrections: Map.unmodifiable(r.userCorrections),
        ),
        RecurringStream r => RecurringStream(
          id: r.id,
          entityId: r.entityId,
          merchantKey: r.merchantKey,
          title: r.title,
          typicalAmount: r.typicalAmount,
          frequency: r.frequency,
          nextExpectedAt: r.nextExpectedAt,
          confidence: r.confidence,
          transactionIds: List.unmodifiable(r.transactionIds),
        ),
        SynoballEntity() ||
        Institution() ||
        SynoballAccount() ||
        RawPayload() ||
        IngestionRecord() ||
        SourceEvidence() ||
        SynoballAuditEntry() => record,
        _ => throw StateError('Unreviewed model at journal ownership boundary'),
      })
      as T;
}

Map<String, dynamic> _recordJson(Object r) => switch (r) {
  SynoballEntity v => v.toJson(),
  Institution v => v.toJson(),
  SynoballConnection v => v.toJson(),
  SynoballConsent v => v.toJson(),
  SynoballAccount v => v.toJson(),
  RawPayload v => v.toJson(),
  IngestionRecord v => v.toJson(),
  TransactionCandidate v => v.toJson(),
  CanonicalTransaction v => v.toJson(),
  SourceEvidence v => v.toJson(),
  SynoballReceipt v => v.toJson(),
  ImportBatch v => v.toJson(),
  RecurringStream v => v.toJson(),
  SynoballEvent v => v.toJson(),
  SynoballAuditEntry v => v.toJson(),
  _ => throw StateError('Unknown journal record'),
};

CategoryPolicy _ownPolicy(CategoryPolicy p) {
  if (p.runtimeType != CategoryPolicy) {
    throw UnsupportedError('Custom category policy requires the full path');
  }
  return CategoryPolicy(
    rules: List.unmodifiable(p.rules),
    redirects: Map.unmodifiable(p.redirects),
    validTagIds: p.validTagIds == null
        ? null
        : Set.unmodifiable(p.validTagIds!),
  );
}

Map<String, dynamic> _policyJson(CategoryPolicy p) => {
  'rules': p.rules.map((r) => r.toJson()).toList(),
  'redirects': p.redirects,
  'validTagIds': p.validTagIds?.toList(),
};
