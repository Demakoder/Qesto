# Gate E — functional pass; performance/resource gates NOT met

2026-10-17. Two real rendered Flutter controllers exchange notes over loopback
with the same full AOT server executor and Protocol v1. Forward/reverse, concurrent
offline edits, same-field conflict, lost ACK, repeated page, malformed incoming
effects, process crashes and worker death pass. The existing integration suite is
imported unchanged, with the effects factory and freshly compiled child probe.

Local delta publication passes full codec-v7/server equality. Incoming pages still
use the old complete financial validation/replay, atomic apply and full UI result;
partial remote publication is NOT implemented or claimed.

Matched 10k medians (three trials per separate Flutter process): local 5.181 →
3.060 s; sender 15.368 → 17.508 s; receiver 10.482 → 10.548 s. Peak host RSS
804.2 → 1036.1 MiB. Payload JSON-equivalent 15,097,157 → 4,824 bytes. No shared
core oracle was disabled. 50k owner ready hits the unchanged 30 s timeout; the sole
test host exits, no in-process native-owner replacement. Performance and 50k
readiness remain red, despite functional/security evidence.

Proceeding to production integration is NOT approved by these results. Stop at
the report; future memory/remote/startup optimization requires a separate slice.
