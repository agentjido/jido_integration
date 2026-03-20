# Jido Integration V2 Market Data Connector

Stream baseline connector package.

This package now publishes the accepted Phase 4 stream-family authored shape:
the authored operation targets Harness through `runtime.driver: "asm"`,
projects through the shared common consumer surface, and carries the canonical
`metadata.runtime_family` keys for an ASM-owned stream-capable session seam.

Proves:

- stream-class capability publishing against the shared `RuntimeResult` substrate
- common-surface projection through the single consumer projection contract
- explicit environment and sandbox posture for feed-style pulls
- lease-bound auth and durable review artifacts/events for each batch
- deterministic ASM-backed conformance through a package-local Harness test driver
- scope-gated admission (`market:read`)
