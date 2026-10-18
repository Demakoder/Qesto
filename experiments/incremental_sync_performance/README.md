# Stage 4c — incremental storage/performance experiment

Windows x64, synthetic data only. No production entry point imports this package.
Run from this directory with the existing pinned Flutter/Dart SDK:

```powershell
./tool/run_checks.ps1 -Regressions
# Optional matched 1k/10k Flutter debug measurements (sequential, no other benchmarks):
./tool/run_checks.ps1 -Benchmarks -Regressions
dart tool/collect_results.dart
```

Prerequisites: the owned local PostgreSQL cluster from 3a, native fault shim from
2a.1, and passed semantic/controller gates in the retained 4b results. No credentials
are embedded: runtime synthetic credentials remain in ignored existing `.runtime`.
Pub get/native hooks may need permission to write SDK/Pub cache. Native probe uses
the pinned sqlite3 Dart package 3.5.2 with SQLite3MultipleCiphers and the real
Windows DPAPI/key/backup container.

The bootstrap chooses experimental container format 2 explicitly; format 1 remains
the default and is regression-tested. No existing profile is migrated. `state` and
`shadow` store ordered manifests referencing `json_chunks`, never duplicate full
JSON financial snapshots. Exact v7 JSON is reconstructable, byte for byte. Revisions,
immutable command/outbox, incoming receipts, coverage, aliases and checkpoint use
the same transactional container. Sync context/revision map and server PostgreSQL
TEXT remain whole documents; this is NOT claimed as complete normalization.

Read caches are bounded, reconstructable and only promote after commit. Reads use
connection total_changes, external data_version, database identity and manifest to
invalidate cached bytes, including raw test writes. Reopen verifies all stored
chunks/root hashes. Exact-input executor cache is two entries, scoped by owner and
immutable source string. Full Synoball, tags, policy, projections and authoritative
replay are not skipped. Cache RAM cost and remaining O(N) work are known drawbacks.

`results/baseline-4b-*` are copies of the original evidence, not regenerated baselines.
`profile-baseline.json` is a native JIT decomposition, not a Flutter latency comparison.
`flutter-baseline-*` vs `flutter-incremental-*` use the same real rendered UI hosts,
Flutter debug mode and AOT backend. CPU is GetProcessTimes of host including both
worker isolates, not PostgreSQL/system CPU. Logical JSON/body bytes are not physical
SSD writes; sampled WAL sizes are not a lifetime peak. `isolate-handoff.json` is a
two-way measured envelope copy/scheduling probe, not an exact one-way IPC estimator.

The optional 50k UI attempt failed the unchanged 30-second startup deadline; native
profiling and handoff completed at 50k. This failed gate must not be counted as a pass.
No production readiness claim: see the report and deferred versioned-core proposal.

Final report: `docs/sync/2026-10-14/Incremental_Sync_Performance_Report.md` from the
repository root. The collector distinguishes successful suite executions from the
known failed 50k gate and unmet performance budgets. One retained server counter
(`phases.codec_decode.input_bytes`) is String code units, not UTF-8; see the report
and summary measurement limitations before interpreting it.
