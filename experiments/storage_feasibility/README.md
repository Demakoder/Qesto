# Qesto Storage Feasibility Spike — isolated 2a

Synthetic data only. This package is not imported by Qesto and is not a migration.
Do not use a real profile, financial export or production database as input.
No server, synchronization transport, cloud account or production install exists.

## Candidates

| CLI name | Candidate | Root hook |
| --- | --- | --- |
| `driftMc` | A: Drift NativeDatabase + SQLite3MultipleCiphers | `source: sqlite3mc` |
| `directMc` | B: direct sqlite3 + SQLite3MultipleCiphers | `source: sqlite3mc` |
| `payloadGcm` | C: ordinary SQLite + AES-GCM BLOBs | `plain_runner`: `source: sqlite3` |

A/B use the SQLCipher cipher mode **inside MC**, not a separately tested Zetetic
SQLCipher library. C leaves SQL schema/revisions/command IDs/metadata kind names
clear. Its binary envelope differs from production JSON; it reuses the AES-GCM
primitive/library, not the production persistence implementation.

## Reproduce on Windows

Use Dart 3.12.2 / Flutter 3.44.6 and committed lockfiles. From this directory:

```powershell
$spikeDart = 'C:\Users\ARM\development\flutter\bin\cache\dart-sdk\bin\dart.exe'
& $spikeDart pub get
& $spikeDart analyze
& $spikeDart test
& $spikeDart build cli -t bin/probe.dart
& '.\build\cli\windows_x64\bundle\bin\probe.exe'
& '.\build\cli\windows_x64\bundle\bin\probe.exe' bench directMc 1000 WAL
```

Keep the complete bundle, including `lib`. Build hooks require `dart build cli`,
not `dart compile exe`. Do not upgrade production dependencies.

Repeat A/B benchmarks for 1000, 10000, 50000 in WAL, plus 50000 in DELETE mode.
Each invocation runs three trials. From `plain_runner`, use the same commands
for C (`bench payloadGcm ...`). Both runners share schema, contract and harness.
Keys are random, not logged, sent to crash workers through stdin. Successful
runs delete their marked synthetic directories. Interrupted parents can leave
synthetic directories: remove only an exact verified owned directory, never a
profile or a broad temp glob.

## Android

`android_probe` is a separate synthetic-only Flutter app for A/B, not C. See its
README. Built but not installed/executed on a device. Packaging does not prove
Keystore, encrypted runtime, crash recovery or Android performance.

## Evidence

- `results/windows_release_mc.json`: A/B actual release/native/crash observations.
- `results/windows_release_payload.json`: corresponding C observations.
- `results/windows_benchmarks.json`: all 36 trial samples.
- `results/build_inventory.json`: packaged native/APK identity and hashes.
- `results/validation_summary.json`: tests and explicit limits.
- `results/production_source_final_validation.json`: hashes bracketing final
  validation; not a baseline for earlier uncommitted app changes.
- `../../docs/sync/2026-10-10/Storage_Feasibility_Report.md`: decision and gates.

## Limits of the original 2a harness

Release gates throw ordinary errors, never assertions. Wrong/missing key or
existing empty/corrupt DB fails closed. Lost ACK retries use durable command and
revision; different contents with the same command ID are rejected. This is
storage-command identity, not another financial deduplicator.

Dart-boundary faults and backup page-copy interruption are exact. Timed kills
around native commit/checkpoint do not establish the native I/O phase or power
loss. DB-only rekey passed Windows; atomic DB+vault rotation and portable recovery
are not implemented. Outbox ACK/pruning protocol is absent. Do not deploy this
experimental schema. Production needs separate approval and gates.

## Stage 2a.1 — storage hardening

See [Storage Hardening Report](../../docs/sync/2026-10-10/Storage_Hardening_Report.md)
and [scope/check matrix](HARDENING_PLAN.md). Windows synthetic-only fault/key/owner
checks are reproduced with `./tool/run_hardening.ps1 -IncludeBenchmarks`.
Use AOT harnesses for subprocess tests: nested `dart run` may try to replace an
already-loaded native asset DLL on Windows. No phone/emulator or installed app
is used. Results: `results/hardening_summary.json` and underlying JSON/JSONL logs.
Not a production vault, migration, installer or stage 2b implementation.
