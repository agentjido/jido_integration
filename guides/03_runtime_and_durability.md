# Runtime And Durability

Durable store contracts exist for:

- credentials
- connections
- install sessions
- webhook routes
- dedupe keys
- dispatch records
- run records

The runtime ships two implementations:

- disk-backed stores for durable local and test use
- ETS-backed stores as explicit local-development adapters

Auth-specific baseline:

- `Auth.Server` is the canonical lifecycle engine and already persists
  credentials, connections, and install sessions through those store contracts
- install sessions are durable, TTL-bound, and consumed exactly once during
  callback acceptance
- callback validation keeps PKCE, expiry, and connector checks inside
  `Auth.Server`, even when the callback arrives after a server restart
- `Auth.Bridge` chooses how a host app routes requests into that engine and how
  it wires store or vault adapters around it

Shared contract suites now enforce the local adapter semantics for:

- credential stores
- connection stores
- install-session stores
- dedupe stores
- dispatch stores
- run stores

Restart-safe behavior is proven in tests for:

- auth callback recovery after `Auth.Server` restart
- duplicate callback rejection after the first successful consume
- disk-backed store adapter restart recovery
- dispatch consumer recovery
- replay from dead-lettered runs after consumer restart
- reference-app recovery across consumer restart

Durability only matters if the control-plane path uses it. That is why ingress
enqueues through `Dispatch.Consumer` instead of calling adapter trigger code
directly.

The current dispatch boundary is explicit: the root OTP application does not
supervise `Dispatch.Consumer`. Hosts own that process so they can choose one
consumer, many consumers, or different local store/backoff settings without the
substrate locking in a premature default topology.

The in-tree runtime now freezes the important logical identities and recovery
lookups:

- `dispatch_id` is the stable transport-record identity
- `run_id` is the stable execution-record identity
- `idempotency_key` durably resolves an existing run binding
- dispatch and run stores support filtered listing by status and scope fields

The acceptance boundary is also stricter now:

- success is returned only after the pre-ack durable writes complete
- if a pre-ack store write fails, dispatch returns an error instead of falsely
  acknowledging acceptance
- dead-lettered runs remain durably replayable

The consumer now emits two telemetry families so operators can distinguish
transport from execution:

- `jido.integration.dispatch.enqueued|delivered|retry|dead_lettered|replayed`
  describe dispatch-record movement through the durable handoff boundary
- `jido.integration.run.accepted|started|succeeded|failed|dead_lettered`
  describe callback execution for the persisted run record

The current Build-Now consumer emits `enqueued`, `delivered`, `dead_lettered`,
and `replayed`. `dispatch.retry` remains part of the canonical contract for the
future transport-retry path, but this in-proc runtime does not yet exercise a
separate dispatch delivery retry loop.

Legacy `jido.integration.dispatch_stub.*` names are retained only as temporary
compatibility aliases during migration. They are not part of the public
contract returned by `Jido.Integration.Telemetry.standard_events/0`.
