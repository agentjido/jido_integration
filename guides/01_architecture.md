# Architecture

The substrate is split into three layers:

1. contracts
2. runtime
3. host applications

That split is visible in both the package layout and the runtime rules.

## Contracts

The contracts layer defines the shared shapes and behaviours:

- connector adapters and manifests
- operation descriptors, envelopes, and results
- trigger and webhook route descriptors
- auth, dispatch, and webhook store behaviours
- error taxonomy
- gateway policies
- telemetry event names

This layer is where connectors and runtimes agree on what a valid request,
event, or record looks like.

## Runtime

The runtime layer owns restart-safe control-plane behavior:

- `Auth.Server`
- `Registry`
- `Webhook.Router`
- `Webhook.Ingress`
- `Webhook.Dedupe`
- `Dispatch.Consumer`
- disk and ETS implementations for store behaviours

The runtime is responsible for lifecycle truth. It decides when auth state is
valid, when ingress is accepted, and what durable records are written before
work proceeds.

## Host Applications

Host applications own the framework boundary:

- HTTP routes and controllers
- tenant and actor resolution
- choosing the correct runtime instance
- wiring store and vault adapters
- supervising and configuring `Dispatch.Consumer`
- registering dispatch callbacks

The host layer should delegate to the runtime rather than reimplement it.

## Execution Path

Outbound execution starts at `Jido.Integration.execute/3` and continues through
the internal execution pipeline in the contracts layer.

The runtime path is:

1. load the adapter manifest
2. find the operation descriptor
3. validate input schema
4. require auth context if scopes are declared
5. check scopes through `Auth.Server` or `Auth.Bridge`
6. apply gateway policy
7. resolve credentials or tokens when needed
8. call adapter `run/3`
9. validate output schema

That sequence keeps connector code focused on provider behavior instead of
control-plane setup.

## Gateway And Policy

`Jido.Integration.Gateway` is the admission-control layer for outbound work.

The contract is intentionally small:

- `Gateway.check/3`
- `Gateway.check_chain/3`
- `Gateway.Policy.compose/1`

Each policy returns one decision:

- `:admit`
- `:backoff`
- `:shed`

`Gateway.check_chain/3` evaluates every policy and composes the result
conservatively:

1. if any policy returns `:shed`, the chain returns `:shed`
2. otherwise, if any policy returns `:backoff`, the chain returns `:backoff`
3. otherwise, the chain returns `:admit`

That composition rule lives in `Gateway.Policy.compose/1`.

### Policy Behaviour

`Jido.Integration.Gateway.Policy` defines three callbacks:

- `partition_key/1`
- `capacity/1`
- `on_pressure/2`

The runtime currently uses the policy decision directly. The in-tree execution
path passes pressure through `gateway_pressure:` options, so callers can feed
the gateway current capacity data without coupling provider code to the
admission logic.

### Built-In Policies

Two policy modules ship in-tree.

#### `Gateway.Policy.Default`

`Jido.Integration.Gateway.Policy.Default` is the fallback policy used by
`Execution.execute/3` when no explicit policy is supplied.

It always:

- partitions to `:default`
- reports infinite token capacity
- admits the request

#### `Gateway.Policy.RateLimit`

`Jido.Integration.Gateway.Policy.RateLimit` is a token-bucket policy with a
GenServer-backed bucket store.

It exposes:

- `start_link/1`
- `try_acquire/2`

Its policy behavior is simple:

- `remaining_tokens <= 0` -> `:shed`
- `remaining_tokens < 10` -> `:backoff`
- otherwise -> `:admit`

The policy partitions by `connector_id` from the gateway envelope. That makes
connector-level rate shaping the default behavior.

### Telemetry From The Gateway

The execution path emits:

- `jido.integration.gateway.admitted`
- `jido.integration.gateway.backoff`
- `jido.integration.gateway.shed`

Those events are emitted before adapter code runs.

## Registry

`Jido.Integration.Registry` is the runtime registry for connector adapters.

It exists so callers can resolve an adapter by manifest ID at runtime instead
of passing modules around manually in every call path.

