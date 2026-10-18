# Gate A — passed, 2026-10-16

`results/coverage-tests.jsonl`: full legacy executor and full ordered core replay
are independent test oracles. Note, clear, Unicode, repeated note, audit-only,
immutable aliases, stale app projection, 21/60 stale-policy and competing
candidates pass. `gate-a-stale.json` records the observed affected counts.

Projection dependencies are canonical transaction + receipt + known-account set
+ classification. Reuse existing QestoReadModelService and projectSberTransactions;
the latter can change a legacy transfer projection based on note text. Receipt /
account / policy changes outside this note scope are unsupported and rejected.
Admission does a one-time full comparison against persisted legacy rows. A command
projects every journal-changed canonical record, not just its target. It also
includes admission corrections of unchanged canonical records' legacy rows.

Membership/order/duplicate-ID anomalies require the old full path, not partial
publication. All derived analytics are marked for invalidation. Core events,
audit and recurring collections remain separate from app account/transaction
writes. No assertion of durability or UI safety at this gate.

Additive codec-v7 record methods delegate to the unchanged private mappings.
No financial model, wire protocol, schema, defaults or bank adapter changed.
