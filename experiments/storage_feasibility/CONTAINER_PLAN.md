# 2b.0 isolated contract plan — 2026-10-11

No app/package dependency, repository, controller, financial rule, real profile,
network, SDK or installed binary will change. Reuse pinned 2a.1 native engine,
DPAPI primitive, checkpoint policy and fault shim inside this experiment.

1. Opaque codec-v7 snapshot boundary; storage knows bytes/digests/revisions, not
   financial calculations. Model changes remain in existing codec/Synoball.
2. Separate immutable durability journal from immutable outgoing commands.
   Bootstrap and remote commits have journal entries but no outgoing command.
3. Partition-bound commands, CAS revisions, delivery state machine and durable
   synthetic receipts. Never discard command payloads in this experiment.
4. Remote page atomic shadow/checkpoint/aliases/conflicts. Without a proven
   financial rebase adapter, retain local projection when pending work exists
   and expose a conflict; never silently choose last-write-wins.
5. Explicit synthetic migration manifest, lossless bytes, restart/idempotency;
   two-generation DPAPI manifest, verified backup, explicit recovery only.
6. Serialized writer isolate, bounded queue, error/exit supervision, process
   lock, reader leases, drain shutdown and mutually exclusive maintenance.
7. Contract, crash, native fault, key, reader/WAL, codec, regression and 1k/10k/50k
   benchmark evidence, then report and stop. Android explicitly deferred.

Integration blockers already identified: BudgetController mutates memory before
onChanged; LocalQestoRepository serializes snapshots but has no mutation intent,
CAS revision or command identity. A future unit-of-work boundary must stage the
existing models before publication. Merely replacing saveUserFinancialData is
not sufficient and is not attempted here.
