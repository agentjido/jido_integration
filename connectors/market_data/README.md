# Jido Integration V2 Market Data Connector

Stream baseline connector package plus the first common projected poll-trigger
proof.

## Runtime And Auth Posture

- runtime family: `:stream` for `market.ticks.pull`, plus one connector-owned
  direct poll trigger for `market.alert.detected`
- public auth binding is `connection_id`
- the authored stream routing contract is explicit through
  `runtime.driver: "asm"`
- the package uses short-lived credential leases for deterministic stream pulls
  and poll-trigger review
- scope-gated admission is explicit through `market:read`

## Capability Surface

This package publishes the accepted stream-family authored operation shape:

- capability id: `market.ticks.pull`
- shared common-surface projection through `consumer_surface.mode: :common`
- canonical `metadata.runtime_family` keys for an ASM-owned stream-capable
  session seam

It also publishes one common poll trigger:

- capability id: `market.alert.detected`
- generated sensor module resolved through
  `Jido.Integration.V2.ConsumerProjection.sensor_module/2`
- generated plugin subscription surface derived from that trigger projection
- matching `ingress_definitions/0` evidence for the poll-trigger boundary
- explicit `policy.environment.allowed` and `policy.sandbox.allowed_tools`
  metadata for the published trigger capability

Proves:

- stream-class capability publishing against the shared `RuntimeResult`
  substrate
- common-surface projection through the single consumer projection contract
- common trigger projection through the same authored-to-generated spine
- explicit environment and sandbox posture for feed-style pulls and poll
  triggers
- generated sensor and plugin subscription surfaces remain derivative of
  authored trigger truth
- durable checkpoint, dedupe, and ingress admission truth stay in
  `jido_integration`
- lease-bound auth and durable review artifacts/events for each batch
- deterministic ASM-backed conformance through a package-local Harness test
  driver

## Package Verification

From the package directory:

```bash
cd connectors/market_data
mix deps.get
mix compile --warnings-as-errors
mix test
mix docs
```

From the workspace root:

```bash
cd /home/home/p/g/n/jido_integration
mix jido.conformance Jido.Integration.V2.Connectors.MarketData
mix ci
```

## Live Proof Status

No package-local live proof exists yet. The accepted baseline for this package
is deterministic package tests, published ingress evidence, and root
conformance.

## Package Boundary

This package owns the stream capability contract, the connector-owned poll
trigger contract, the generated consumer surface, and the package-local
Harness-backed conformance seam.

It does not own hosted webhook routing, async dispatch handlers, or app-level
operator composition above the connector boundary.
