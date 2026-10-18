# Gate B — passed, 2026-10-16

New native receipt tests and seven AOT process-exit cases pass. Prior container,
WAL, chunk/native-fault and shared-core tests pass (machine-readable logs under
`results/regression-*.jsonl`). Process exit evidence is not power-loss evidence.

The experimental SQLite format 1/2 schema is unchanged. The immutable command
intent contains a reserved local effects envelope; commands, revision/journal,
encrypted state and outbox still share the existing single native transaction.
Only after COMMIT does the container issue an unconstructible final receipt with
a private per-open authority. Verification checks persisted immutable bytes,
snapshot/chunk digest, journal, delivery, generation, checkpoint and all bindings.
Closing/reopening invalidates old receipt authority. Same-ID resolve/retry does
not create a duplicate outbox. A corrupt warm chunk cannot be verified.

Unknown outcome poisons the container and requires a safe reopen. Legacy APIs
remain intact; receipt is local durability proof, not server acceptance. New
schemas, bank adapters, production persistence and financial rules unchanged.
