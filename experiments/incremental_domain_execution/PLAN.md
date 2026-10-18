# Stage 4d — gated synthetic work, 14 October 2026

Only Windows x64 synthetic fixtures. Preserve 4c evidence and source hashes first.
No production profile, installation, migration, protocol-v2 or bank/Android work.

## O(N) audit and decision BEFORE implementation

| Work | Required contract / possible reduction |
|---|---|
| Decode/schema/identity on open | Required once per verified durable generation; any mismatch must invalidate owner |
| Core indexes + configured policy on construction | Reuse only a prepared core with unchanged policy and exact source binding; changed policy/observation forces full path |
| Recurring derivation in updateTransaction | Preserve: edits can alter merchant/semantics; cannot just patch note |
| Canonical changes | Capture ALL core collections, not target-only; compare full oracle including stale-policy multi-effects |
| Read-model/Sber projections | Existing functions stay authoritative; partial projection not enabled without complete effect contract |
| Full JSON and digests | Required by v1 storage/wire interfaces; streaming hash may reduce allocation but must preserve exact bytes |
| Shadow/pending replay | Required for conflicts; no blind SQL update/JSON Patch |
| UI full envelope | Current controller requires data + mutable preparedCore; typed delta requires a separately verified publication seam |
| Backup/export | Full reconstruction remains mandatory; cannot postpone v1 commit validation to export |

1. Establish versioned effect contract, exhaustive oracle and startup/policy gates.
2. Try minimal additive core prepared-fork API (unchanged default behavior), with
   per-command clock/IDs and discarded speculative fork on failure. No live-core
   mutation before commit. Reuse must bind exact owner/input/policy, never target ID alone.
3. Measure bounded retention and allocations separately from timed benchmarks.
4. Reuse existing encrypted container, coordinator, backend and real UI harness.
   Default paths and existing expectations remain unchanged.
5. Retain full fallback where contracts still require full state. If partial UI,
   storage or server updates need broad refactoring, document RFC and stop there.
6. Regression/fault/parity and matched measurements; report GO/NO-GO honestly.

Provisional budgets are the owner's: local <=3s, receiver <=6s, RSS <=110% of
matched full-snapshot path, unchanged 50k startup deadline. Never relax safety.
