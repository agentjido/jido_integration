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
- `GeneratedSensor`
- `GeneratedPlugin`

Current hardening guarantees:

- the authored catalog and projection structs now follow the canonical `@schema Zoi.struct(__MODULE__, ...)` pattern with derived `@type`, `@enforce_keys`, `defstruct`, `schema/0`, `new/1`, and `new!/1`
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
- `OperationSpec` and `TriggerSpec` now distinguish three layers explicitly:
  - provider inventory in connector-local catalogs
  - runtime-published manifest entries
  - projected common consumer surfaces through `consumer_surface`
- non-direct authored routing stays on the existing contract spine:
  - `runtime.driver`, `runtime.provider`, and `runtime.options` are the canonical authored routing keys for `:session` and `:stream` operations
  - the control plane does not synthesize an implicit `asm` default when authored `runtime.driver` is missing
  - common `:session` and `:stream` consumer surfaces must also declare canonical `metadata.runtime_family`
  - `:connector_local` remains the explicit authored escape hatch when a non-direct capability should stay off the generated common surface
  - target descriptors can advertise compatible runtime environments and workspace locations, but they must not rewrite authored runtime routing keys
- `schema_policy` is explicit on authored operations and triggers so placeholder schemas cannot silently leak into published or projected surfaces
- `ConsumerProjection` derives deterministic action, sensor, and plugin projection rules only from authored entries marked as normalized common consumer surfaces, and rejects duplicate projected action names or generated sensor collisions within one connector
- common projected triggers must declare deterministic `jido.sensor.name`, `jido.sensor.signal_type`, and `jido.sensor.signal_source` metadata, and those generated sensor contract names must stay unique within a connector while `:connector_local` triggers remain explicit exclusions from the generated common sensor surface
- `GeneratedAction`, `GeneratedSensor`, and `GeneratedPlugin` project those rules into the current real `Jido.Action`, `Jido.Sensor`, and `Jido.Plugin` APIs
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

`OperationSpec` and `TriggerSpec`

- use canonical Zoi-backed struct derivation
- carry explicit `consumer_surface` metadata:
  - `:common` means the entry projects into generated consumer surfaces
  - `:connector_local` means the entry is a stable runtime capability but not a generated common surface
- carry explicit `schema_policy` metadata:
  - `:defined` for concrete schemas
  - `:dynamic` for future runtime-resolved schemas
  - `:passthrough` only with an explicit justification, and never for a projected common surface
- may also carry authored late-bound schema metadata inside `metadata`:
  - `schema_strategy` to classify static versus late-bound behavior
  - `schema_context_source` to identify the governing lookup source
  - `schema_slots` entries with `surface`, `path`, `kind`, and `source`
  - `:none` is reserved for `:static` metadata; late-bound operations and slots
    must identify a real lookup source
- expose `OperationSpec.schema_strategy/1`, `schema_context_source/1`,
  `schema_slots/1`, `late_bound_schema?/1`, `runtime_driver/1`,
  `runtime_provider/1`, `runtime_options/1`, and `runtime_family/1` so
  connector-owned runtime enrichment can stay on the authored-contract spine
  without widening the public generated consumer surface

`ConsumerProjection`

- projects only authored entries whose `consumer_surface.mode == :common`
- derives generated action names from normalized surface semantics, not raw provider operation ids
- derives generated sensor modules and plugin subscriptions from the same authored trigger projection instead of a second trigger-only authored plane
- keeps provider operation ids stable as internal/runtime-facing capability ids
- leaves provider-specific long-tail inventory at the connector or SDK boundary instead of auto-projecting it into `Jido.Action` or `Jido.Plugin`

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
