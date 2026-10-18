# Stage 4g — performance plan

2026-10-17. Windows x64, synthetic codec-v7 only. Protocol v0.1 applies.
No production profile, vault, installed app, Android or public service access.
This directory owns all new evidence; Stage 4c–4f evidence is immutable.

## Scope and baseline

The workspace is already dirty from earlier stages. Capture SHA-256 source,
test/golden and historical result manifests plus git status before changing
existing files. Review only the delta against this manifest for Stage 4g.
Reuse the actual core, codec, SQLite3MultipleCiphers, full protocol-v1 server,
coordinator, and two rendered BudgetControllers. No financial reimplementation.

Run a fresh sequential 1k/10k full/effects control using the existing Stage 4f
workload (three edits, sender push/pull, receiver pull, full-state oracle).
Use separate Flutter test processes, the same AOT server and no concurrent
test/build load. Keep debug/JIT measurements explicitly separate from an SLA.
GC/allocation probing runs separately, outside latency benchmark intervals.

## Hypotheses (not findings)

1. Full JSON and decoded objects coexist in owner, storage caches, shadow,
   coordinator, controller, and retained SendPort responses. Entry-count caches
   have an unbounded byte footprint as profile size grows.
2. Unconditional driver invalidation/readmission on sync duplicates codec,
   policy and projection work, even for an empty/repeated pull.
3. Authoritative replay and pending rebase dominate genuine remote changes;
   protocol-v1 full digests remain mandatory, regardless of local journals.
4. Repeated admission during worker startup, not native open alone, causes the
   50k readiness failure. The existing 30-second deadline is not negotiable.

## Sequential gates

### A — measurement before cache changes

Capture process/build/phase, CPU, RSS/peak, VM allocation classes and live bytes
after controlled GC, isolate-group IDs and bounded retaining paths. Never sum
shared isolate-group heap values. Map committed/prepared state, JSON, canonical
indexes, shadow/pending/projections, read/executor caches and UI/port envelopes.
STOP cache changes until measurements and source ownership explain retention.

### B — bounded lifetime

Only measured redundant retention may be removed. One writer/profile, one
candidate and bounded queue remain. Cache budgets use bytes and correct
workspace/revision/policy/storage-generation invalidation; corruption fails
closed. Keep authoritative shadow/pending/recovery metadata. Exercise 50–100
note/sync cycles and compare post-GC retention, not just allocation totals.

### C — admission reuse

Separate empty, repeated, receipts-only, genuine remote, pending/conflict,
policy/version changes and restart. Reuse requires verified partition/device,
generation, cursor/revisions, policy/domain version, pending identity,
receipt/coverage consistency and no unapplied effects. Cursor equality alone
is never sufficient. Unknown dependencies retain the full path.

### D — verified remote replay

Measure receipt/bundle verification, shadow reconstruction, domain replay,
journal capture, projections, codec/digest, encrypted commit, admission and UI.
Any journal comes from LOCAL verified replay and must match the complete full
oracle. Keep full v1 authoritative digests and atomic shadow/projection,
revisions, coverage, conflicts, aliases and checkpoint; no incoming outbox.
STOP incremental remote/UI changes if this proof is unavailable. Document
the blocker instead of bypassing validation or trusting network patches.

### E — startup

Separate native open/key, manifest/chunks/reconstruction, decode/indexes,
configured policy, legacy/Sber projections, owner, controller and port costs.
Measure 50k peak and retained state. No timeout increase, partial readiness,
second writer, schema migration or large controller rewrite. If a small safe
change cannot satisfy readiness, write a focused RFC.

## Acceptance and regressions

10k local <=3s, receiver <=6s, peak RSS <=110% fresh full control, sender no
slower than fresh full control; explain any main-isolate regression. 50k
owner readiness <=30s. Report CPU/RAM/heap, logical serialization/SQL bytes,
DB/WAL growth, HTTP/server timings, controller/publication and handoff.

Preserve full codec/core/audit/locks/tags/categories/source identities/exact
money/currencies/tombstones/unrelated roots equality and existing goldens.
Repeat relevant Stage 4f regressions and cover the 20 scenarios in the user
spec (including crashes, unknown commit, lost ACK, warmed-cache corruption,
keys/rotation, queued shutdown, audit-only and stale-policy 21/60 fixture).

## Completion

Produce Owner_Lifetime_Remote_Replay_Performance_Report.md, raw machine-readable
evidence, exact changed-file list, unmet budgets and smallest next step.
GO is only for a subsequent experiment, never production authorization.
Stop after the report; no automatic next stage, deployment or migration.
