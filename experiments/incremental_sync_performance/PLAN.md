# Stage 4c — bounded synthetic experiment

Scope: Windows x64, synthetic fixtures only. No production repository, user vault,
installed application, bank session, cloud service or financial migration.
The attachment ended midway through section 9. The owner supplied sections 9–13
in the follow-up; fault cases, performance budgets and the stop boundary below
include that continuation.

1. Audit current executor/codec/owner/coordinator/SQLite/PostgreSQL path and retain
   original Stage 4b results plus hashes of source files before any changes.
2. Profile 1k/10k and attempt 50k, distinguishing Flutter debug VM and native AOT.
   Identify decode, policy/core, projections, diff, serialization, I/O, replay,
   isolate transfer, UI publication/build, memory and bytes. State limitations.
3. Compare SQL normalization, versioned chunks and a hybrid. Choose the smallest
   measured safe prototype; keep full financial execution as parity oracle.
4. Integrate optional experimental storage representation with the SAME container
   transaction/outbox/checkpoint/key/backup contracts. No second reconciliation.
5. Check full codec-v7 equality, multi-entity effects, conflicts/pending overlays,
   immutable intents, crashes/restart/recovery and protocol compatibility.
6. Repeat matched-mode benchmarks and applicable prior regression suites. Report
   improvements AND remaining O(N) work. Stop after report; no rollout/next stage.

Existing worktree changes belong to earlier tasks. Git/PR creation not requested.