The public API is:

- `Jido.Integration.Registry.register/2`
- `Jido.Integration.Registry.unregister/2`
- `Jido.Integration.Registry.lookup/2`
- `Jido.Integration.Registry.list/1`
- `Jido.Integration.Registry.registered?/2`

Each registry entry stores:

- `id`
- `module`
- `manifest`
- `registered_at`

Registration validates:

- the adapter ID is a non-empty string
- the manifest is a `Jido.Integration.Manifest`
- `adapter.id/0` matches `manifest.id`
- an existing connector ID is not claimed by a different module

The registry emits:

- `jido.integration.registry.registered`
- `jido.integration.registry.unregistered`

The root facade exposes registry lookup through:

- `Jido.Integration.lookup/1`
- `Jido.Integration.list_connectors/0`

## Auth Ownership Split

The auth boundary is one of the most important architecture decisions in the
repo.

### What `Auth.Server` Owns

`Jido.Integration.Auth.Server` is the canonical auth lifecycle engine.

Its public surface includes:

- `Auth.Server.store_credential/4`
- `Auth.Server.resolve_credential/3`
- `Auth.Server.rotate_credential/3`
- `Auth.Server.revoke_credential/2`
- `Auth.Server.list_credentials/2`
- `Auth.Server.set_refresh_callback/2`
- `Auth.Server.create_connection/4`
- `Auth.Server.start_install/4`
- `Auth.Server.handle_callback/4`
- `Auth.Server.get_connection/2`
- `Auth.Server.transition_connection/4`
- `Auth.Server.transition_connection/5`
- `Auth.Server.check_connection_scopes/4`
- `Auth.Server.link_connection/3`
- `Auth.Server.mark_rotation_overdue/4`

Those functions cover four ownership areas.

#### 1. Credential Truth

`Auth.Server` stores and resolves credentials through `Auth.Store`
implementations. It is also responsible for token rotation and revocation.

#### 2. Connection Truth

`Auth.Server` creates and transitions connections through
`Auth.ConnectionStore` implementations. Scope gating checks use the connection
record, not host-maintained side data.

#### 3. Install-Session Truth

`Auth.Server.start_install/4` creates a durable install-session record with:

- a state token
- a nonce
- optional PKCE verifier and challenge
- connector and tenant binding
- actor and trace metadata
- expiry

`Auth.Server.handle_callback/4` validates and consumes that install session
exactly once through `Auth.InstallSessionStore.consume/2`.

That is why callback success does not depend on the original process staying
alive between install start and callback acceptance.

#### 4. Refresh Coordination

`Auth.Server.resolve_credential/3` handles expired OAuth credentials by
deduplicating refresh work per `auth_ref`. Waiters are coordinated outside the
GenServer and receive the same refresh result.

Refresh failure also feeds connection-state transitions. Terminal refresh
failures can move linked connections into `:reauth_required`.

### What `Auth.Bridge` Owns

`Jido.Integration.Auth.Bridge` is the host contract around that engine.

It defines callbacks for:

- `start_install/3`
- `handle_callback/3`
- `get_token/1`
- `revoke/2`
- `connection_health/1`
- `check_scopes/2`

`Auth.Bridge` exists so Phoenix, Ash, or another host layer can expose auth
flows without creating a second lifecycle source of truth.

The bridge should:

- route host requests into the correct `Auth.Server`
- resolve tenants and actors from host state
- decide which runtime instance and store/vault adapters to use
- present host-facing token or health views

The bridge should not:

- validate state tokens on its own
- duplicate callback anti-replay logic
- perform parallel scope gating rules
- own refresh semantics

## Dispatch Architecture

`Jido.Integration.Dispatch.Consumer` is the durable handoff between ingress
acceptance and callback execution.

### Host-Owned Dispatch Role

`Dispatch.Consumer` ships in the runtime package, but the root
`:jido_integration` application does not supervise a default instance.

That is the current contract, not an accidental omission.

Hosts own:

- starting and supervising the consumer process
- selecting dispatch and run store adapters
- tuning retry and backoff settings
- registering trigger callback modules

