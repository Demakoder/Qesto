# Deferred proposal — NOT implemented, not authorized for production

Stage 4c chunks reduce physical writes without inventing a financial model.
They cannot make all processing O(changed entities): the existing shared core
constructor reapplies configured policy and rebuilds recurring derived state;
the app preparation constructs all legacy projections; v1 authenticates effects
using full before/after canonical digests. SQL patching one note would skip real
multi-entity effects. Full decode/encode/replay remains necessary at this boundary.

## Smallest next architecture decision

1. Give shared Synoball an explicit, versioned mutation-result contract containing
   changed canonical IDs, removals/tombstones, audit/events and global derived
   invalidations. Preserve the exact existing executor as full parity oracle.
   Distinguish loading a verified current-policy state from applying a new policy.
   Do not assume a note always changes exactly one entity.
2. Use a long-lived domain owner with revision/policy/core-version binding, plus
   bounded legacy/UI deltas. A failed/unknown commit cannot publish its speculative
   state. Dispose/restart loads verified authoritative chunks, never old caches.
3. PostgreSQL: under the EXISTING workspace row lock, retain RLS, receipt/bundle
   journal and head in one transaction. Physical v2 workspace manifest/chunk rows
   can replace the opaque `workspace.state` TEXT without a second snapshot copy.
   All row writes still derive from shared executor, not client JSON Patch.
   Changing this schema requires explicit synthetic migration and tenant/security
   regressions before any production decision. Not performed in this slice.
4. If full-core digests/replay are to become incremental, negotiate an opt-in
   `financial_profile=qesto.note.v2` with core/policy versions and a specified
   Merkle-root format. Bind target base revision, immutable command/time, complete
   effect set and all affected subtree proofs. V1 clients keep v1 full replay;
   unknown v2 rejects before durable mutation/cursor movement. Never silently
   reinterpret a v1 digest as a chunk digest or drop tags from authentication.

## Migration/recovery gates

Synthetic rehearsal first; production remains on its existing repository. Later,
with separate approval: stop writer, retain encrypted source+outbox+key backup,
create a staging generation, export through existing v7, build chunks, reassemble
and compare byte/value equality, validate IDs/tombstones/source evidence/all root
sections and pending intents; then an explicit atomic generation promotion.
Never migrate in place, provision an empty profile on failure, delete WAL/SHM,
or roll back to a generation that would hide newer accepted/pending commands.
Corrupt state stays quarantined. Chunk compaction/retention are separate decisions.
