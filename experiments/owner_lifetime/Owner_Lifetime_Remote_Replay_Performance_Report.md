# Stage 4g — Owner Lifetime, Remote Replay & Startup Performance

19 October 2026. Windows x64; only synthetic codec-v7 profiles. This report
uses a fresh three-run matched control, not the older Stage 4f numbers as proof.
The experimental code is opt-in (`EffectsDriverFactory(boundedLifetime: true)`);
the normal Qesto repository, user profile, SQLite default, bank adapters,
server protocol and installed apps were not changed.

## Decision

**NO-GO for production integration and for the next performance stage.** The
local 10k edit meets its 3 s gate, and 50 two-client cycles preserve full
financial parity. The 10k receiver, sender, peak RSS and 50k readiness gates
fail. Full incoming replay, atomic storage and full UI reload remain in use.
Neither a network-supplied patch nor a faster but incomplete validation path
was introduced.

## Fresh matched measurements

Three consecutive edits per run; two rendered controllers; same encrypted
SQLite3MultipleCiphers container and same AOT full-protocol server. Values are
median wall milliseconds except peak RSS. This is a Flutter debug VM benchmark,
not a release SLA. Each trial asserts full codec-v7 client A = client B = server.

| Profile / path | Local edit | Sender push+pull | Receiver apply | Peak RSS |
|---|---:|---:|---:|---:|
| 1k full control | 460 ms | 1,413 ms | 1,015 ms | 328.1 MB |
| 1k Stage 4f effects | 283 ms | 1,730 ms | 977 ms | 361.1 MB |
| 1k bounded owner | 302 ms | 1,873 ms | 1,085 ms | 353.9 MB |
| 10k full control | 5,391 ms | 14,937 ms | 11,241 ms | 835.4 MB |
| 10k Stage 4f effects | 2,785 ms | 16,550 ms | 11,067 ms | 1,079.3 MB |
| 10k bounded owner | **2,739 ms** | **19,512 ms** | **12,069 ms** | **1,101.5 MB** |

The RSS budget is 919 MB (110% of the fresh 10k full control). The new path
exceeds it by 182 MB. Its receiver exceeds the 6 s target by 6.07 s, and
sender is 4.58 s slower than the full control. The maximum measured receiver
main-isolate heartbeat gap was 54.6 ms, versus 62.8 ms in full and 60.7 ms
in effects control; this is only a sampled timer metric, not frame latency.
For sample 2 at 10k, host CPU rose from 32.2 to 38.5 seconds. DB and WAL
sizes were unchanged (A DB 60,518,400 B, WAL 1,429,672 B; B DB 60,502,016 B,
WAL 1,969,392 B), as were HTTP bytes on this trial (sender 686 B sent,
6,437 B received). The proposed guard adds validation without changing wire
traffic or the full remote computation.

Machine-readable [summary](results/summary.json), [raw controls](results/baseline),
[1k result](results/bounded-matched) and [10k result](results/bounded-matched-10k).

## Retained objects and cache lifetime

VM `getAllocationProfile(gc:true)` measured one isolate-group heap after
confirmed GC. It was **not** added across the main and worker isolates.
The clean 10k ready control measured 169.0 MB live heap (full) and 340.1 MB
(effects), with two-byte strings at about 42.9 vs 163.7 MB, canonical
transactions at 20k vs 40k and BudgetTransactions at about 30k vs 50k.
Retaining paths link `SqliteContainer` through the long-lived worker to read
cache/financial snapshots; a `NotePreparationScope` holds the admitted
profile/core. Sample retained sizes are overlapping subgraphs: two containers
about 91.6 MB each, scope about 23.9 MB; they must not be summed.
Prepared candidates and commit requests count zero after completion.

The opt-in container cache now has a 64 MiB UTF-16 payload budget, drops
superseded JSON generations and clears on key rotation/recovery/close. This is
an estimate of retained cache strings, **not** a cap on native RSS, canonical
models or temporary buffers. Five original cache tests plus new lifetime tests
exercise warmed corruption, 50 local commits, generation rotation and byte
limits. A separate **50-cycle two-client** test alternates note changes,
sender/receiver sync, repeated page and empty pull. It compares full v7
client states with the server after every cycle; all 50 passed. The last
cache payload was 598,442 B per client with zero staged entries and no pending
commands. Post-GC heap was 105.1 MB at cycle 0, then 110.1 / 111.2 / 112.2
MB after cycles 10 / 25 / 50 for this 60-operation fixture. That small growth
does not prove a zero-leak bound for 10k or 50k; JIT/code allocation is included.