That keeps queue topology and durability choices in the host layer while the
substrate is still being pressure-tested across connector types.

The main public functions are:

- `Dispatch.Consumer.register_callback/3`
- `Dispatch.Consumer.dispatch/2`
- `Dispatch.Consumer.get_dispatch/2`
- `Dispatch.Consumer.get_run/2`
- `Dispatch.Consumer.list_dispatches/2`
- `Dispatch.Consumer.list_runs/2`
- `Dispatch.Consumer.replay/2`

### Dispatch Records

`Jido.Integration.Dispatch.Record` is the transport record written first.

It contains:

- `dispatch_id`
- `idempotency_key`
- tenant and connector identity
- trigger identity
- workflow selector
- normalized payload
- delivery status
- attempts
- optional `run_id`
- trace context
- error context

The important statuses are:

- `:queued`
- `:delivered`
- `:failed`
- `:dead_lettered`

### Run Records

`Jido.Integration.Dispatch.Run` is the execution record created when dispatch
is accepted.

It contains:

- `run_id`
- `attempt_id`
- `dispatch_id`
- `idempotency_key`
- tenant and connector identity
- trigger identity
- callback identity
- execution status
- attempt counts
- result
- error classification
- trace context
- timestamps

The run statuses are:

- `:accepted`
- `:running`
- `:succeeded`
- `:failed`
- `:dead_lettered`

### Logical Identity And Durable Lookup

The stable record identities are:

- `dispatch_id` for transport acceptance
- `run_id` for callback execution state

`idempotency_key` is the durable duplicate-binding key. `Dispatch.RunStore`
supports `fetch_by_idempotency/2`, and the local adapters reject a second
different `run_id` for the same idempotency key.

### Durable Store Contracts

Dispatch durability is split between two store behaviours:

- `Dispatch.Store`
- `Dispatch.RunStore`

The runtime ships both ETS and disk implementations for each behavior.

Those store behaviours now support filtered listing by status and scope fields.
`Dispatch.RunStore` also supports durable lookup by `idempotency_key`.

### Acceptance, Recovery, And Replay

When `Dispatch.Consumer.dispatch/2` accepts work, it:

1. validates the dispatch record
2. checks for an existing run binding by `idempotency_key`
3. writes the queued dispatch record
4. emits `dispatch.enqueued`
5. writes the accepted run record
6. moves the dispatch record to `:delivered` with the accepted `run_id`
7. emits `dispatch.delivered` and `run.accepted`
8. schedules callback execution

If any pre-ack store write fails, dispatch returns an error instead of reporting
success. The consumer will not claim accepted work that it cannot durably
recover.

On restart, once a callback is registered for a trigger, the consumer recovers:

- queued dispatch records
- accepted runs
- running runs
- failed runs awaiting retry

If a run fails enough times to exhaust `max_attempts`, the consumer:

- moves the run to `:dead_lettered`
- marks the dispatch record dead-lettered
- emits run and dispatch dead-letter telemetry

`Dispatch.Consumer.replay/2` only accepts runs in `:dead_lettered`. Replay
returns the run to `:accepted`, increments the attempt counter, clears error
state, emits `dispatch.replayed`, and schedules execution again.

For operator inspection, `Dispatch.Consumer.list_dispatches/2` and
`Dispatch.Consumer.list_runs/2` accept filters such as:

- `:status`
- `:statuses`
- `:tenant_id`
- `:connector_id`
- `:trigger_id`
- `:dispatch_id`
- `:idempotency_key`

## Webhook Ingress And Routing

Webhook handling is split across three runtime pieces:

- `Webhook.Router`
- `Webhook.Dedupe`
- `Webhook.Ingress`

### `Webhook.Router`

The router stores `Webhook.Route` records and resolves them in one of two
topologies:

- `:dynamic_per_install`
- `:static_per_app`

Dynamic routes are keyed by `install_id`.

Static routes are keyed by `connector_id` and optionally disambiguated by
tenant-resolution keys extracted from the request payload.

### `Webhook.Dedupe`

