# Jido Integration V2 Market Data Connector

Stream baseline connector package.

Proves:

- stream-class capability publishing against the shared `RuntimeResult` substrate
- explicit environment and sandbox posture for feed-style pulls
- lease-bound auth and durable review artifacts/events for each batch
- repeated pulls with cursor advancement over a stable stream reference keyed by credential ref
- scope-gated admission (`market:read`)
