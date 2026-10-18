# Stage 4e — typed proposal only, not installed or wired

The journal proves core collection effects, not that SQLite committed anything.
`CoreJournalPreparation` is speculative even after `finish`. Calling `prepareNext`
in tests is sequencing test candidates, not durable promotion. No live coordinator
uses these APIs; its full serialization/verification paths remain unchanged.

## Required next interface (Stage 4f, separate approval)

```dart
// Conceptual types, not APIs implemented in this stage.
final class PreparedFinancialCommit {
  final OwnerBinding owner; // workspace, lineage, generation,
  // local revision, server sequence, pending-set digest, conflict generation
  final ImmutableCommand command;
  final CoreEffectsJournal coreEffects;
  final AppProjectionEffects appEffects; // separate versioned coverage!
  final Digest effectsDigest; // binding + core/app effects + invalidations
}

abstract interface class TransactionContainer {
  Future<DurableReceipt> commitPrepared(PreparedFinancialCommit prepared);
  Future<VerifiedCommandOutcome> resolveUnknownOutcome(CommandId id);
}
// Private constructor; issued only by that container after real SQLite COMMIT.
// A publicly constructed DTO, RAM Boolean or callback is not evidence of commit.
final class DurableReceipt {
  final WorkspaceId workspace;
  final ProfileLineage lineage;
  final CommandId commandId;
  final Revision baseRevision, committedRevision;
  final DomainVersion domainVersion;
  final PolicyFingerprint policyFingerprint;
  final Digest effectsDigest;
  final StorageGeneration storageGeneration;
  final OwnerGeneration ownerGeneration;
}
```

One writer owns preparation and storage. Queue stays bounded. Only one candidate
may be outstanding for a given revision; two preparations of the same target do
not both become committed. The journal itself does NOT arbitrate those conflicts.

1. Load and verify encrypted state, codec/domain version and complete owner binding.
2. Freeze/admit records once. Record constructor normalization relative to persisted
   state; NEVER silently promote initialized policy changes as durable.
3. Execute the existing bridge/core, freeze effects. Unknown versions/commands,
   untracked projection dependencies or policy changes use full reload/fallback.
4. In a single SQLite transaction check base revision/generation, write financial
   rows, command/outbox, local revision and effects/receipt. Remote bundles also
   atomically bind shadow, pending replay, conflicts, cursor, aliases and coverage.
5. After COMMIT issue receipt bound to the exact immutable prepared digest. Before
   COMMIT, cancellation/error discards the candidate. After COMMIT, cancellation
   means lookup/reload, never a pretend rollback. Unknown outcome invalidates RAM
   and resolves immutable command ID before another submission.
6. Promote only if all receipt fields and digest match the current owner. Stale
   policy/revision/generation and another workspace/command are rejected. Restart
   cannot reuse an old RAM owner or serialized journal as authority.
7. Publish typed app presentation updates only after promotion. Apply once by
   receipt/revision; stale/disposed controllers reload. No raw network JSON Patch.

## Core vs app projection gate

The core journal includes constructor policy normalization, canonical/evidence/
audit/recurrence/trash effects. It does NOT include app accounts/transactions,
classification settings, budgets/goals/debts, UI selectors or analytics caches.
`QestoLegacyBridge.canonicalFromQesto` supplies the edited canonical value; the
journal records the write, not an alternative interpretation of the edit.
`QestoReadModelService` and `projectSberTransactions` are still full projections.
Their input/output dependency contract must be versioned and compared to full
codec-v7 before enabling partial publication. An unsupported projection requires
the existing complete result, even if the core journal is complete.

## Integrity and wire compatibility

Core binding's policy fingerprint is caller-supplied metadata; the experimental
app seam validates it against actual classification settings. The journal also
contains the actual configured policy and detects policy changes during execution.
That detection forces re-admission before another prepared fork. Policy authority,
workspace authorization and command parsing remain the owner's responsibilities.

Future effect digest must use canonical, versioned ordering and include every
binding field. It supplements, not silently replaces, v1 full-state digests.
Neither network v1, SQLite format 1/2, encryption, PostgreSQL schema nor financial
record IDs change in 4e. No claim of exactly-once durability from this POC alone.

## Mandatory 4f gates

Real SQLite COMMIT proof and failure/unknown-outcome recovery; two competing edits;
policy/remote invalidation; stale receipt substitution; once-only incoming UI;
full codec/canonical/legacy parity; all old format1/2 crash/security regressions.
Only synthetic Windows data. Production integration remains a separate decision.
