# Shared Synoball Core

Private, offline **pure Dart** package extracted from the actual Qesto working
tree on 2026-10-09. There is one reconciliation implementation, not a server fork.
This package implements neither networking nor a server nor storage.

## Boundary

```text
qesto_synoball_core.dart
  core/             canonical models, exact Money, state JSON, ingestion core
  ingestion/        adapter contracts, existing ID factory
  reconciliation/   existing deduplicator and source trust policy
  enrichment/       existing merchant/category/recurring policy and calendar
  adapters/         normalized input adapters, source/notification identities
```

The enrichment dependency is necessary: `SynoballCore` applies that existing
policy during reconciliation, user edits and restore. Removing it would change
behavior. Adapters here consume already prepared inputs; they do not control a
bank, read SMS/notifications from an OS, parse banking DOM or perform OCR.

```dart
import 'package:qesto_synoball_core/qesto_synoball_core.dart';

final core = SynoballCore(initialState: existingState);
final outcome = core.ingest(StatementAdapter(), preparedStatementInput);
final snapshot = core.state.toJson();
```

The host owns persistence, authorization, source bindings and validated inputs.
`PersistentSourceAdapter` remains an interface, not a network implementation.

## Compatibility and deterministic tests

- Existing `package:qesto/synoball/...` paths re-export these exact classes.
  No second runtime type universe or ID sequence is created.
- Schema fields, money representation, source hash algorithms and production
  IDs are unchanged. Existing canonical IDs are never rewritten by extraction.
- `SynoballCore(clock: ...)` controls bookkeeping timestamps only; the default is
  still `DateTime.now`. It does **not** implicitly change ID generation or source
  observation/business dates.
- The existing `SynoballIdFactory(clock: ...)` and test subclasses can provide
  deterministic IDs. Its production defaults/format/static sequence are intact.
  Hosts must inject the same test factory into both core and input adapters when
  a deterministic complete ingestion result is needed.
- Adapter `healthCheck()` timestamps still use wall clock, as before; these are
  diagnostic, not financial facts.

## Parity oracle

`test/goldens/legacy/` contains 13 frozen outputs captured **before** extraction
against the actual working tree (including prior uncommitted user changes), not
against git HEAD or the later compatibility exports. The manifest records the
SHA-256 of each original source file and baseline test/analyzer results.

Only the old core's uninjectable wall-clock bookkeeping is normalized:
canonical `createdAt`/`updatedAt`, event/audit `occurredAt` and event
`payload.changedAt`. IDs, money, directions, types/tags, business timestamps,
source identities, raw inputs, evidence, user locks and complete trash state are
compared. Separate runtime tests verify actual injected/default timestamps and
unnormalized JSON round trips. All new fixtures are synthetic.

There is intentionally no automatic golden updater: regenerating them from the
extracted code would destroy the independent oracle. Golden changes require
review of an explicitly approved financial behavior change, not a passing build.

## Checks

Run from this package directory:

```text
dart pub get --offline
dart analyze
dart test --reporter expanded
```

From `apps/qesto_app`, also run the app compatibility test and full regressions:

```text
flutter pub get --offline
flutter analyze --no-pub
flutter test --no-pub
```

CI includes standalone package analysis/parity as well as existing app checks.
`cryptography` is the same runtime dependency Qesto already used for stable
SHA-256 source identity; there is no new runtime library. `test` is development
only, allowing verification without a Flutter test runner. The package lock is
committed for reproducible checks in this private monorepo.

## Deliberately outside this slice

- Flutter UI/BudgetController, repository, vault, encrypted JSON codec, native
  bank browser and OS capture remain in Qesto.
- App-model-specific bridge/read models, financial projections and bank parsers
  remain app-owned. Some of those are already pure Dart, but are not needed for
  reconciliation and must not become package dependencies.
- No durable outbox, revision/cursor protocol, tenant guard, cloud auth,
  cross-device source/account binding or server persistence has been implemented.
- Current IDs/scopes retain their existing limitations; packaging does not make
  local-user identities globally unique or this mutable core thread-safe.

See the implementation report in `docs/sync/2026-10-09/` before the next slice.
