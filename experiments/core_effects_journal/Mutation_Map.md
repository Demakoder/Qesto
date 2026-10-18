# Current core mutation map — Stage 4e

Read against `packages/qesto_synoball_core/lib/core/synoball_core.dart`.
This is not authorization for all app mutations. Application command coverage in
this POC is `transaction.set_note`; extra calls below are regression probes of
the actual core, not newly implemented Sync commands.

| Path | Persisted effects / existing semantics | Journal boundary |
|---|---|---|
| Constructor / restore from state | configured policy touches every canonical entry including trash; recurring streams and flags rebuilt | All 15 lists wrapped BEFORE constructor policy call; captures changes vs original input |
| `setCategoryPolicy` | categories, redirects, rule/label tags, confidence, cleared subcategory; recurrence | transaction slot writes; final actual policy; policy-change flag forbids reuse without reload |
| `updateTransaction` | enrichment + policy, user fields/locks/tags, timestamp/trust; audit+event; recurrence | transaction write + ordered append + derived replacement |
| `_refreshDerivedData` | all recurring stream output, canonical flags/stream IDs | opt-in replaceContents (equivalent final list); changed slots/length, no clear/re-add noise |
| `ingest` | institution/connection/consent/account upserts; raw payload; records/candidates/receipts/batch; reconciliation; outcome/status counters; event | existing upsert helper and list primitives; no adapter rewrite |
| `_reconcile` create | new enriched canonical transaction, evidence, merged candidate, events | tracked add/update |
| `_reconcile` repeated observation | preserves locks; evidence replacement/append, candidate/record changes; no forced resurrection | same writes, exact evidence values and source IDs |
| Pending candidate / `confirmCandidate` | confirmation may reconcile or revert candidate on conflict; audit/recurrence | same slot, coalesced net value, append effects; exception aborts scope |
| `deleteTransaction` | tombstone is canonical status+trash tags+timestamp; event includes account snapshot; audit; derived rebuild | update (not physical deletion), nested event JSON immutable |
| `restoreTransaction` / `restoreDeletedTransaction` | explicit trash check; canonical replace/append; optional virtual account recreation; audit/events | existing API rules, tracked lists; no new account algorithm |
| `removeUserTag` | all matching canonical tags, audit | slot writes + audit |
| Account/entity upserts / unused removal | existing records and order preserved | setter/add/removeAt; order/expected-before recorded |
| `linkSourceAccount` / `mergeAccountInto` | source mapping/merge alias semantics encoded in events; account removal, affected transaction account IDs, audit | no independent alias collection; event and canonical/account effects |

## Collections

`entities`, `institutions`, `connections`, `consents`, `accounts`, `rawPayloads`,
`ingestionRecords`, `candidates`, `transactions`, `evidence`, `receipts`,
`importBatches`, `recurringStreams`, `events`, `auditEntries`.

Position indexes, evidence lookup lists and provider-ID sets are derived runtime
indexes, not persisted effects. `forkForCommand` still copies their containers.
The journal result does not claim these indexes are independently serializable.
Core version/schema values cannot change within a scope; unknown input versions
are rejected, not silently normalized.

## External effects (not covered by core completeness)

| Layer | Responsibility / current treatment |
|---|---|
| `QestoLegacyBridge.canonicalFromQesto` | supplies canonical user intent incl. field lock tags and category override; existing function called unchanged |
| App `classification.policy` | passed as immutable policy; core fingerprint is owner metadata, app probe checks actual classification digest |
| `QestoReadModelService` | all app accounts and transaction projections, not new canonical facts; full projection retained |
| `projectSberTransactions` | existing presentation/classification rules; complete result retained |
| codec-v7 roots | unrelated budgets/goals/debts/investments/settings etc untouched; full codec equality checked |
| BudgetController / selectors | no partial UI publication implemented, no controller edits |
| SQLite / outbox / shadow / receipt / cursor | no storage changes or journal wiring; existing full transaction contract unchanged |

## Mutable references and protection

Default models have shared `tags`, consent `scopes`, connection `capabilities`,
receipt `items/userCorrections`, batch `warnings`, stream `transactionIds`, event
`payload` (arbitrary nested JSON), and policy `rules/redirects/validTagIds`.
The default core/fork does not deep-freeze them. The optional journal admission
copies these containers once, freezes new writes, and reuses frozen record values
between forks. This does not make the original public model API globally immutable.

Journal before/after JSON is detached and deeply read-only. The record scope seals
on success AND exception; a captured callback reference cannot keep writing to it.
The callback is trusted local synchronous code; not a sandbox for third-party code.
Asynchronous callbacks reject and abort. App authorization, ownership of actual
durable revision and conflict resolution remain outside this scope.
The sealed `restoreTransaction` entry is guarded before its private ID-index write;
otherwise a rejected tracked append could still poison a later prepared fork.
Unreviewed top-level model subclasses and custom policy subclasses are rejected,
not silently copied into base classes. Policy-only changes invalidate projections
even if the persisted lists were empty.

## Complexity and limits

No before/after scan of the whole profile builds the journal. Every list write
compares that record's exact JSON, records only changes and coalesces repeated slot
writes. Structural removal invalidates slot-coalescing indexes for that collection.
Sealing scans the touched effects only. Actual policy initialization still visits
N transactions, recurrence still scans/rebuilds, forks still copy list/index
containers. Rebuilt recurring records must be compared even if unchanged.
Therefore journal overhead scales with attempted writes/record size, NOT guaranteed
O(1) nor strictly only final changed count under bulk policy/reconciliation.

Completeness is evidence-backed for this version/covered scenarios, not a proof
for arbitrary future mutations. A new mutable model field/list/serialization rule
requires ownership + oracle regression review. Unknown record types/version or
unsupported list primitive fail closed. The independent full oracle is retained.
