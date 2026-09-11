# Sber history navigation, slow loading and cancellation

Local test build: 1.0.43+44, 2026-09-10. Synoball's canonical schema is unchanged.

## Observed through read-only DEV

- Dashboard `/app/main`: section `История` contains an anchor labelled `Ещё`
  pointing to `/app/operations`. Another `Ещё` belongs to spending analytics.
- After the user clicked the history link: `/app/operations`, 14 operation detail
  links, the `Карта или счёт` filter and enabled `Показать ещё` button.
- The new read-only readiness probe returned `ready` on that live page.
- No CAPTCHA or other bank challenge was observed in these snapshots. A challenge
  cannot be inferred solely from a loading spinner or an unsafe-navigation notice.

## Changes

1. Global history follows the observed History → More SPA anchor once. Removed
   the additional direct `navigate('/app/operations')` reload. A retained product
   filter must still pass the global-history check; it is not silently ignored.
2. Product histories also require an actually rendered matching history link.
   There is no synthetic deep-link fallback. If the bank does not expose that
   control, the optional ownership sweep skips it; account ownership is not guessed.
3. DOM readiness waits up to 30 seconds for loading placeholders/spinners to clear.
   An operations shell without rows is not treated as empty history unless an
   explicit empty-history message is present. Account discovery has bounded retries.
4. After clicking `Показать ещё`, the extractor waits for new observations and a
   ready page. It does not click again if the first request stalls. Previously read
   rows remain in a partial result; no complete-coverage claim after timeout.
5. Recognized authentication/security prompts stop read/navigation actions and
   request user intervention. No allowlist changes, anti-bot evasion or TLS bypass.
6. Connections now expose `Отменить` during a run. The visible bank browser has
   its own cancel button. Automatic-sync toggles remain enabled while a run is active.
7. Turning automatic sync off cancels the active run and removes its future schedule.
   Cancelling only the current run leaves the hourly setting enabled and schedules
   the next normal cycle, without counting cancellation as a bank failure.
8. Cancellation immediately revokes the financial write lease. Connector/native
   command boundaries check that lease; background runtime shutdown is bounded.
   Visible cancellation stops loading without closing Qesto. Ownership remains locked
   until the old task finishes, preventing a new run overlapping unfinished work.
9. Cancelled jobs do not advance successful-history coverage. Existing data and
   previous completed imports remain; cancellation is not a rollback of an already
   committed import. In-flight native calls may take a short time to finish.

## Verification / remaining acceptance

- Full Flutter suite: 492 passed, 8 skipped. Static analysis: no issues.
  Native synthetic DOM regression: 20 cases passed, covering History More,
  loading versus explicit empty history, spinners and a security prompt.
- Full live sync with the new executable, slow network and native cancellation
  still requires acceptance after installation. No live bank actions were automated
  during this diagnosis; the user navigated and DEV only read the current DOM.
- The existing total runner deadline remains bounded. Very long history requests
  may still reach it; increasing waits is not a promise to wait indefinitely.

Deployment: Windows release 1.0.43+44 built and installed through the existing
desktop shortcut after the user closed Qesto. Backup:
`%LOCALAPPDATA%/Qesto/Backups/1.0.43+44-20260910-170333-087`.
The updater verified 277 runtime files and backed up 4 financial files,
1 protected key-store file and 984 browser-profile files. No Git publication.
