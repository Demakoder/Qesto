# Stage 4e — Core-owned effects journal

Isolated synthetic Windows x64 experiment. No real profiles, DB migration,
server/UI coordinator integration, production data, Android or app installation.

## Files and boundaries

- `Mutation_Map.md`: current internal paths and external effects.
- `Journal_Contract.md`: exact experimental API and completeness scope.
- `Durable_Publication_Proposal.md`: future receipt design, NOT implemented.
- `lib/app_probe.dart`: calls actual app bridge and projections, notes only.
- `lib/oracle.dart`: independent full-state verifier, not the capture algorithm.
- `test/`: parity, lifecycle, readonly ownership and negative checks.
- `bin/benchmark.dart`: standalone timing and VM allocation runs.
- `bin/retention_probe.dart`: weak-reference collection after 40 aborts.
- `results/`: machine-readable evidence, including failed exploratory logs.

Shared-core changes live in `packages/qesto_synoball_core/lib/core/`. Production
callers remain on default construction. The only shared test adaptation admits
the standard Dart SDK `dart:collection` import in the offline-pure allowlist.
No extra production package or financial rule is introduced.

## Reproduce (PowerShell, repository root)

Uses the installed SDK and existing dependency cache. Local script SDK paths may
be adjusted on another machine. Initial dependency resolution in this experiment:

```powershell
$taskDart='C:\Users\ARM\development\flutter\bin\cache\dart-sdk\bin\dart.exe'
Push-Location experiments/core_effects_journal
& $taskDart pub get --offline
& $taskDart tool/configure_app_seam.dart
Pop-Location
& .\experiments\core_effects_journal\tool\run_checks.ps1
& .\experiments\core_effects_journal\tool\benchmark.ps1
Push-Location experiments/core_effects_journal
& $taskDart --enable-vm-service=0 --packages=.dart_tool/package_config.json bin/retention_probe.dart
& $taskDart tool/summarize_results.dart
Pop-Location
& .\experiments\core_effects_journal\tool\verify_sources.ps1
```

`configure_app_seam` references real pure app source and prior experiment stubs
for Flutter-only imports. No production pubspec changes. Direct test runner with
the package config preserves this mapping; plain `dart test` can refresh it.
The shared package has its own ordinary standalone `dart test` run, and real
Flutter tests independently check the app. Existing tests/goldens are not replaced.

Run performance separately from tests for less interference. Every timing mode
gets a fresh Dart JIT process, one warmup and three trials; exact oracle work is
outside measured capture. Allocation gets a separate 10k run, pre-workload forced
GC/reset, then samples BEFORE full oracle. VM service is ephemeral local loopback
profiling only; it is not a financial server or remote sync connection.

Flutter may need write access to its SDK cache lockfile. If blocked by a sandbox,
report that failure and repeat with scoped permission, not altered tests. Original
source baseline is retained and must not be overwritten. Verification compares
source/golden files only; it never probes user data.

See `docs/sync/2026-10-16/Core_Owned_Effects_Journal_Report.md` for the decision and
measured results. Stop here; Stage 4f needs separate approval.