The first profiling attempts were rejected as evidence: sampling VM object
IDs at each point created service roots, and a tracing closure retained a
bootstrap document. The corrected run samples retaining paths only at the
final point and uses non-capturing worker timing. Rejected attempts remain
under `results/retention-before*` and `results/retention-clean-v2` rather
than being silently replaced. Corrected raw data is under
`results/retention-fixed` and `results/bounded-cycles`.

## Admission after pull

The worker now supports an optional lifetime interface. Before a remote
operation, the owner suspends local preparation; only one committed scope is
retained and no prepared candidate is allowed. After the operation, reuse
requires an exact digest of the **verified** partition, device, user, owner
and storage generations, policy/profile, complete sync context (including
cursor, revisions and page coverage), snapshot revision/hash, shadow hash,
and all durable journal/command/delivery/receipt/checkpoint/alias/conflict/
bundle/migration rows. Storage integrity is verified on both sides. The owner
also checks its admitted hash, revision and generation before returning to
ready. A mismatch causes the existing full verification/admission path;
an unknown or corrupt result invalidates the owner. Cursor equality alone
does not grant reuse. The default flag uses Stage 4f full readmission.

The 50-cycle fixture observed 50 safe reuses and 50 full readmissions per
client (empty/repeated versus genuine changes). Tests cover same-checkpoint
changes to cursor, revisions, pages, delivery attempts, pending commands and
receipt-only updates; foreign identity/policy, warmed chunk corruption and
key generation changes fail closed or readmit. Receipt-only state intentionally
uses the full path until a more precise proof exists.

## Genuine remote change and UI publication

Instrumented 10k control across six remote changes: verified domain replay
averaged 3.95 s per change, owner readmission 2.35 s, executor policy/
projection preparation about 1.07 s, encrypted storage verify about 1.55 s
per invocation. These spans overlap or nest; do not add them as independent
critical-path times. One receiver trial measured network 0.55 s, remote
prepare 4.42 s, remote commit 2.21 s, then admission about 2.28 s plus UI
publication. The application executor repeatedly decodes the same full
profile during replay and pending projection. The protocol-v1 authoritative
before/after digests, receipt/coverage proof and full-state equality remain.

Reusing a locally computed core-owned effects journal for incoming updates
would need a versioned proof that also covers pending rebase, every codec-v7
root, audit/events, legacy projections, exact money, locks, tags, categories,
source identities and tombstones, then a single atomic shadow/projection/
receipt/checkpoint commit. The existing local note journal does not provide
that remote contract. No incremental remote commit or remote typed UI delta
was implemented. Local typed publication still occurs only after durable
commit; remote UI continues to load the complete committed state.

## 50k startup

The unchanged 30 s readiness deadline **failed**. The synthetic run spent
7.85 s building/seeding fixture and server, then 36.08 s in snapshot fetch
plus worker open; whole attempt 44.06 s, peak RSS 1,729.5 MB. The 30 s owner
wait timed out before effects admission. Trace includes 1.84 s bootstrap
decode, 2.41 s bootstrap encode/validation, two state reconstructions of
3.52 and 3.38 s, and 7.49 s storage verification. These are observed spans
inside the failed attempt, not a full decomposition. Native reopen, owner
projection admission and controller publication were never reached, so no
number is claimed for those stages. The opt-in cache/lifetime flag is enabled
only when the effects driver opens, after the observed failing bootstrap; it
cannot remove this first-open timeout. The run did not show a partially ready
financial profile. A warm reopen was not established as a passing substitute
for the failed cold bootstrap.

## Safety, regressions and limitations

Core financial rules, exact minor units, IDs, encrypted storage, protocol-v1
wire and full server validation remain unchanged. Source baseline captured
1,029 hashes before edits; comparison found changes only in eight existing
experiment source files and the new trace file outside this package. App and
shared Synoball files did not change in Stage 4g. This experiment did not
touch real profiles.

