# Jido Integration V2 Market Data Connector

Stream baseline connector package plus the first common projected poll-trigger
proof.

This package now publishes the accepted Phase 4 stream-family authored shape:
the authored operation targets Harness through `runtime.driver: "asm"`,
projects through the shared common consumer surface, and carries the canonical
`metadata.runtime_family` keys for an ASM-owned stream-capable session seam.

It also now publishes one Phase 5 common poll trigger:

- capability id: `market.alert.detected`
- generated sensor module:
  `Jido.Integration.V2.Connectors.MarketData.Generated.Sensors.MarketAlertsDetected`
- generated plugin subscription surface derived from that trigger projection
- matching `ingress_definitions/0` evidence for the poll trigger boundary
- explicit `policy.environment.allowed` and `policy.sandbox.allowed_tools`
  metadata for the published trigger capability

Proves:

- stream-class capability publishing against the shared `RuntimeResult` substrate
- common-surface projection through the single consumer projection contract
- common trigger projection through the same authored-to-generated spine
- explicit environment and sandbox posture for feed-style pulls and poll triggers
- generated sensor and plugin subscription surfaces remain derivative of
  authored trigger truth
- durable checkpoint, dedupe, and ingress admission truth stay in
  `jido_integration`
- lease-bound auth and durable review artifacts/events for each batch
- deterministic ASM-backed conformance through a package-local Harness test driver
- scope-gated admission (`market:read`)
