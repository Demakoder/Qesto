# Qesto Bank Browser DEV CLI

This helper talks only to an explicitly opened Qesto Bank Browser DEV session.
It reads the short-lived descriptor from `%LOCALAPPDATA%\Qesto\dev\session.json` and sends authenticated commands to the loopback bridge.

From the repository root on Windows:

```powershell
.\tools\qesto-browser\qesto-browser.cmd status
.\tools\qesto-browser\qesto-browser.cmd snapshot --limit 120
.\tools\qesto-browser\qesto-browser.cmd query "#HISTORY"
.\tools\qesto-browser\qesto-browser.cmd navigate "https://online.sberbank.ru/app/operations"
.\tools\qesto-browser\qesto-browser.cmd run-extractor .\tools\sber\extractors\debug_accounts.js
```

The CLI always prints JSON so it is safe to consume from scripts. `--json` is accepted as a no-op compatibility flag. If DEV Mode is not open, it exits with `No active Qesto Bank Browser DEV session.`

The bridge is loopback-only, uses a new bearer token for every session, and blocks clicks that look like financial mutations. It never exports cookies or writes DOM/network dumps automatically.
