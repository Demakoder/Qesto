# Storage spike 2a — bounded experiment

Intent: evaluate transactional encrypted local storage without changing Qesto.
All experiment databases are synthetic, under an explicitly marked temporary
directory. No production repository, profile, financial logic or migration is used.

1. Baseline production sources and existing persistence/core tests.
2. Pin sqlite3 3.x and Drift; verify actual bundled native library in release.
3. Compare A Drift + SQLite3MultipleCiphers, B direct sqlite3 + same cipher,
   C ordinary SQLite + AES-GCM payload (clear SQL metadata documented).
4. One immutable-command transaction: compare revision, snapshot, outbox,
   revision, checkpoint, shadow, conflicts; acknowledge only after commit.
5. Negative encryption, rollback, concurrent writers, crash/recovery, WAL and
   live backup experiments; report unverified fault points explicitly.
6. Repeated synthetic benchmarks (1k/10k/50k); regressions and source hashes.
7. Separate Android probe, never installed over Qesto. Physical-device runtime
   gate remains blocked when no device is supplied.
8. Report results and stop. No migration, server, sync API or production rollout.
