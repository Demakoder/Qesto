# Windows Integration Boundary — Stage 4a

An optional **real BudgetController note seam**, enabled only by constructing a
synthetic controller with `noteBoundary`. The normal app shell/default repository
are unchanged. This runner never launches or installs Qesto or reads its profiles.

`WindowsNoteBoundary` owns one marked synthetic encrypted Container in a supervised
isolate. Decode, configured Synoball, existing Qesto bridge, existing Sber projection,
codec-v7 serialization and SQL commit run there. Only a durable result is published
by the controller. The base app has no storage-experiment dependency or setting.

From this directory on this Windows workstation:

```powershell
./tool/run.ps1
```

Prerequisites: previous storage fixture/probe and sqlite3mc build environment,
existing Flutter SDK, and available disk headroom. Dart/Flutter paths are explicit
in the script. No PostgreSQL is started; backend code is used for wire contracts
and a **documented semantics compatibility gate**, not for network requests.

Native CLI tests use a generated `.dart_tool/package_config.json` mapping to the
actual pure app files. `tool/configure_app_seam.dart` recreates it after `pub get`;
no production pubspec or copied implementation is needed. The separate Flutter
runner declares a normal app path dependency and native sqlite3mc hook. Its lock
file pins that test environment independently of the app. Both SDK/platform test
environments are exercised, not assumed identical.

The synthetic factory creates a fresh `qesto-storage-spike-*` directory and two
markers, with `synthetic-4a-*` workspace/device/epoch and synthetic user. No path
discovery, user-vault access, bank profile, real `store.json`, migration, reset,
automatic fallback or public listener is implemented.

The controller and adapter support staged **notes only**. Injection rejects a
legacy save callback. Calling an old financial mutation in this synthetic mode
fails at its save boundary and requires recreation/reload; those existing methods
still mutate memory before save and are not usable mixed with the new path.
Normal production behavior for those methods is preserved.

One outstanding command per target; 16 queued RPCs maximum; FIFO and CAS reject
stale intents. Cancellation can prevent commit at the precommit boundary. After
commit it requires explicit reload, not rollback. Graceful close drains requests
or cancels pending work. Worker death is unknown durability and **full process
restart is required**: do not reopen after `Isolate.kill` in the same process.
Synthetic fault hooks are never production recovery.

No delivery coordinator runs in 4a. Fresh entity `base_revision=0` is only a
synthetic bootstrap assumption. `server-semantics-gate.json` records why the
current 3a server note adapter cannot yet be connected directly: actual Qesto
bridge/policy and owner/entity semantics must first be aligned and tested.

Results include JSONL tests, full-result parity, native crashes/keys/ownership,
actual Flutter widget publication, 1k/10k timings and primary-isolate timer gaps.
Timers are not production raster-frame p95. Source checks allow only four app
seam files; the original baseline is retained and never silently overwritten.

Report: `docs/sync/2026-10-12/Windows_Integration_Boundary_Report.md` at repo root.