The dedupe process is a TTL-backed replay-protection layer. It uses the
`Webhook.DedupeStore` behaviour and the runtime ships ETS and disk adapters.

### `Webhook.Ingress`

Ingress is the control-plane entry point. It performs:

1. route resolution
2. verification-secret lookup
3. signature verification
4. duplicate rejection
5. trigger normalization
6. durable dispatch acceptance

Ingress returns an accepted run ID when durable dispatch succeeds. It does not
wait for the final callback result.

Ingress requires `:dispatch_consumer` in its options once the request reaches
dispatch acceptance. If no consumer is supplied, it returns
`:dispatch_consumer_required`. That is intentional because dispatch is currently
a host-owned runtime role.

## Error Taxonomy

The current taxonomy defines seven error classes.

That is the current code contract, even if older notes or planning docs refer
to eight.

| Class | Default retryability | Typical meaning |
| --- | --- | --- |
| `invalid_request` | `terminal` | malformed input or contract mismatch |
| `auth_failed` | `terminal` | missing auth, blocked state, revoked token, scope failure |
| `rate_limited` | `retryable` | backoff or shed decision from the gateway or provider |
| `unavailable` | `retryable` | transient upstream or local unavailability |
| `timeout` | `retryable` | operation timed out |
| `unsupported` | `terminal` | operation is not implemented or not allowed |
| `internal` | `fatal` | unexpected control-plane or adapter bug |

Every normalized `Error` carries:

- `class`
- `retryability`
- `message`
- optional `code`
- optional `upstream_context`

### Retryability Model

The retryability model is simple:

- `retryable` means the control plane may try again later
- `terminal` means retry is not expected to succeed without a state change
- `fatal` means there is a bug or systemic failure that should page an operator

### Where Classes Show Up

Common mappings in this repo include:

- `invalid_request`
  invalid manifest input, malformed operation input, missing route identifiers
- `auth_failed`
  missing connection context, connector mismatch, blocked connection state,
  refresh failure that requires re-auth
- `rate_limited`
  gateway backoff or shed decisions
- `unavailable`
  transient upstream HTTP failures or retryable refresh failures
- `timeout`
  reserved for timeout paths declared by the contract
- `unsupported`
  unknown adapter operations
- `internal`
  invalid adapter manifests, invalid adapter results, non-normalized connector
  errors

## Telemetry Events

`Jido.Integration.Telemetry.standard_events/0` defines the canonical telemetry
catalog.

Two things matter operationally:

1. the event name list is the public contract
2. not every standard event is emitted by the current Build-Now runtime yet

Where an event is cataloged but not emitted in-tree today, the table marks its
schema as reserved.

### General Rules

- All canonical events live under `jido.integration.*`.
- Metadata is sanitized before emission when it goes through
  `Jido.Integration.Telemetry.emit/3`.
- Most in-tree events currently use an empty measurements map.
- `dispatch_stub.*` events remain migration-only aliases and are not part of
  the canonical table below.

### Operation Events

| Event | Measurements | Metadata keys |
| --- | --- | --- |
| `jido.integration.operation.started` | none | `connector_id`, `operation_id`, `args` |
| `jido.integration.operation.succeeded` | none | `connector_id`, `operation_id` |
| `jido.integration.operation.failed` | none | `connector_id`, `operation_id`, `reason` |

The in-tree GitHub connector emits these directly.

### Auth Events

