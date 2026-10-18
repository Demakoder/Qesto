# Stage 4f — bounded integration plan (2026-10-16)

Synthetic Windows only. No profile/vault reads, migrations, Android, installation,
remote deployment, bank changes or production wiring. Preserve the existing dirty
tree. Stage 4b/4c full execution and all existing goldens remain the oracle.

1. A: immutable note candidate and typed app effects; reuse the actual bridge,
   read-model and Sber projection. Capture admission-only corrections separately
   from changed canonical records. Prove full codec-v7 equality including stale
   policy (21/60), stale legacy rows, audit-only, money, locks and unrelated roots.
2. B: experimental encrypted container receipt issued after SQLite COMMIT; bind
   exact effects, snapshot, command, revision, owner and storage generations.
   Retry/collision, corrupt state and crash tests before any owner/UI wiring.
3. C: one owner; verified receipt promotion only, invalidate on remote/restart/
   policy/unknown result, no second writer after native worker death.
4. D: opt-in synthetic BudgetController publication; no full profile over port,
   no speculative or duplicate success, all neighbours and audit-only included.
5. E: existing loopback sync financial validation, two UI clients, matched
   benchmarks and unchanged 50k startup deadline. Full remote path is allowed.

STOP at any unproved gate. A demonstrated need for broad refactoring requires an
RFC, not an unsafe workaround. Metrics from standalone JIT are not UI/AOT metrics.

Reusable APIs: CoreJournalPreparation, applyQestoTransactionEdit,
QestoReadModelService.build, projectSberTransactions, UserFinancialDataCodec,
SqliteContainer.commitMutation / immutable intent, WAL policy, Coordinator,
WindowsNoteBoundary FIFO and synthetic Flutter hosts. No second financial executor.

Important dependencies: app projections depend on canonical record, receipt,
known account IDs and configured category policy; legacy Sber transfer projection
also consumes note text. Admission must account for stale persisted app projection.
