# Gate D — verified synthetic UI publication

Passed `flutter_runner/test/delta_test.dart`: six real-worker/controller tests
(`results/flutter-delta.jsonl`). Ordinary and audit-only writes publish one delta,
zero full reloads, after native COMMIT and verified receipt. Before-commit UI and
notification count remain unchanged. Full codec-v7 parity with the original
executor is asserted, not merely matching totals.

The stale-policy 21/60 fixture has a different controller admission baseline:
strict before-image checks reject partial application and invoke one verified full
reload. All policy neighbours then match the full oracle. No partial UI changes
are made before validation of every projection. Dispose, cancellation and local
read-model refresh during an in-flight commit report unknown outcome, no false
success and no speculative publication.

Opt-in only: production/default controllers still use the previous path. Typed
core replay is presentation-only; it cannot prove durability or execute remote
financial commands. Ordinary 60-record delta is 4,819 JSON-equivalent bytes versus
112,110 full codec bytes; this is not a physical Dart object-graph byte count.
Gate E may proceed; no production readiness claim follows from this gate.
