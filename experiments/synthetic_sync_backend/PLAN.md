# Stage 3a — synthetic loopback backend

## Repository findings and boundary

- Shared `qesto_synoball_core` is pure Dart. Use its existing `updateTransaction`
  method for the only supported command: `transaction.set_note`. No second
  reconciliation algorithm, production persistence edits, migrations or UI.
- The 2b.0 container stores full codec-v7 projections and defers pending-local
  remote reconciliation. This experiment instead uses a small **synthetic client
  adapter**, with immutable pending commands and one durable page/checkpoint file.
  It is not a production storage replacement or a claim of solved rebase.
- PostgreSQL is not installed/on PATH. Use an isolated portable distribution,
  separate cluster, SCRAM credentials, loopback, no Windows service. Never use an
  existing database. Runtime artifacts and random credentials stay ignored.
- Add only `postgres` (PG wire driver); crypto/test/core are already used in the
  repository. `dart:io` supplies HTTP, process orchestration and test clients.

## Implementation / verification order

1. Capture unchanged app/core sources; establish local PG and dependency versions.
2. Strict protocol, fixture, shared-core note executor, per-workspace row-lock
   commit gate. State + receipt + complete-entity bundle + head in one transaction.
3. Loopback HTTP with bounded body, allowlisted synthetic tokens mapped to
   workspace/user/device, signed workspace/epoch/version-bound cursors.
4. Two clients with durable commands and atomic page/checkpoint, explicit
   conflicts, no optimistic financial mutations or automatic conflict resolution.
5. Real PG multi-process integration: replay, collision, concurrent different
   records, stale same record, late-commit cursor, server termination before/after
   commit, DB error, postcommit response loss, security, client checkpoint failure.
6. Core/container regressions, analyzer, machine-readable evidence, self-review,
   report and stop. No public endpoint, app install, production auth or real data.

## Important contracts

- Server assigns entity revisions; workspace transactional bigint is NOT a
  sequence. Every writer holds workspace row lock until commit/rollback.
- Conflict is a committed outcome containing the attempted note and authoritative
  revision/value. It has an immutable receipt and log entry, not a silent overwrite.
- Idempotency uses workspace + change ID + canonical validated command digest;
  replay does not advance any revision. Receipt never advances client pull cursor.
- Read head/page from a repeatable-read view. Pin H in signed cursors; no skipped
  unpublished sequence. Epoch mismatch fails closed. No retention in this slice.
- Test-only crash hooks are injected by the harness, not HTTP payload/headers.
- Financial payloads/credentials never leave the local machine. Downloading public
  tools/packages is not financial-data transfer.
