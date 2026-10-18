# Stage 4d — bounded experiment and required next contract

This is NOT a production implementation proposal approved for execution. Only
synthetic Windows data; no protocol, schema, migration or installation changes.

## What the experiment proves

`DomainEffectsV1.between` can unambiguously capture all effects **by comparing the
full real before/after codec-v7 result**. It includes every root and every core
collection, per-transaction changed fields, audit/events, tombstones, evidence,
recurrence/enrichment and classification. Values are deep read-only JSON; the
base document digest rejects reconstruction against a different base. No aliases
are produced by the only supported command, `transaction.set_note`. Unsupported
kinds reject in the existing strict parser, never degrade to note edits.

The stale-policy fixture changes 21 canonical transactions for one note. Repeating
an identical note can change only audit/events. Neither target-ID-only deltas nor
`changedTransactions.isEmpty` are valid commit/publication shortcuts.

This envelope is **local oracle capture**, not a network patch, new financial
algorithm, transaction receipt, or hot-path incremental effect API. Its full-root
values must NOT be wired into UI/storage as if they were cheap minimal deltas.

## Concrete blocker: complete cheap effects are not exposed

The current core mutates owned collections and exposes complete state. Construction
applies category policy to every canonical transaction and rebuilds recurrence;
update/enrichment also rebuilds derived recurrence. Some canonical changes are not
individual audit events. The caller cannot infer all effects from the command,
target, event list, or returned boolean. The full diff oracle is correct but scans,
serializes and retains entire profiles. Profiling quantifies this cost separately.

`forkForCommand` skips **re-initialization only**, not any mutation rule. It still
copies list/index containers and executes global derivation and full legacy/Sber
projection. No O(1) claim. The shared API assumes exclusive ownership of model
values; existing models are not deeply immutable. Do not expose a prepared owner
to code that mutates returned nested lists/maps. No production caller uses it.

## Minimum additive contract requiring a separate reviewed slice

1. A core-owned `PreparedCommandEffects` transaction scope. All authoritative
   collection writes (including configured-policy initialization and recurrence)
   must report replacements/removals, stable IDs, ordered audit/event appends and
   derived invalidations. It must collect constructor normalization relative to
   the persisted base, not silently treat it as already persisted.
2. Versioned binding: workspace, lineage, owner generation, local revision,
   authoritative server sequence, pending-command-set digest, policy fingerprint,
   domain version and conflict state. Reject unknown versions. Existing core
   constructors/public financial methods retain their results.
3. Prepared fork cannot publish itself. Container returns an opaque durable token
   binding the exact effect-set, immutable command ID and revision. Only the owner
   may promote; rollback discards; unknown commit discards and reloads by command ID.
   Remote page + shadow + cursor + conflicts + pending replay promote together.
4. Typed presentation changes derived using the **existing** projection functions,
   initially full fallback for any untracked dependencies. UI requires matching
   base revision/generation and command receipt. Cancellation after commit reloads;
   duplicate delivery is acknowledged without re-publication. No financial math in
   UI and no network JSON Patch.
5. Isolate ownership: one durable writer, at most one speculative fork and bounded
   queue (current 16). Policy/import/restore/remote/unknown outcomes invalidate or
   explicitly replace the complete binding; unsupported commands use full path.

This requires instrumenting core writes and changing several experiment boundary
interfaces together. It is not just a cache getter or a direct SQL UPDATE note.
Do not implement it as an unreviewed expansion of this experiment.

## v1 integrity/server limits

Protocol v1 commits to full canonical JSON digests; SHA-256(full ordered bytes)
cannot be recomposed from unrelated chunk hashes. `streaming_digest.dart` explores
exact-byte hashing with bounded encoding buffers, not a new digest. It stays off
the wire/hot path. Format 1 and format 2 remain unchanged.

The server locks the workspace row, reads full codec text and revisions, executes
the existing algorithm, and atomically stores full text, transactional receipt and
immutable change log. An in-memory owner may only be promoted **after** PostgreSQL
COMMIT; it must revalidate DB revision under lock on every reuse, including another
process's commits. Cache authority cannot replace the workspace lock or RLS.

A future internal entity/chunk table may reduce PostgreSQL payload, but needs full
effect contract above and reconstructable ordered codec export. A new Merkle/effect
digest would be an explicit negotiated protocol v2, with v1 full-state fallback,
version refusal tests, dual verification and migration/rollback approval. Neither
schema nor protocol is changed here.

## Memory ownership policy (implemented vs proposed)

| Lifetime / buffer | Stage 4d status |
|---|---|
| Decoded executor cache | Implemented: one exact owner+source entry, 32 MiB admission estimate; source UTF-16 length ×16, old graph dropped BEFORE decoding; oversized entries uncached |
| Prepared domain owner | POC: one current model/core + one speculative fork per serial caller; no extra decoded LRU; explicit invalidation/reload |
| Storage read cache | Unchanged: verified DB identity/total_changes/data_version/manifest; proposed combined 64 MiB UTF-16 payload budget, not enabled |
| FinancialSnapshot cache | Unchanged: two exact JSON values; proposed shared budget with read cache to avoid accounting aliases twice |
| Staged state/shadow | Unchanged: temporary transaction references cleared in finally; no promotion before COMMIT |
| SendPort / controller | Unchanged full envelope; proposed typed committed effects, only after all required invalidations proved |
| Server | Implemented same bounded decode admission; full state/response buffers remain request-scoped; no prepared-owner promotion |

The ×16 estimate is conservative admission accounting, **not** a measured hard
bound on the Dart heap or process RSS. The cache cannot hide DB corruption: it is
only consulted after storage supplies a verified full source; mismatched sources
and tenants clear/revalidate. A cache-rejection test is not a native OOM test.

## Explicitly not implemented

No partial UI application, incremental core mutation journal, server/entity schema,
partial integrity protocol, production owner, new financial engine, real profile
read/write, Android integration or deployment. Existing full fallback remains the
only end-to-end execution path; the memory harness changes retention only.
