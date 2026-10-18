# Encrypted client ↔ synthetic sync backend (3b)

Windows x64 experiment only. No production Qesto integration, no real data,
no Android, no public listener. Uses the existing 3a PostgreSQL cluster and API.
This is **not** a finished sync client for arbitrary financial changes.

## Run

From this directory, with the existing 3a cluster provisioned and previous
experiment dependencies/build artifacts prepared:

- 3a `build/fault_server.exe` and regression worker executables from its runner;
- storage `build/hardening/qesto_fault_shim.dll` (benchmark CPU counters, no fault
  installation in the benchmark), and `test/fixtures/container_profile_v7.json`;
- the app's existing `.dart_tool/package_config.json` for the real v7 codec gate.

These are produced by the earlier experiment runners; this runner fails rather
than skipping checks if a prerequisite is missing. SDK paths are workstation
specific in the runner/harness. On another checkout, review source-baseline
differences explicitly; do not overwrite the baseline to force a green result.

```powershell
./tool/run.ps1
```

The script builds the standalone AOT client and benchmark, runs new tests and
prior backend/core/storage/app regression suites, writes JSONL evidence, checks
source hashes, and stops the owned PostgreSQL cluster in `finally`. It never
launches or installs Qesto. Allow at least 1 GiB free for synthetic DBs, native
builds and compiler/test scratch space; the storage floor remains 256 MiB plus
the write-amplification headroom. Do not lower it to make benchmarks pass.

The CLI protocol is `client.exe <synthetic-config> <principal-index> <loopback-url>
<marked-container-directory> <action> [arguments]`, with `bootstrap`, `edit`,
`push`, `pull`, `sync`, `verify`. `edit` takes change ID, existing transaction ID
and note. `bootstrap` takes a synthetic codec-v7 fixture path. The harness creates
both clients before the first server mutation; bootstrap refuses nonzero heads.
Credentials live only in ignored `.runtime/`, never command-line arguments or
reports. Each CLI config contains only its own device identity/token/epoch;
server DB credentials, cursor signing key and other device tokens are rejected.
The privileged fixture harness/server have their own separate config.
`verify` prints **synthetic** state for harness assertions, not secrets.
`QESTO_3B_FAULT` is a test-only process exit hook; never use this CLI in production.

## Durable flow

Existing Synoball `applyNote` → full codec-v7 snapshot + immutable wire intent
in Container's local transaction → local ACK → loopback push → validated receipt
persisted separately → pull → validate whole page → atomic shadow + projected
full profile + encrypted transport metadata + numeric checkpoint.

Only incoming pages advance the checkpoint. Unknown delivery outcome retries the
same body/ID. Three attempts maximum (100/200 ms backoff); auth/version, invalid
receipts and incompatible financial fields stop immediately. A single coordinator
and exclusive lifetime database owner serialize delivery; there is no background
scheduler and therefore no second delivery worker/lease renewal loop.

Different-target note proposals can converge. A pending target retains its local
proposal over the authoritative shadow; same-field conflicts persist both notes
in the receipt and are reported as `requires_attention`. One outstanding command
per target; no generic automatic rebase or conflict resolution.

## Boundaries

- Full-profile root sections and local provenance are not replaced with the
  server's smaller Synoball snapshot. The note adapter preserves them, updates
  existing canonical entities and only changed legacy comments. Actual codec-v7
  decode/encode equality is checked using the app's existing codec, not a copy.
- Server audit/raw state is not replicated by 3a; local audit and provenance stay
  local, and incoming receipts remain durable evidence. Complete audit replication
  is a later protocol requirement, not implied by canonical convergence here.
- The optional container extension is initialized only on a fresh synthetic
  clone. Existing default 2b.0 bundle handling remains conservative. There is no
  automatic upgrade of old containers, and no production schema migration.
- Whole-profile serialization still runs in the CLI coordinator isolate; SQLite
  work uses `ContainerWriter`. A future Flutter integration must move the whole
  expensive operation off the UI isolate and define publication/CAS boundaries.
- Test process termination is not hardware power-loss proof. No hot restart claim
  after `Isolate.kill`; fault recovery uses a full process restart.
- Commands/page identities are retained without compaction. Opaque snapshots,
  initial bootstrap, policy parity, authentication and retention remain gates.

See `docs/sync/2026-10-12/Encrypted_Client_Sync_Integration_Report.md` at repo root.