| Event | Measurements | Metadata keys |
| --- | --- | --- |
| `jido.integration.auth.install.started` | none | `connector_id`, `tenant_id`, `auth_descriptor_id`, `auth_type`, `state`, `actor_id`, `trace_id`, `span_id` |
| `jido.integration.auth.install.succeeded` | none | `auth_ref`, `connector_id`, `auth_type`, `state`; callback path also adds `tenant_id`, `auth_descriptor_id`, `actor_id`, `trace_id`, `span_id` |
| `jido.integration.auth.install.failed` | none | `connector_id`, `tenant_id`, `auth_descriptor_id`, `auth_type`, `failure_class`, `actor_id`, `trace_id`, `span_id` |
| `jido.integration.auth.token.refreshed` | none | `auth_ref`, `connector_id`, `auth_type`, `state`, `actor_id`, `trace_id`, `span_id` |
| `jido.integration.auth.token.refresh_failed` | none | `auth_ref`, `connector_id`, `failure_class`, `state`, `actor_id`, `trace_id`, `span_id`, `reason` |
| `jido.integration.auth.scope.mismatch` | none | either `auth_ref`, `connector_id`, `trace_id`, `span_id`, `actor_id`, `failure_class`; or `tenant_id`, `connector_id`, `state`, `actor_id`, `trace_id`, `span_id`, `missing_scopes`, `failure_class`, optional `expected_connector_id` |
| `jido.integration.auth.scope.gated` | none | `tenant_id`, `connector_id`, `state`, `actor_id`, `trace_id`, `span_id`, `missing_scopes` |
| `jido.integration.auth.revoked` | none | `auth_ref`, `connector_id` |
| `jido.integration.auth.rotated` | none | `auth_ref`, `connector_id`, `auth_type` |
| `jido.integration.auth.rotation_overdue` | none | `tenant_id`, `connector_id`, `auth_ref`, `auth_type`, `state`, `actor_id`, `trace_id`, `span_id` |

### Trigger And Webhook Events

`Webhook.Ingress` emits the current in-tree trigger and webhook events. The
remaining trigger names are still part of the catalog but reserved for future
paths.

| Event | Measurements | Metadata keys |
| --- | --- | --- |
| `jido.integration.trigger.received` | none | `tenant_id`, `connector_id`, `connection_id`, `trigger_id`, `trace_id`, `span_id`, `actor_id` |
| `jido.integration.trigger.validated` | none | `tenant_id`, `connector_id`, `connection_id`, `trigger_id`, `trace_id`, `span_id`, `actor_id` |
| `jido.integration.trigger.rejected` | none | `tenant_id`, `connector_id`, `connection_id`, `trigger_id`, `trace_id`, `span_id`, `actor_id`, `failure_class` |
| `jido.integration.trigger.dispatched` | none | `tenant_id`, `connector_id`, `connection_id`, `trigger_id`, `trace_id`, `span_id`, `actor_id`, `run_id` |
| `jido.integration.trigger.duplicate` | none | `tenant_id`, `connector_id`, `connection_id`, `trigger_id`, `trace_id`, `span_id`, `actor_id` |
| `jido.integration.trigger.retry_scheduled` | reserved | no in-tree emitter yet |
| `jido.integration.trigger.dead_lettered` | reserved | no in-tree emitter yet |
| `jido.integration.trigger.checkpoint_committed` | reserved | no in-tree emitter yet |
| `jido.integration.webhook.received` | none | `tenant_id`, `connector_id`, `connection_id`, `trigger_id`, `trace_id`, `span_id`, `actor_id` |
| `jido.integration.webhook.routed` | none | `tenant_id`, `connector_id`, `connection_id`, `trigger_id`, `trace_id`, `span_id`, `actor_id` |
| `jido.integration.webhook.route_failed` | none | `connector_id`, `trace_id`, `span_id`, `actor_id`, `failure_class` |
| `jido.integration.webhook.signature_failed` | none | `tenant_id`, `connector_id`, `connection_id`, `trigger_id`, `trace_id`, `span_id`, `actor_id`, `failure_class` |
| `jido.integration.webhook.dispatched` | none | `tenant_id`, `connector_id`, `connection_id`, `trigger_id`, `trace_id`, `span_id`, `actor_id`, `run_id` |

### Registry Events

| Event | Measurements | Metadata keys |
| --- | --- | --- |
| `jido.integration.registry.registered` | `count` | `connector_id`, `module` |
| `jido.integration.registry.unregistered` | `count` | `connector_id` |

### Gateway Events

| Event | Measurements | Metadata keys |
| --- | --- | --- |
| `jido.integration.gateway.admitted` | none | `connector_id`, `operation_id` |
| `jido.integration.gateway.backoff` | none | `connector_id`, `operation_id` |
| `jido.integration.gateway.shed` | none | `connector_id`, `operation_id` |

