# Jido Integration V2 Market Data Connector

Stream baseline connector package.

This package still targets the `integration_stream_bridge` compatibility shim.
That keeps the migration proof around for feed-style fixtures, but it should be
treated as temporary architecture rather than the target model for new runtime
composition work.

Proves:

- stream-class capability publishing against the shared `RuntimeResult` substrate
- explicit environment and sandbox posture for feed-style pulls
- lease-bound auth and durable review artifacts/events for each batch
- repeated pulls with cursor advancement over a stable stream reference keyed by credential ref
- scope-gated admission (`market:read`)
