# CEF session persistence — 2026-09-08

Fix release: **1.0.39+40**. No Synoball schema or financial-data migration.

## Root cause

Qesto passed `<root>/<bank-profile-id>/cef` as the request-context cache path.
CEF 149 Chrome Runtime only loads a named disk profile when its directory is an
immediate child of the user-data root. Otherwise it falls back to an
OffTheRecord profile, even with `persist_session_cookies = true`.
The affected local bank profile had an empty legacy `cef` directory.

See the pinned runtime implementation:
[ChromeBrowserContext::InitializeAsync](https://github.com/chromiumembedded/cef/blob/2f1bfd8/libcef/browser/chrome/chrome_browser_context.cc).

## Changes

- Use `<root>/<bank-profile-id>`; keep the profile ID, metadata and PIN binding.
- Normalize root and profile paths to native Windows separators before giving
  them to CEF. The native probe reproduced an empty profile and lost cookies
  with inconsistent separators, then passed after normalization.
- Reject nested, root-equal and out-of-root paths, including resolved escapes.
- Preserve empty legacy folders; reject nonempty legacy folders instead of
  silently discarding or merging them. Such profiles need explicit migration.
- Create disk-backed browsers asynchronously; complete Dart creation from
  `OnAfterCreated`, after attaching the origin allowlist and browser state.
- Retain pending request contexts and match via CEF `IsSame`, not the address
  of a C++ wrapper. Reopening a profile can return a different wrapper.
- Keep normal CEF cookie persistence, session-cookie restoration, sandbox,
  certificate verification and per-profile isolation. Do not copy sessionStorage,
  default-profile cookies or bank credentials into another profile.

## Verification

- Flutter tests: **425 passed, 8 skipped**.
- `flutter analyze`: no issues.
- Windows release build: passed.
- Opt-in `qesto_cef_probe` compiles the actual production `WebviewHandler` and
  runs against the bundled CEF 149 runtime, with sandbox enabled. No bank login
  or bank data is used. Only two synthetic Secure/HttpOnly cookies at
  `https://qesto-fixture.invalid/` are written (one session, one persistent).
- `write`: create → set cookies → production close → reopen → read: **PASS**.
- `read`, in a separate process using the same fixture root: **PASS**.
- `read-isolated`, using a different profile under that root: **PASS** (neither
  synthetic cookie is visible). A Cookies database exists under the original
  profile, not merely in the default profile.
- Invalid nested/root-equal profile paths are checked by the native probe.

Build the opt-in target with `cmake --build build/windows/x64 --config Release
--target qesto_cef_probe`. Put its DLL and bootstrap EXE beside the bundled CEF
runtime/resources. Run sequentially with `--probe-mode=write`, `read`, and
`read-isolated`, using the same `--probe-root=<absolute new fixture directory>`.
The directory basename must start with `qesto-cef-probe-`; never use a user bank
profile. Result files contain only PASS/FAIL and fixed lifecycle stage labels.
The probe is not included in the application distribution.

## User verification still required

The former in-memory login cannot be recovered after it was closed. The user
must perform one full Sber login in the fixed version, then close/reopen the bank
page and restart Qesto to verify that Sber offers PIN login. Synthetic-cookie
tests prove runtime storage behavior, not the bank's decision to retain or
revoke authorization. Bank-side expiry/logout may still require full login.
