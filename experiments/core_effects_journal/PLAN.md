# Stage 4e — bounded plan (2026-10-15)

Synthetic Windows only. No live profiles, coordinator/storage/UI wiring, network,
Android, migrations or changes to financial rules. Preserve the dirty worktree.

1. Audit the 15 core collections, constructor policy normalization, command writes,
   recurring rebuild, bridge and projections; preserve source baseline hashes.
2. Add opt-in core-owned recording at collection write boundaries. The default
   constructor/fork keep their behavior. Journal includes initialization changes
   relative to persisted input, not just command target/audit. Immutable result.
3. Freeze nested model collections on initial experimental ownership admission,
   and on subsequent writes. Reuse immutable records between prepared forks;
   never deep-clone a whole profile on every command. Measure admission separately.
4. Compare full state and app codec with the independent 4d oracle. Exercise
   note/no-op/clear, 21-of-60 policy case, override/locks, recurring, imports/trash,
   errors, stale/restart ownership and deliberate missing-record negative tests.
5. Benchmark capture vs full diff at 1k/10k/50k, with oracle outside timed work;
   separate domain cost, record/finalize cost, allocation and admission.
6. Run shared/app regressions and analyzers, write mutation map, typed durable
   publication proposal and Core_Owned_Effects_Journal_Report.md. Stop.

Coverage is core collections only. App bridge/root/projection effects are NOT
claimed by this journal. Unsupported paths must fail or report incomplete.
