# Gate A — measured ownership, before cache changes

Fresh matched control is preserved in `results/baseline/`: full 10k median
local 5.391s, sender 14.937s, receiver 11.241s; peak 796.7 MiB. Effects median
local 2.785s, sender 16.550s, receiver 11.067s; peak 1029.3 MiB. Three trials,
same synthetic fixture/workload and AOT full server, two rendered controllers.
All four benchmark processes passed complete codec-v7/server parity.

## Explanation supported by GC + retaining paths

The FIRST ready observation in `retention-before-v2` precedes any instance
sampling and therefore cannot be contaminated by earlier service object IDs:

| Live heap after GC, 10k | Full | Effects |
|---|---:|---:|
| Whole isolate group bytes | 169,010,640 | 339,984,432 |
| Two-byte string bytes | 42,937,600 | 163,702,304 |
| CanonicalTransaction instances | 20,000 | 40,000 |
| BudgetTransaction instances | 29,997 | 49,995 |
| NotePreparationScope / UserFinancialData | 0 / 0 | 2 / 2 |

The additional ~163 MiB LIVE heap is not solely allocator slack: ~115 MiB
additional string payload plus two admitted canonical/legacy models accounts
for most of the difference. Peak RSS also includes transient JSON parsing,
policy/projection reconstruction, GC headroom, VM/native/SQLite memory.
Do not add class bytes or retained subtree sizes to whole-heap usage.

Final retaining paths identify `_RawReceivePort` → worker callback →
`SqliteContainer` → `_financialCache` / `_readCache`, and worker → `_Driver` →
`DurableEffectsOwner._scope` → detached codec model. Sample container retained
sizes are 91,630,816 and 91,632,992 bytes; sample scope 23,868,128 bytes. A stale
FinancialSnapshot alone retains 30,190,544 bytes. Each container has two verified
read scopes and two entry-count-only financial snapshots. These measurements
support bounding/releasing stale JSON, not discarding authoritative shadow.

UI cores are retained by the two BudgetControllers and widgets. Full-path
benchmark wrapper additionally retains its most recent CommittedTransactionNote;
sync results remain local until trial completion. No PreparedFinancialCommit or
EffectsCommitRequest survives a successful local commit in sampled allocation.

## Instrumentation defects discovered (not application leaks)

1. `getRetainedSize` is NOT a public RPC in this VM. The first 1k probe failed.
   `_getRetainedSize` is documented by the installed vm_service private RPC test.
2. Intermediate getInstances/getObject can root old objects in the VM service
   ring. Later counts in `retention-before-v2` are NOT evidence of an application
   leak. Clean probes sample instances only at the final point; earlier points
   use GC + allocation counts without allocating model object IDs.
3. Initial phase wrappers used closures inside the long-lived worker. Dart
   closure contexts retained bootstrap locals and inflated ready heap (~492 MiB).
   The diagnostic wrapper was replaced with explicit stopwatch records, without
   capturing startup models. `retention-clean-v2` records that rejected probe.

Raw evidence includes process, runtime, group ID, phase, GC timestamp, classes,
paths and fields. One profile per isolate group, never sums per-isolate heaps.

## Gate decision

GO for a bounded, opt-in storage cache policy and exact current-generation
lifetime checks. The useful admitted domain owner remains; no speculative
state, authoritative shadow, pending or recovery state is removed. Need repeat
clean post-change probes and 50–100 cycles before declaring retention bounded.
Admission reuse and remote optimization require their own independent gates.
