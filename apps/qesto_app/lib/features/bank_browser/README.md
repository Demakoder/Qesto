# Qesto Bank Browser Runtime

This module is a local browser foundation for future bank connectors. It is not
a bank parser and it does not write financial data to Synoball.

Security boundaries:

- each `BankProfile` owns an exclusive CEF RequestContext/cache folder under the
  current Windows user's local application data;
- browser storage is not placed in Qesto's financial store, backup or sync;
- the JavaScript/native bridge, browser extensions, DevTools in release,
  password autosave, autofill, downloads and site permissions are disabled;
- top-level navigation is HTTPS-only and restricted to connector-configured
  origins; unknown origins are blocked before navigation;
- certificate challenges are never bypassed;
- persisted page metadata has query parameters, fragments and credentials
  removed;
- deleting a connection recursively deletes its explicit profile directory
  after the WebView environment has closed.

`BrowserAutomation` is deliberately an unimplemented boundary. A later parser
must be reviewed separately and must not gain access to credentials, OTP fields,
raw browser storage or unrestricted native APIs.
