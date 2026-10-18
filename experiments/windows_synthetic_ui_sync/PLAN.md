# Stage 4b

1. STOP GATE: actual controller, common app preparation and server executor must
   produce identical complete financial state under controlled clock/IDs, including
   tags/audit/events and ent-user binding. Do not wire UI networking before it passes.
2. Add minimal optional domain ports to existing backend and Coordinator. Defaults
   preserve 3a/3b behavior. Replay the common executor to validate incoming effects;
   compare all tags rather than broadening the old protected-field allowlist.
3. Extend the existing Windows worker with the existing Coordinator/transport.
   One owner serializes local edits, ACKs and remote apply. Publish durable incoming
   state without creating outbox commands. Early-reject unsupported controller writes.
4. Fresh explicit synthetic bootstrap only; tests for offline/conflict/lost response,
   revisions, restart/crash, key, cancellation, versions and unrelated v7 roots.
5. Two real controller/widget hosts; 1k/10k latency, UI event-loop and DB/RAM
   measurements. Apply regression suites, report constraints and stop.
