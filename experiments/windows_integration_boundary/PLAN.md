# Windows boundary 4a

Scope: a disabled-by-default controller note seam, existing configured core and
projection, supervised synthetic Windows writer. No production repository switch.

1. Inventory mutation entry points and capture sources before this slice.
2. Extract the existing edit/projection logic without changing rules; define a
   pure note intent/commit contract and optional BudgetController injection.
3. Synthetic worker owns encrypted Container. Prepare/core/codec/commit run in
   worker; only committed typed results cross to UI. FIFO, CAS, bounded queue,
   cancellation before commit, unknown outcomes and shutdown are explicit.
4. Compare complete results with the actual old controller path/configured policy;
   use deterministic bookkeeping only in tests. Native faults run in child
   processes; Isolate.kill is fail-closed until full process restart.
5. Exercise real Flutter controller publication/error responsiveness, native
   restart/key/ownership cases and 1k/10k benchmarks. Run desktop regressions.
6. Produce report and stop; no app installation or network integration.
