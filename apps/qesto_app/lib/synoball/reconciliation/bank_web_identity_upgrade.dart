import '../core/models.dart';

/// Both IDs must be derived by the adapter from the SAME source row, never
/// guessed by sorting equal payments. This is an identity-version bridge.
class BankWebIdentityUpgrade {
  const BankWebIdentityUpgrade({
    required this.canonicalId,
    required this.providerId,
    required this.legacyIds,
    required this.amount,
    required this.direction,
    required this.occurredAt,
    required this.description,
  });
  final String canonicalId, providerId, description;
  final List<String> legacyIds;
  final Money amount;
  final FinancialDirection direction;
  final DateTime occurredAt;
}

class BankWebIdentityUpgradeResult {
  const BankWebIdentityUpgradeResult(this.state, this.targets);
  final SynoballState state;
  final Map<String, String> targets;
}

/// Repairs proven identity changes before ingestion, in its staged state. Old
/// canonical IDs survive. Original payloads/candidates/audit history are retained.
class BankWebIdentityReconciler {
  const BankWebIdentityReconciler();

  BankWebIdentityUpgradeResult apply(
    SynoballState state, {
    required String entityId,
    required String connectionId,
    required String institutionId,
    required Iterable<BankWebIdentityUpgrade> upgrades,
    Set<String> protectedTransactionIds = const {},
    DateTime? now,
  }) {
    final transactions = {for (final t in state.transactions) t.id: t};
    final accounts = {for (final a in state.accounts) a.id: a};
    final records = {for (final r in state.ingestionRecords) r.id: r};
    final targets = <String, String>{};
    final merged = <String, String>{};
    final events = <SynoballEvent>[];
    final audit = <SynoballAuditEntry>[];
    final claims = <String, Set<String>>{};
    for (final u in upgrades) {
      for (final id in u.legacyIds) {
        claims.putIfAbsent(id, () => {}).add(u.providerId);
      }
    }
    bool scope(CanonicalTransaction t, {required bool legacy}) {
      final sources = state.evidence.where((e) => e.transactionId == t.id);
      if (sources.isEmpty) return false;
      final account = accounts[t.accountId];
      // Legacy ingestion omitted connection metadata; a later explicitly scoped
      // account is the only permissible fallback. Missing scope is not a wildcard.
      return sources.every((e) {
        final r = records[e.ingestionRecordId];
        if (e.sourceType != SynoballSourceType.bankWeb || r == null) {
          return false;
        }
        return (r.connectionId ?? (legacy ? account?.connectionId : null)) ==
                connectionId &&
            (r.institutionId ?? (legacy ? account?.institutionId : null)) ==
                institutionId;
      });
    }

    bool sameFact(CanonicalTransaction t, BankWebIdentityUpgrade u) =>
        t.entityId == entityId &&
        t.amount.minorUnits == u.amount.minorUnits &&
        t.amount.currency == u.amount.currency &&
        t.direction == u.direction &&
        t.occurredAt == u.occurredAt &&
        t.rawDescription == u.description;

    for (final u in upgrades) {
      final legacy = u.legacyIds
          .toSet()
          .map((id) => transactions[id])
          .whereType<CanonicalTransaction>()
          .where(
            (t) =>
                claims[t.id]?.length == 1 &&
                sameFact(t, u) &&
                scope(t, legacy: true) &&
                state.evidence.any(
                  (e) =>
                      e.transactionId == t.id &&
                      e.providerTransactionId == t.id,
                ),
          )
          .toList();
      if (legacy.length != 1) continue;
      final old = legacy.single;
      final current = transactions[u.canonicalId];
      if (current != null && current.id != old.id) {
        if (protectedTransactionIds.contains(current.id)) continue;
        if (!sameFact(current, u) ||
            !scope(current, legacy: false) ||
            !state.evidence.any(
              (e) =>
                  e.transactionId == current.id &&
                  e.providerTransactionId == u.providerId,
            )) {
          continue;
        }
        if (old.accountId != current.accountId &&
            accounts[old.accountId]?.isVirtual != true &&
            accounts[current.accountId]?.isVirtual != true) {
          continue;
        }
        // Conflicting user edits/deletions require an explicit review, not an
        // automatic repair. This also protects unrelated custom relationships.
        if ([
              old,
              current,
            ].any((t) => t.status != CanonicalTransactionStatus.posted) ||
            (current.userCategoryOverride != null &&
                current.userCategoryOverride != old.userCategoryOverride) ||
            current.receiptId != null ||
            current.tags.any(
              (tag) =>
                  tag.startsWith('user-field:') ||
                  tag == 'qesto-manual-category',
            ) ||
            (old.tags.contains('user-field:account') &&
                old.accountId != current.accountId) ||
            state.events.any(
              (e) =>
                  (e.type == 'transaction.refund-linked' ||
                      e.type == 'transaction.transfer-linked') &&
                  (e.subjectId == current.id ||
                      e.payload.values.contains(current.id)),
            )) {
          continue;
        }
        final account =
            accounts[old.accountId]?.isVirtual == true &&
                accounts[current.accountId]?.isVirtual == false
            ? current.accountId
            : old.accountId;
        transactions[old.id] = old.copyWith(
          accountId: account,
          tags: {...old.tags, ...current.tags}
              .where(
                (tag) =>
                    tag != 'sber-account-unresolved' ||
                    accounts[account]?.isVirtual == true,
              )
              .toList(),
          updatedAt: now ?? DateTime.now(),
        );
        transactions.remove(current.id);
        merged[current.id] = old.id;
        final eventId = 'identity-upgrade:${current.id}:${old.id}';
        events.add(
          SynoballEvent(
            id: eventId,
            type: 'transaction.identity-reconciled',
            entityId: entityId,
            subjectId: old.id,
            occurredAt: now ?? DateTime.now(),
            payload: {
              'previousTransactionId': current.id,
              'proof': 'adapter_legacy_fingerprint',
              'connectionId': connectionId,
            },
          ),
        );
        audit.add(
          SynoballAuditEntry(
            id: 'audit:$eventId',
            actorId: 'synoball',
            action: 'transaction.identity-reconciled',
            entityId: entityId,
            subjectId: old.id,
            purpose:
                'Same source row reproduced legacy and scoped provider identities',
            occurredAt: now ?? DateTime.now(),
          ),
        );
      }
      targets[u.canonicalId] = old.id;
    }
    if (merged.isEmpty) return BankWebIdentityUpgradeResult(state, targets);
    return BankWebIdentityUpgradeResult(
      SynoballState(
        schemaVersion: state.schemaVersion,
        modelVersion: state.modelVersion,
        entities: state.entities,
        institutions: state.institutions,
        connections: state.connections,
        consents: state.consents,
        accounts: state.accounts,
        rawPayloads: state.rawPayloads,
        ingestionRecords: state.ingestionRecords,
        candidates: [
          for (final c in state.candidates)
            merged.containsKey(c.canonicalId)
                ? TransactionCandidate.fromJson({
                    ...c.toJson(),
                    'canonicalId': merged[c.canonicalId],
                  })
                : c,
        ],
        transactions: transactions.values.toList(),
        evidence: [
          for (final e in state.evidence)
            if (merged.containsKey(e.transactionId))
              SourceEvidence(
                id: e.id,
                transactionId: merged[e.transactionId]!,
                sourceType: e.sourceType,
                ingestionRecordId: e.ingestionRecordId,
                confidence: e.confidence,
                trust: e.trust,
                observedAt: e.observedAt,
                providerTransactionId: e.providerTransactionId,
              )
            else
              e,
        ],
        receipts: state.receipts,
        importBatches: state.importBatches,
        recurringStreams: [
          for (final r in state.recurringStreams)
            RecurringStream.fromJson({
              ...r.toJson(),
              'transactionIds': r.transactionIds
                  .map((id) => merged[id] ?? id)
                  .toSet()
                  .toList(),
            }),
        ],
        events: [...state.events, ...events],
        auditEntries: [...state.auditEntries, ...audit],
      ),
      targets,
    );
  }
}
