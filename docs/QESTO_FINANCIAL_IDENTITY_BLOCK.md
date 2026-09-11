# Financial identity block — local build 1.0.42+43

Updated: 2026-09-10. This is a partial delivery of the financial-data audit,
not a declaration that live bank reconciliation is complete.

## Implemented

- Sber provider transaction IDs and product IDs are scoped by connection.
  A changed description/fingerprint does not create a new provider operation;
  different provider IDs are not collapsed merely because their display rows match.
- Legacy identity adoption is one-to-one and uses preserved source evidence where
  available. Monetary signatures use minor units, not rounded rubles.
- Batch reconciliation evaluates competing candidates before committing any of
  them. Ambiguous cross-source matches go to review, independently of row order.
- Matching can use original accepted source observations after a user has edited
  the canonical operation. This does not authorize replacing user overrides.
- Excel period/category aggregates overlapping detail rows in a compatible account
  are flagged for review instead of blindly summed. This is not universal detection
  across unrelated Excel workbooks or different account identities.
- Sber imports preserve connection/institution/external-product metadata. Retained
  product identifiers can resolve operations when fresh product discovery fails.
- Observed card-history resources support a bounded read-only account-mapping sweep
  after global history extraction. Only exact provider ID/date/minor amount/currency/
  direction matches with a unique owner acquire an account. Conflicting or absent
  evidence leaves an operation unassigned. Scoped rows do not inflate global counts.
- Global history navigation clears a previous product filter and verifies its state.
- Explicit card/account relationships are merged only when unambiguous in the fresh
  facts. Linked card representations use the account's balance, not a sum of both.
- PDF preview allows choosing an existing currency-compatible account. Confirmed
  mappings are stored through existing Synoball events using a hash of the full
  statement account number, not its last four digits. The mapping survives account
  merges; silent reassignment, including dangling historical links, is refused.
- Importing a historic PDF into an existing account preserves its current balance.
  Account/source-link/ingestion changes are staged before replacing the live core.
- Notification auto-import requires a sufficiently certain account match. An unknown
  or colliding suffix no longer falls back to an arbitrary single bank card. Such
  notifications remain in the native inbox; this does not create a new account UI.
- The Qesto projection respects manual category/type overrides and stops showing an
  unresolved-account marker when the canonical operation has a known real account.

The canonical Synoball serialization schema is unchanged. Adapter DTOs were extended;
confirmed source-account mappings use the existing generic event mechanism.

## Verification

- Full Flutter regression suite: 482 passed, 8 skipped. Static analysis: no issues.
  Windows release build 1.0.42+43 succeeded. The deployment result is recorded below.
- Chromium DOM regression: 15 synthetic cases passed (including scoped product
  context and card-only wallet tiles). This does not exercise live Sber navigation.
- Private local PDF regression: all 125 parsed rows reconcile with the printed
  income/outflow and opening/closing balances to the kopeck.
- The saved web fixture yields 114 monetary rows; repeating that import adds zero
  new operations. It is not an identical-account comparable fixture to the PDF;
  the count difference cannot be reported as exactly 11 missing operations.
- Added tests cover competing batch claims, source evidence after edits, kopeck
  differences, aggregate/detail overlap, profile isolation, replay without fresh
  product discovery, confirmed PDF linking, persistence, and unsafe remapping.

## Still required before closing block 1

1. Live acceptance of the new card-history sweep and clearing of product filters.
   The earlier DEV session expired before this implementation could be exercised.
2. An identical-period, identical-account web/PDF reconciliation, including transfers
   and refunds. Card histories may omit account-level transfers and deposit activity.
3. Assess long-history execution against the existing runner deadline. The extra
   mapping sweep is bounded, but a first long sync may still reach that deadline.
4. Review unresolved account references and conflicting evidence without guessing.
   A missing source fact cannot be reconstructed solely from a balance difference.
5. Separate work for paired internal transfers, bundled fees, netted refunds and
   broader aggregate/detail overlap across independently named source accounts.
6. Evidence-driven repair of pre-existing duplicates or previously lost rows.
   No wholesale historical deletion/merge or reset of the user's ledger is performed.

## Local installation

Installed 1.0.42+43 on 2026-09-10 through the existing desktop shortcut. Identity
`ru.qesto / Qesto` and shortcut DEV arguments are preserved. All 856 user-data files
(4 financial, 1 protected key-store, 851 browser-profile files) have identical hashes
before and after deployment; no files were added or removed in these data roots.

Backup: `%LOCALAPPDATA%/Qesto/Backups/1.0.42+43-20260910-075603-580`.
The previous executable/runtime and shortcuts are recoverable there. The updater
verified all 277 copied runtime files. Qesto was closed and was not force-terminated
or reopened for live bank testing. No public release signing or Git publication is
implied by this local test build.
