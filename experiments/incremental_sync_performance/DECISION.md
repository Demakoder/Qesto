# Pre-benchmark decision and budgets (13 October 2026)

Baseline retained without overwrite. Native JIT decomposition at 10k: decode
346 ms; core initialize+policy 179 ms; core update 65 ms; legacy projection 19 ms;
Sber presentation policy 185 ms; encode 236 ms; changed entities diff 297 ms;
before/after full hashes 640 ms; encrypted full snapshot commit 1,233 ms.
50k profiling also completed. JIT compiler-host RSS is NOT Flutter RSS.

Options: A (full/partial normalized financial SQL) needs mapping every codec and
core field, ownership and schema evolution; largest migration risk. B (versioned
opaque chunks) is storage-only, byte-lossless and testable against v7. C (hybrid)
is plausible long term, but requires field-specific contracts like A.

Choose B for this isolated slice: deterministic record-boundary JSON chunks,
ordered manifest + hash per chunk + full document hash; rows and manifest are the
ONLY durable state. Same encrypted container and transactions. Chunk identity is
physical ordinal, not a new financial ID. Inserts/reordering can still rewrite
many chunks; this is deliberately a note-only optimization, not full normalization.

Also eliminate repeated exact-input decoding in one executor with a bounded
two-entry, owner-scoped cache. Full Synoball execution and authoritative replay
remain compulsory. No generic SQL patch for notes. Server wire v1 unchanged.

Budgets set BEFORE optimized run: target <=3 s local edit at 10k in matching
Flutter debug mode, receiver <=6 s; aspirational >=2x. At steady state, financial
SQL payload changed <5% of full v7; no >10% peak RSS regression. A first command
can trigger configured-policy effects across many entities; measure it separately.
Failing a budget is reported, not fixed by weakening validation. O(N) core/policy,
whole-core digest, full PostgreSQL state and UI handoff will be measured residuals;
incrementalizing their semantics requires a separately approved core contract.