### Dispatch Transport Events

`Dispatch.Consumer` keeps transport telemetry separate from callback-execution
telemetry.

| Event | Measurements | Metadata keys |
| --- | --- | --- |
| `jido.integration.dispatch.enqueued` | none | `run_id`, `dispatch_id`, `tenant_id`, `connector_id`, `trigger_id`, `callback_id`, `attempt`, `trace_id`, `span_id`, `correlation_id` |
| `jido.integration.dispatch.delivered` | none | `run_id`, `dispatch_id`, `tenant_id`, `connector_id`, `trigger_id`, `callback_id`, `attempt`, `trace_id`, `span_id`, `correlation_id` |
| `jido.integration.dispatch.retry` | reserved | no in-tree emitter yet; current runtime retries at the run level rather than a separate transport loop |
| `jido.integration.dispatch.dead_lettered` | none | `run_id`, `dispatch_id`, `tenant_id`, `connector_id`, `trigger_id`, `callback_id`, `attempt`, `trace_id`, `span_id`, `correlation_id` |
| `jido.integration.dispatch.replayed` | none | `run_id`, `dispatch_id`, `tenant_id`, `connector_id`, `trigger_id`, `callback_id`, `attempt`, `trace_id`, `span_id`, `correlation_id` |

### Run Execution Events

| Event | Measurements | Metadata keys |
| --- | --- | --- |
| `jido.integration.run.accepted` | none | `run_id`, `attempt_id`, `dispatch_id`, `tenant_id`, `connector_id`, `trigger_id`, `callback_id`, `attempt`, `error_class`, `trace_id`, `span_id`, `correlation_id`, `causation_id` |
| `jido.integration.run.started` | none | `run_id`, `attempt_id`, `dispatch_id`, `tenant_id`, `connector_id`, `trigger_id`, `callback_id`, `attempt`, `error_class`, `trace_id`, `span_id`, `correlation_id`, `causation_id` |
| `jido.integration.run.succeeded` | none | `run_id`, `attempt_id`, `dispatch_id`, `tenant_id`, `connector_id`, `trigger_id`, `callback_id`, `attempt`, `error_class`, `trace_id`, `span_id`, `correlation_id`, `causation_id` |
| `jido.integration.run.failed` | none | `run_id`, `attempt_id`, `dispatch_id`, `tenant_id`, `connector_id`, `trigger_id`, `callback_id`, `attempt`, `error_class`, `trace_id`, `span_id`, `correlation_id`, `causation_id` |
| `jido.integration.run.dead_lettered` | none | `run_id`, `attempt_id`, `dispatch_id`, `tenant_id`, `connector_id`, `trigger_id`, `callback_id`, `attempt`, `error_class`, `trace_id`, `span_id`, `correlation_id`, `causation_id` |

### Artifact Events

Artifact transport events are part of the canonical namespace but are not
exercised by the current in-tree runtime.

| Event | Measurements | Metadata keys |
| --- | --- | --- |
| `jido.integration.artifact.chunk_emitted` | reserved | no in-tree emitter yet |
| `jido.integration.artifact.complete` | reserved | no in-tree emitter yet |
| `jido.integration.artifact.checksum_failed` | reserved | no in-tree emitter yet |
| `jido.integration.artifact.retransmit_requested` | reserved | no in-tree emitter yet |
| `jido.integration.artifact.gc_executed` | reserved | no in-tree emitter yet |

### Conformance Events

| Event | Measurements | Metadata keys |
| --- | --- | --- |
| `jido.integration.conformance.suite_started` | reserved | cataloged, but no in-tree emitter yet |
| `jido.integration.conformance.suite_completed` | `duration_ms` | `connector_id`, `profile`, `pass_fail` |

## Legacy Telemetry Alias

`jido.integration.dispatch_stub.*` remains emittable for migration
compatibility, and `Dispatch.Consumer` still emits those aliases.

They are intentionally excluded from `Telemetry.standard_events/0` and should
not be treated as the public contract for new connectors or host integrations.
