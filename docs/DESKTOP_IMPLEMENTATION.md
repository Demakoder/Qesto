# Qesto Desktop implementation

## Delivered

- Responsive desktop shell at widths from 900 px with expanded and compact
  navigation, global search, period context and keyboard shortcuts.
- Dashboard, transactions, budget, cash flow, accounts, recurring operations,
  goals, reports/categories, insights/data quality, benefits and system status.
- Transaction review queue, filters, virtualized rows, multi-select, bulk
  review/category actions, TSV export, editable details drawer, evidence and
  confidence display, and soft delete.
- Manual entry and existing receipt, statement and notification import flows.
  Voice input creates a Synoball candidate and requires confirmation before it
  becomes a posted transaction.
- Production starts only from persisted user data. Demo repositories and seeded
  financial records are not compiled into the application entry point.
- Windows-native statement selection, pure-Dart PDF extraction, local receipt
  image OCR and microphone capture work without Flutter plugins or Developer
  Mode symlinks. User state is stored atomically in `%APPDATA%\Qesto`.

## Synoball invariants

- Every source is adapted to `SynoballTransaction`, `TransactionCandidate` or
  another canonical Synoball entity before the UI consumes it.
- The desktop interface does not introduce a second transaction model, ledger
  or persistence layer.
- Source, evidence, confidence, classification reason, duplicate status and
  user overrides remain visible and auditable.
- Candidates stay separate from posted transactions until user confirmation;
  imported records retain source identity and provenance.
- Budget, forecasts, reports and assistant context are projections over the
  canonical state, not independent calculations persisted as truth.

## Verification

```powershell
cd apps/qesto_app
flutter analyze
flutter test
flutter build web --release
flutter build windows --release
```

The responsive widget suite covers 1440x900 and 1024x768 desktop layouts. The
interactive build was additionally inspected at both widths.
