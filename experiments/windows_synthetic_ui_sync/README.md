# Stage 4b — synthetic Windows UI sync

This is an explicit test integration, not a public Qesto feature. Two independent
real `BudgetController` / Qesto widget hosts own separate encrypted SQLite stores,
talking to the existing loopback-only PostgreSQL backend through the existing
Coordinator. Only `transaction.set_note` is supported. No production store,
bank sessions, actual financial documents or installed applications are used.

## Run (Windows)

Prerequisite: the **owned synthetic** Stage 3a PostgreSQL cluster already exists.
The script resumes/stops that cluster; it never provisions a production service.
From this directory:

```powershell
powershell -NoProfile -File tool/run.ps1 -IncludeRegressions
```

Adjust the SDK executable paths in `tool/run.ps1` for a different development
machine. The read-only `qesto` package mapping points to actual pure app code;
there are no copied financial implementations or production pubspec changes.
`pub get` can regenerate this mapping; re-run `tool/configure_app_seam.dart`.
Native tests use the direct `test` entry after build hooks to preserve it.
The runner first materializes the JIT native-assets manifest via a marked,
encrypted synthetic seed, so it does not depend on stale local hook caches.

STOP gate is checked both by the script and the harness before UI networking:
complete application/server codec+Synoball parity, controlled clock/IDs, all tags,
configured rules/locks, audit/events and `user` / `ent-user` binding.
Do not substitute the old Stage 3a narrow note executor for the Qesto executor.

`build/` and `.runtime/` are ignored, including synthetic credentials. Results are
machine-readable JSON/JSONL; `tool/collect_results.dart` fails on an incomplete
suite, changed golden/model/repository files, missing benchmarks or unsafe
controller mutation ordering. Core goldens remain unchanged.

Full v7 snapshots and exact incoming executor replay are intentionally retained.
The measured 10k latency is **not production-ready**; the report separates SQL,
CPU/codec, network/backend, remote apply, UI publication and isolate timer gaps.
No next stage, normalization, Android integration or real-profile migration is
included.
