# Jido Integration V2 Contracts

Public structs and behaviours for the greenfield platform:

- `ArtifactRef`
- `Capability`
- `Credential`
- `CredentialLease`
- `Manifest`
- `InvocationRequest`
- `CredentialRef`
- `Run`
- `Attempt`
- `Event`
- `RuntimeResult`
- `Gateway`
- `Gateway.Policy`
- `PolicyDecision`
- `TargetDescriptor`
- `TriggerCheckpoint`
- `TriggerRecord`
- `Connector`
- `ConsumerProjection`
- `GeneratedAction`
- `GeneratedPlugin`

Current hardening guarantees:

- `ArtifactRef` is a first-class public object with explicit checksum, transport, payload reference, retention, and redaction metadata
- `TargetDescriptor` is a first-class public object with explicit capability identity, runtime class, semantic version, health, location, and compatibility negotiation inputs
- `Run` is the durable work record and can carry artifact refs plus an optional target id
- `Run.status` distinguishes execution failure from pre-attempt `:denied` and `:shed` outcomes
- `Attempt` identity is deterministic from `run_id` and monotonic `attempt`
- `Event` uses a canonical control-plane envelope with `schema_version`, attempt-aware sequencing, trace fields, and optional `payload_ref` maps
- `RuntimeResult` is the shared connector/runtime emission contract for output, reviewable events, and durable artifact refs
- `Gateway` is the shared admission plus execution-policy request shape used before dispatch
- `Gateway.Policy` is the normalized capability-side security contract for actor, tenant, environment, runtime, operation, and sandbox checks
- `PolicyDecision` can allow work, deny it, or shed it before attempt creation
- `InvocationRequest` is the typed public invoke helper that normalizes stable facade fields, uses `connection_id` as the public auth binding, and derives the requested capability allowlist by default
- `ConsumerProjection` derives deterministic action and plugin projection rules from the authored manifest without reintroducing handwritten capability catalogs, and rejects duplicate projected action names or module collisions within one connector
- `GeneratedAction` and `GeneratedPlugin` project those rules into the current real `Jido.Action` and `Jido.Plugin` APIs
- generated actions build typed `InvocationRequest` structs and call the fixed `Jido.Integration.V2.invoke/1` facade path rather than honoring a caller-supplied invoker module
- `CredentialRef` remains durable while `CredentialLease` is the short-lived execution boundary
- `Credential` carries durable subject/scope/auth metadata plus secret-bearing fields that are meant to stay behind auth APIs
- `CredentialLease` carries only the execution-time payload needed for a bounded lease lifetime
- `TargetDescriptor` uses a separate target-capability namespace from connector capabilities
- `TriggerRecord` preserves trigger-to-run causation plus rejection truth at the control-plane boundary
- `TriggerCheckpoint` keeps polling cursors explicit and durable

## Public Objects

`ArtifactRef`

- stores `artifact_id`, `run_id`, `attempt_id`, `artifact_type`, `transport_mode`, `checksum`, `size_bytes`, `payload_ref`, `retention_class`, and `redaction_status`
- validates the `payload_ref` contract from the artifact transport spec and rejects local file paths
- keeps forward-compatible metadata without turning artifacts into inline blobs by default

`TargetDescriptor`

- stores `target_id`, `capability_id`, `runtime_class`, `version`, `features`, `constraints`, `health`, and `location`
- keeps unknown fields in `extensions` so mixed-version descriptors remain survivable
- exposes explicit compatibility checks plus runspec/event-schema version negotiation

`InvocationRequest`

- stores the stable public invoke fields such as `capability_id`,
  optional `connection_id`, `input`, actor/tenant/environment identity,
  sandbox posture, and optional target selection
- keeps non-reserved extension opts explicit so callers can pass additional
  runtime context without collapsing back to an untyped map wrapper
- exposes `to_opts/1` so `invoke/1` and `invoke/3` can share one normalized
  request shape

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `jido_integration_v2_contracts` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_integration_v2_contracts, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/jido_integration_v2_contracts>.
