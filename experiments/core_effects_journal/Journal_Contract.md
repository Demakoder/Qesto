# Experimental core effects v1

Scope: existing Synoball serialized collections, **not** a replacement for codec-v7,
Sync Protocol v1, `DomainEffectsV1`, `CommittedTransactionNote` or a DB receipt.
Only the synthetic app `transaction.set_note` seam is enabled. Additional core
lifecycle tests are coverage probes, not newly supported network commands.

## Binding

`CoreEffectsBinding` is immutable local metadata:

| Field | Meaning |
|---|---|
| commandId | Existing immutable command identifier; journal creates no financial IDs |
| workspace, lineage | Logical owner; must match across prepared generations |
| target, kind | App validates supported kind and exact displayed target |
| baseRevision | Nonnegative expected revision; proposed next revision = base + 1 |
| generation | Local owner generation, not a storage commit generation |
| domainVersion | Exact current Synoball model version; future values rejected |
| policyFingerprint | Supplied by trusted owner; app seam verifies classification digest |

No authentication, signature, storage proof or global command deduplication is
provided by this binding. It must never be accepted from an untrusted caller as
proof of authority. The core callback is trusted synchronous code, not a parser.

## Journal and effects

`contract = qesto.experimental-core-effects.v1`, integer `version = 1`.

`writes` is an ordered, immutable sequence of collection writes. Each contains
`collection`, `index`, `id`, `before`, `after`, derived `kind` and `changedFields`.
Values are detached deeply read-only JSON. `before == null` means append at index;
`after == null` means physical removal at index; both present means replacement.
Replay must check the expected before value and exact append index. Indexes
preserve current list order and even duplicate IDs; this is not a SQL row key.

Writes to the same slot are coalesced before a structural removal. Removal clears
coalescing indexes for that collection so subsequent shifted positions remain
unambiguous. Net no-op writes are omitted on sealing. Audit/events themselves are
not omitted merely because a canonical transaction was unchanged.

Derived read-only sets `changedCanonicalIds` and `changedCollections` include every
retained effect, not just `binding.target`. The JSON writes carry the same IDs;
the sets do not duplicate serialized payload. Changed field values remain in the
complete before/after records (including locks/tags, provider/source IDs, amounts,
currency, transfer direction, confidence, timestamps and deletion status).

Tombstones are canonical **updates**. Source mappings/merge aliases use the
existing event/account/canonical structures, not a new aliases model.

`configuredPolicy` contains the actual final rules, redirects and valid tag IDs.
`policyChangedDuringExecution` compares actual policies at callback entry/exit;
a change invalidates prepared reuse. Constructor normalization is recorded against
the original input state even before callback execution. No claim is made that
the caller's fingerprint is cryptographically tied to durable storage.

Conservative invalidations on any writes **or policy change**:
`core-read-model`, `recurring`, `app-projections-require-full-fallback`.
They are invalidation hints, not computed UI deltas.

## Coverage and rejection

`coverage = core-collections-only`, `coreCollectionsComplete = true` is emitted
only after successful tracked execution/sealing of the current 15 collections.
The exact list is in `Mutation_Map.md`. It does **not** assert completeness for
app roots, projections, shadow/pending/conflicts, SQLite or UI. Completeness means
observable persisted core values; derived in-memory indexes are private runtime
state and are not independent financial facts.

Schema/model mismatch, unreviewed top-level model subclasses, custom policy
subclasses, unsupported JSON, unsupported list operations and async preparation
throw. No empty profile, empty successful journal or implicit lossy fallback is
created. The caller must either retain the existing full path or report failure.
No new path is installed in an existing caller.

This v1 is coupled to current model fields. Adding a collection/mutable field or
changing serialization requires ownership review, full oracle tests and contract
version review. `true` is not a guarantee about arbitrary future implementations.

## State ownership and lifecycle

`fromState` admits existing base models, detaches/freezes mutable containers once,
initializes the **existing** core and captures its initialization effects.
`prepareNext` only forks an owned prepared core, sharing immutable values while
copying lists and indexes. New records are frozen at writes. It rejects foreign
workspace/lineage, changed policy/version, nonsequential revision/generation,
immediate command-ID reuse and reuse after policy change. Actual durable revision
authority, historic command-ID idempotency and concurrent winners remain outside
this API. Calling it in a test does not promote an owner.

Scopes seal on success or failure; speculative state is never published to the
app. Public mutations that could write private indexes before a tracked list
(`restoreTransaction`) are guarded before index mutation. Async callbacks reject;
retaining a callback reference is not a way to reopen the scope.

`recordingMicros` measures individual record comparison/JSON capture/freeze work
inside the recorder; excludes admission, record ownership copying, core scans,
forks, finalization, result encoding and independent oracle verification. Use the
benchmark's complete preparation metrics to assess overhead, not this counter alone.

## Independent oracle

The experiment reconstructs the full original core JSON by ordered replay and
compares every collection/field to the result of the existing ordinary core.
Note commands additionally compare complete codec-v7 output from the actual
existing app bridge/projections and old `DomainEffectsV1` oracle. Deliberately
removed effects, foreign preconditions and unregistered field changes must fail.
The oracle is deliberately O(N) and stays outside capture timing/hotpath.

There is deliberately no production decoder/applier for a serialized journal.
Restart reloads verified full state. A future durable receipt and app effects
contract are specified separately in `Durable_Publication_Proposal.md`.
