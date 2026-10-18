# Gate C — passed, 2026-10-16

`results/owner-tests.jsonl` verifies prepare/commit/receipt/promotion, exactly-one
return, audit-only publication, foreign candidates, competing preparations,
policy/remote invalidation, before/after-COMMIT failures and same-ID recovery.

The owner admits a codec-detached profile, allows one outstanding candidate and
checks revision, identity, workspace, lineage, policy and generation before and
after awaited work. Unknown outcome invalidates RAM and blocks new commands.
After safe close/reopen the exact original immutable request is resolved; if
absent it is retried unchanged. Admission then uses verified durable state.
Native worker death still requires full process restart, not a second writer in
the same process. No UI integration claimed by these owner-only tests.
