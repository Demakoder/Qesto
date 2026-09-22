# Status note

The follow-up [White Silver stabilization](white_silver_stabilization.md) supersedes the initial dark-theme compatibility and DPI behavior described below. See that report for 1.0.47+48.

# White Silver production migration

Reference: `qesto_overview_white_silver.html`. Native Flutter only; no demo data in production.

## Presentation map

| Area | Entry point / reusable UI | Migration |
| --- | --- | --- |
| Foundation | core/theme/qesto_theme, qesto_elements, qesto_card, states | Semantic tokens, bundled Onest/Prata/Noto Serif Display, Silver controls, Window compatibility wrappers |
| Desktop / mobile shell | desktop_app_shell, desktop_chrome, desktop_destination | Same destinations/callbacks; silver selection, compact tool chrome, responsive navigation |
| Overview | desktop_dashboard_page, overview_expense_trend_chart, overview_expense_map | Capital hero + period tool, chart/flow tools, planning rows, transaction log |
| Expenses / rhythm / merchants / categories | desktop_statistics_page + statistics/presentation | Shared windows, toolbars, table/chart treatment; retain category customization |
| Transactions | desktop_transactions_page, budget/transaction_details_screen | Spreadsheet hierarchy, adaptive rows, existing selection/sort/filter/details |
| Budget / recurring | desktop_budget_page, desktop_recurring_page, budget/widgets | Financial tool surfaces, progress rails, existing editors |
| Capital / accounts / debts | desktop_accounts_page, desktop_debts_page | Shared hero money, windows, compact controls; no balance recalculation |
| Investments / goals | desktop_investments_page, desktop_support_pages | Portfolio / goal tools and existing dialogs |
| Benefits / AI / settings | desktop_support_pages, benefits/* | Neutral product chrome; real merchant/category content retained |
| Imports / manual / voice / notifications / SMS / OCR | *_import/presentation, budget/add_expense_screen, voice_transaction/presentation | Shared theme, fields, dialogs, progress, review states; import pipelines unchanged |
| Banks | desktop_bank_connections_page + bank_browser/presentation | Presentation only. Never change runtime, auth, scheduling, parsers or policies |
| Auxiliary | history, trash, shared, savings, budget detail screens | Same shared surfaces and typography |
| Startup | qesto_app, states | Neutral loading / useful error; no separate onboarding route exists |

## Invariants

- Preserve controllers, routes, widget keys, calculations, period/filter/sort state and callbacks.
- No edits to domain/data/services/parsers/repositories or Synoball.
- Source fixtures are for widget/golden tests only.
- Unknown free money remains unknown, not zero. Cash flow is not balance.
- Keep saved theme preference; no colour-inversion filter in the new design.

## Checkpoints

- [x] Inventory / approved reference / migration boundaries.
- [x] Foundation and shared controls.
- [x] Shell and mobile navigation.
- [x] Overview.
- [x] Core finance.
- [x] Extended products.
- [x] Supporting flows and dark compatibility.
- [x] Regression tests, native goldens, consistency and local builds.

## Dark compatibility

White Silver is the approved material. Dark preference will use a native dark workspace / chrome with explicit light financial tool islands during this migration, rather than invert charts, merchant imagery or financial colours. This is compatibility, not the final Graphite theme.

## Implementation choices

- `DesktopCard` and `QestoCard` retain their API but delegate to `QestoWindow`. No second decoration system remains in those wrappers.
- `QestoButton` delegates to native Silver / secondary buttons. Native Flutter fields, selects, money fields, checkbox/radio/switch, dates, sheets, dialogs and tables are themed centrally rather than cloned into dozens of identical forwarding classes. Validation/controllers are untouched.
- Existing category/merchant colours are retained as user/content data; navigation, AI chrome and debt type accents use neutral tokens. Income/negative values use semantic green/burgundy.
- The graph/map have real compact/expanded tools via `OverlayPortal` and a reparented keyed subtree. Input and module state preservation is tested.
- Dark compatibility has dark native navigation/app chrome and explicitly light finance/overlay surfaces. No `ColorFiltered` remains in production UI.
- No separate onboarding screen exists to rewrite; startup loading/error and existing first-use empty states share the new foundation.
- Desktop sidebar, mobile drawer/bottom navigation and all destination semantics are unchanged.
- No portfolio performance, sync status, AI insight, forecast or budget value was invented for styling.

## Visual verification

Native Flutter goldens (real bundled fonts): component gallery, full Overview + sidebar at 1440, mobile Overview at 390, transaction log, budget, liquidity, debts, investments, goals, insights and benefits. They also cover chart/window/hero/silver button roles. HTML is a code/style reference, not a browser screenshot; exact pixel equivalence to a captured browser image is not claimed.

Fourteen dedicated design tests cover the font/colour roles, Cyrillic and rubles, long/negative amounts at enlarged text scale, real chart expansion on mobile and desktop, search, and an identical retained input element across expansion and Escape. Existing route/form/selection/import tests remain in the full suite; off-screen mobile test taps now explicitly scroll their targets into view.

The visual pass caught and corrected font overrides in dropdowns, button styles and custom chart painters, fixed-height clipping with the new fonts, and a missing Material ancestor in adaptive transaction rows. No financial rule was altered to satisfy a screenshot.

## Local build policy

Version: `1.0.46+47`. Windows uses the existing local-test updater with verified file copies, previous-build rollback and financial/browser-profile backups. This is not an Authenticode-signed public release.

The Android artifact is a **local test APK**, compiled with the project's explicit `QESTO_ALLOW_DEBUG_RELEASE_SIGNING=1` option because a private production keystore is not configured on this machine. The release-signing guard is unchanged. Do not publish this APK as a production release; upgrading a differently signed installation requires its original signing key, not erasing user data.

## Verified result — 17 September 2026

- `flutter analyze --no-pub`: no issues.
- Full `flutter test --no-pub --concurrency 2`: **542 passed, 8 skipped**, including the 14 design tests and 11 native golden snapshots. The skipped tests require explicit local financial fixtures or opt-in native PDF/OCR/Whisper integration; they are not claimed as verified.
- `git diff --check`: clean. Financial domain, repository, parser, bank runtime and Synoball sources are unchanged.
- Windows release build succeeded; existing local installation updated to `1.0.46+47` with verified copies and a previous-build/data/browser-profile backup. Start Menu launcher updated; absent desktop launcher restored to the same installed executable.
- Android release-mode **test** APK built successfully; application ID `ru.qesto.qesto`, versionCode `47`. APK v2 signature verified (local Android Debug key). Delivery: `Qesto-Android-1.0.46-test.apk` in the repository root, ignored by Git.
- No bank session was opened or synchronization triggered for this visual migration. Physical Android installation and live bank smoke tests were not performed.

Full Graphite material, further screen-specific layout polish and any financial-calculation discrepancy from the pre-existing read models remain separate work; this migration changes presentation only.