| Regression suite | Passed | Failed |
|---|---:|---:|
| Stage 4f effects + native crash/recovery | 45 | 0 |
| Encrypted storage + key/vault | 120 | 0 |
| Chunk/fault storage | 21 | 0 |
| Shared Synoball core | 37 | 0 |
| Core effects journal | 8 | 0 |
| Domain/executor | 9 | 0 |
| Windows boundary | 17 | 0 |
| Two-client protocol scenarios (bounded owner) | 15 | 0 |
| Flutter delta/defaults/sync | 14 | 0 |
| New cache/lifetime unit suites | 22 | 0 |

The 50-cycle Flutter suite and all fresh benchmark parity assertions also
passed. Eight targeted analyzer invocations returned zero issues (Stage 4g,
effects, storage, boundary, coordinator, executor, shared core and app seams).
Machine-readable results are in `results/regressions/`,
`results/tests-final-v2/` and `results/analyzer/`. Earlier failed harness
attempts and a corrected test expectation are retained in separate result
folders; they are not counted as application regressions.

Known limitations: cache accounting excludes models/native buffers; a single
60-operation long-run fixture cannot establish a 50k leak bound; the 50k
startup trace ends before owner admission; a genuine remote note still
reconstructs full domain/projection state; and debug VM timing is noisy. No
performance target was relaxed. There was no physical Android test in scope.

### Files changed for Stage 4g

Existing experiment sources:

- `../storage_feasibility/lib/container/sqlite_container.dart`
- `../durable_effects_integration/lib/{prepared_commit,durable_owner,windows_driver}.dart`
- `../encrypted_client_sync/lib/coordinator.dart`
- `../windows_integration_boundary/lib/{synthetic_note_driver,windows_note_boundary}.dart`
- `../windows_synthetic_ui_sync/lib/qesto_note_executor.dart`

New outside this package: `../storage_feasibility/lib/synthetic_trace.dart`.
New source/document files inside this package (generated `build/`, `.dart_tool/`,
`.flutter-plugins-dependencies` and machine-readable `results/` omitted):

- Root: `PERFORMANCE_PLAN.md`, `Gate_A.md`, this report, `pubspec.yaml`, `pubspec.lock`.
- Native probes: `bin/{client_probe,native_effects_probe,receipt_probe}.dart`.
- Flutter runner: `pubspec.yaml`, `pubspec.lock`,
  `test/{benchmark,cycles,retention,startup,regression_defaults,regression_delta,regression_sync}_test.dart`.
- Profiling: `lib/heap_probe.dart`.
- Pure Dart tests: `test/{cache_lifetime,lifetime,integration,regression_boundary,regression_chunks,regression_domain,regression_effects,regression_journal,regression_storage}_test.dart`, `test/evidence_redirect.dart`.
- Tools: `tool/{analyze,benchmarks,build_probes,configure_app_seam,flutter_regressions,regressions,run_tests,source_evidence,summarize}.dart`.

Exact pre-stage comparison is `results/source_verification.json`; historical
Stage 4f evidence was not overwritten. The worktree had many pre-existing
untracked/modified files, which remain untouched outside the listed delta.

## Focused RFC and stop

1. Define a locally produced, versioned **remote effects proof** from the
   existing verified replay. Prove it against the full codec/core oracle,
   pending overlay and all projection/root invariants, including crash and
   unknown-commit cases. Only then consider atomic incremental remote apply
   and a guarded UI delta.
2. Split cold 50k bootstrap profiling into verified server snapshot fetch,
   migration, native encrypted reopen, owner admission and controller. Remove
   repeated work only where full integrity is preserved; rerun against the
   original 30 s readiness deadline. Do not call preloaded or partial state
   ready.
3. Repeat memory comparisons after controlled GC on 10k bounded runs and
   larger long-run fixtures. Current 64 MiB cache setting reduces no measured
   10k peak RSS and adds guard CPU; retain it as opt-in research only.

The next experiment needs a separately reviewed contract. This NO-GO is not
permission for a production repository switch, migration or deployment.
