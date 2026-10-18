# Stage 2a.1 — isolated storage hardening (2026-10-10)

Scope: candidate B, synthetic data only. No production imports, data migration,
installation, network sync, emulator or phone. Stop at report, not stage 2b.

Already passed in 2a: atomic snapshot/outbox/revision, semantic parity, retry,
key validation, keyed backup, DB-only rekey, reader isolation, two-writer race,
release builds, boundary process crashes. Rerun contracts only after shared
prototype changes; do not repeat the entire old benchmark matrix.

Partially proven: checkpoint crash (timer only), vault lifecycle (DPAPI primitive
only), WAL growth (unbounded measurement), Android (build, not runtime).

New evidence: native file-method error/partial-write/crash interception; FULL
quota; checkpoint status and backpressure; pinned readers; two-generation
DPAPI recovery; writer isolate serialization; CPU/RAM/serialization benchmarks.

Physical power loss, actual full disk and failing hardware are NOT simulated
into claims of proof. Android explicitly deferred by user.
