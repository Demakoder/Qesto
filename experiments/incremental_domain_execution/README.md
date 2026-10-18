# Incremental domain execution — Stage 4d synthetic experiment

Windows x64, synthetic fixtures only. `PreparedDomainOwner` and `DomainEffectsV1`
are isolated POCs, not production/client integration. `DomainMemoryHarness` runs
the existing real UI/controller/worker/backend stack with bounded decode cache,
unchanged full algorithm, format 2 and v1 wire protocol.

Read `PLAN.md`, `Domain_Effects_Contract_and_Blockers.md` and the Stage 4d report
under `docs/sync/2026-10-15/` before interpreting performance numbers.

Setup (from this directory, existing pinned Flutter/Dart SDK):

```powershell
dart pub get
dart run ../windows_synthetic_ui_sync/tool/native_assets_seed.dart
dart tool/configure_app_seam.dart
dart build cli -t bin/server.dart -o build/server
dart tool/configure_app_seam.dart
# From flutter_runner: flutter pub get
./tool/run_checks.ps1 -Benchmarks -Regressions
```

The runner uses existing isolated PostgreSQL cluster config; no cloud or real
profile discovery. It stops that cluster in finally. The existing 4c native crash
probe is reused (it exercises the unchanged worker/storage path). Compilation and
native assets for prior experiment binaries are prerequisites from Stage 4c.

Domain decomposition (separate process for each pair, three measured trials after
one warmup, includes full parity/effects outside timed execution):

```powershell
dart bin/profile_domain.dart baseline 10000
dart bin/profile_domain.dart prepared 10000
dart --enable-vm-service=0 bin/profile_domain.dart baseline 10000 --allocation
dart --enable-vm-service=0 bin/profile_domain.dart prepared 10000 --allocation
```

Allocation runs are separate and force GC only before the first command. The VM
service binds loopback and exits with the probe; no authentication/data is exposed
to a remote endpoint. Output is synthetic machine-readable JSON in `results/`.

Full UI results are not interchangeable with standalone domain timings. Preserve
the copied 4c baseline evidence; the benchmark wrapper reuses exactly the prior
workload. `QESTO_4C_COUNTS=50000` does not extend the existing 30s startup deadline.
