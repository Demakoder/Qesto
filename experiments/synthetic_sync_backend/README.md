# Synthetic Sync Backend — Stage 3a

**Local experiment, not production. No real financial data. Do not publish it.**

Two independent command-line clients communicate over loopback HTTP with Dart
servers backed by a real PostgreSQL cluster. Only `transaction.set_note` is
implemented, using the existing shared Synoball core. No app repository, database,
profile, installed application or banking adapter is connected.

## Reproduce on this Windows workstation

Requires Dart 3.12.2, the repository's existing Flutter SDK (for app regressions),
and the existing storage feasibility package/build dependencies. No Windows
service, Docker, phone, emulator or public listener is needed.

```powershell
cd C:\Users\ARM\Documents\Qesto\experiments\synthetic_sync_backend
# Only for initial runtime preparation. Public EDB ZIP + pinned observed SHA-256.
./tool/download_postgres.ps1
./tool/run.ps1 -IncludeRegressions
```

The runner creates/resumes **only its own marked cluster** in `.runtime`, compiles
three separate executables, runs the tests, checks unchanged app/core sources,
writes `results/summary.json`, and stops that cluster in `finally`. Each integration
test gets two fresh synthetic workspaces, random test credentials and distinct
client files. Files are retained for investigation; nothing is reset silently.
`pubspec.lock` pins dependencies. Runtime ZIP/database/credentials/builds are ignored.

`run.ps1` has workstation-specific Dart/Flutter paths at the top. Adapt these paths
for another machine. `source_baseline.json` records this work session's sources:
on another checkout, differences are expected and require an explicit reviewed
baseline; the script will not silently overwrite it. Missing PG/runtime is an
error, not skipped integration coverage.

## Layout

```text
lib/
  protocol.dart    strict command, version, digest and signed cursor
  config.dart      loopback PG endpoint and bounded test identities
  domain.dart      existing Synoball updateTransaction + synthetic fixture
  database.dart    row-lock gate, atomic commit, repeatable-read pull
  server.dart      bounded HTTP endpoint handlers
  client.dart      synthetic durable-command/page-checkpoint adapter
sql/schema.sql    isolated schema, constraints, immutable history, RLS
bin/server.dart   normal entry point (no fault-control file)
tool/             cluster, fault/client executables, runner and evidence
test/             real-PG integration + protocol/domain parity
results/          synthetic, non-secret machine-readable evidence
```

## API slice

Every request requires the test bearer token, its bound `X-Device-Id`,
`X-Protocol-Version: 1`, and `X-Domain-Version: 1`. Token mappings are generated
locally, not built into source. They are **not production authentication**.

| Method/path | Meaning |
|---|---|
| `GET /sync/v1/capabilities` | Supported versions/command and body limit |
| `GET /sync/v1/workspaces/{w}/snapshot` | Bounded fixture bootstrap at a consistent head |
| `POST /sync/v1/workspaces/{w}/push` | One immutable note command |
| `GET /sync/v1/workspaces/{w}/changes?cursor=…&limit=…` | Whole ordered bundles, pinned high watermark |

```json
{
  "protocol_version": 1,
  "domain_version": 1,
  "workspace_id": "workspace-main-example",
  "workspace_epoch": "epoch-example",
  "device_id": "device-a",
  "change_id": "edit-example-1",
  "kind": "transaction.set_note",
  "transaction_id": "synthetic-tx-0",
  "base_revision": "0",
  "note": "Synthetic note"
}
```

`note` must be a string (empty clears visible text; null is rejected), at most
4096 UTF-8 bytes. Unknown fields/kinds, owner/device mismatch, wrong epoch/version
and reused ID with a different body fail closed. Accepted and conflict receipts
are immutable. Conflicts retain the attempted and current notes/revisions.

Money in canonical wire entities is `{"minor_units":"486122","currency":"RUB",
"scale":2}`; command bodies cannot assign money, trust, IDs or revision.
Push receipts contain a diagnostic `commit_seq`, **not a pull checkpoint**.

## Explicit limitations

- Loopback HTTP and PostgreSQL SCRAM only; no TLS, OIDC, expiring/revocable sessions,
  internet security review, server encryption-at-rest, or cross-device key recovery.
- Two tiny synthetic canonical transactions, not a full financial profile or
  primary-fact bootstrap protocol; no bulk import/financial command registry.
- Core state is stored as opaque JSON text. This is not a scalability benchmark or
  production DB normalization decision. One connection/request, workspace writer
  serialization; no server worker isolate/pool/load testing in this slice.
- Client uses a flushed sibling file + rename containing state/receipts/checkpoint.
  This proves the tested **process-exit before checkpoint** case, not encrypted
  SQLite, hardware durability or multi-writer client ownership. Pending commands
  are retained separately from authoritative state; no optimistic rebase.
- Signed cursors have workspace/epoch/version binding but no expiry, retention or
  compaction. Startup snapshot does not carry historical conflict review state.
- RLS protects correctly scoped queries; a compromised application DB credential
  can set another workspace context. Do not treat RLS as a substitute for trusted
  server authorization. Admin/test fixtures are privileged and outside the API.
- Native server process terminations and an actual SQL error are tested; power
  loss, disk I/O faults, failover, replication and production restore are not.

See `docs/sync/2026-10-11/Synthetic_Sync_Backend_Report.md` in the repository for
the evidence, gates and proposed next steps. The runner does not deploy anything.
