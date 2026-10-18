# Stage 3b — synthetic Windows integration

Only this package and the experimental container may change. No app, shared
financial rules, real profiles, installation, Android, or public service.

1. Prove a narrow v7 adapter: existing Synoball note command; preserve every
   unrelated root section and local provenance; validate with the actual codec.
2. Add optional encrypted transport context and explicit projection to the
   experimental container. Old conservative bundle behavior remains the default.
   No silent upgrade of old containers; initialize only fresh synthetic clones.
3. CLI owner process + coordinator: immutable wire intent inside existing outbox;
   receipt validation; bounded retry; sequential pull with atomic context, shadow,
   projection and cursor. Do not rewrite queued commands or advance cursor on ACK.
4. Only one outstanding note per transaction. Different targets may converge;
   unresolved same-field proposals stay in outbox and overlay, never LWW.
5. Actual two-client/process, loopback PostgreSQL, fault/key/restart tests;
   real codec roundtrip, regression, source hashes, 1k/10k timings.
6. Report limitations and stop. Production integration requires a separate gate.
