# Jido Integration Contracts

Public structs, behaviours, and projection rules for the greenfield platform.

This package is the contract spine. It defines the canonical objects used by
auth, control-plane durability, runtime invocation, and generated consumer
surfaces.

It now also documents the lower-boundary contract packet that the lower acceptance gateway is
allowed to carry without re-exporting raw `execution_plane` package surfaces.

## Public Types

- `ArtifactRef`
- `AuthSpec`
- `BoundaryCapability`
- `Capability`
- `Credential`
- `CredentialLease`
- `Manifest`
- `InvocationRequest`
- `CredentialRef`
- `DerivedStateAttachment`
- `Run`
- `Attempt`
- `Event`
- `RuntimeResult`
- `InferenceRequest`
- `InferenceExecutionContext`
- `EndpointDescriptor`
- `BackendManifest`
- `ConsumerManifest`
- `CompatibilityResult`
- `InferenceResult`
- `LeaseRef`
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
- `ReviewProjection`
- `CanonicalJson`
- `SubmissionIdentity`
- `AuthorityAuditEnvelope`
- `ExecutionGovernanceProjection`
- `SubmissionAcceptance`
- `SubmissionRejection`
- `BrainInvocation`
- `LowerEventPosition`
- `ClaimCheckLifecycle`
- `InstallationRevisionEpoch`
- `LeaseRevocation`
- `RetryPosture`
- `AccessGraph.Edge`
- `AccessGraph`
- `MemoryFragment`

## Core Guarantees

- all authored and projected structs follow the canonical `@schema
  Zoi.struct(__MODULE__, ...)` pattern with derived `@type`, `@enforce_keys`,
  `defstruct`, `schema/0`, `new/1`, and `new!/1`
- `ArtifactRef` is a first-class public object with explicit checksum,
  transport, payload reference, retention, and redaction metadata
- `TargetDescriptor` is a first-class public object with explicit capability
  identity, runtime class, semantic version, health, location, and
  compatibility negotiation inputs
- `Run` is the durable work record and can carry artifact refs plus an optional
  target id
- `Run.status` distinguishes execution failure from pre-attempt `:denied` and
  `:shed` outcomes
- `Attempt` identity is deterministic from `run_id` and monotonic `attempt`
- `Event` uses a canonical control-plane envelope with `schema_version`,
  attempt-aware sequencing, trace fields, and optional `payload_ref` maps
- `Receipt` now projects durable lower run, attempt, event, and artifact
  records into Mezzanine-safe lower receipts, terminal execution outcomes, and
  `Mezzanine.WorkflowReceiptSignal.v1` attrs. The projection carries only
  lower IDs, event refs, artifact IDs, provider correlation IDs, lifecycle
  hints, and normalized outcome refs; raw provider payload bodies stay in lower
  event/artifact storage.
- `RuntimeResult` is the shared connector/runtime emission contract for
  output, reviewable events, and durable artifact refs
- the phase-0 inference contract seam extends that same contracts package with
  request, context, endpoint, compatibility, result, and lease shapes while
  keeping the durable cross-repo form JSON-safe under `contract_version:
  "inference.v1"`
- `Gateway` is the shared admission plus execution-policy request shape used
  before dispatch
- `Gateway.Policy` is the normalized capability-side security contract for
  actor, tenant, environment, runtime, operation, and sandbox checks
- `PolicyDecision` can allow work, deny it, or shed it before attempt creation
- `InvocationRequest` is the typed public invoke helper that normalizes stable
  facade fields, uses `connection_id` as the public auth binding, and derives
  the requested capability allowlist by default
- `AuthSpec` is the authored, profile-driven auth contract; it carries
  `supported_profiles`, `default_profile`, connector-level `install` and
  `reauth` posture, connector-wide derived scope/lease/secret posture, and the
  validation rules that keep callback, PKCE, and external-secret semantics
  explicit
- `OperationSpec` and `TriggerSpec` distinguish three layers explicitly:
  - provider inventory in connector-local catalogs
  - runtime-published manifest entries
  - projected common consumer surfaces through `consumer_surface`
- non-direct authored routing stays on the existing contract spine:
  - `runtime.driver`, `runtime.provider`, and `runtime.options` are the
    canonical authored routing keys for `:session` and `:stream` operations
  - the control plane does not synthesize an implicit `asm` default when
    authored `runtime.driver` is missing
  - common `:session` and `:stream` consumer surfaces must also declare
    canonical `metadata.runtime_family`
  - `:connector_local` remains the explicit authored escape hatch when a
    non-direct capability should stay off the generated common surface
  - target descriptors can advertise compatible runtime environments and
    workspace locations, but they must not rewrite authored runtime routing
    keys
- `schema_policy` is explicit on authored operations and triggers so
  placeholder schemas cannot silently leak into published or projected
  surfaces
- `ConsumerProjection` derives deterministic action, sensor, and plugin
  projection rules only from authored entries marked as normalized common
  consumer surfaces, and rejects duplicate projected action names or generated
  sensor collisions within one connector
- common projected triggers must declare deterministic `jido.sensor.name`,
  `jido.sensor.signal_type`, and `jido.sensor.signal_source` metadata, and
  those generated sensor contract names must stay unique within a connector
  while `:connector_local` triggers remain explicit exclusions from the
  generated common sensor surface
- `GeneratedAction`, `GeneratedSensor`, and `GeneratedPlugin` project those
  rules into the current real `Jido.Action`, `Jido.Sensor`, and `Jido.Plugin`
  APIs
- generated actions build typed `InvocationRequest` structs and call the fixed
  `Jido.Integration.V2.invoke/1` facade path rather than honoring a
  caller-supplied invoker module
- `CredentialRef` remains the durable, non-secret handle and now carries
  profile plus current-credential lineage while `CredentialLease` stays the
  short-lived execution boundary
- `Credential` is the versioned durable secret-bearing record and now carries
  `credential_ref_id`, `profile_id`, `version`, source lineage, and optional
  supersession/revocation metadata behind auth APIs
- `CredentialLease` carries only the execution-time payload needed for a
  bounded lease lifetime plus safe lineage such as `credential_id` and
  `profile_id`
- `TargetDescriptor` matches against authored capability ids while remaining a
  compatibility and location advertisement rather than a second override plane
- `TargetDescriptor.extensions["boundary"]` is the authored baseline boundary
  capability advertisement, and `TargetDescriptor.live_boundary_capability/2`
  produces a runtime-merged live capability view when worker-local facts
  sharpen the lower-boundary result
- `TargetDescriptor.authored_requirements/2` turns authored capability truth
  into compatibility requirements so non-direct runtime drivers stay primary
  and target lookups do not drift into ad hoc override logic
- `TriggerRecord` preserves trigger-to-run causation plus rejection truth at
  the control-plane boundary
- `TriggerCheckpoint` keeps polling cursors explicit and durable
- `SubjectRef`, `EvidenceRef`, and `GovernanceRef` are the only intended
  cross-repo reference seam for higher-order repos
- `core/contracts` is the only intended shared dependency seam for higher-order
  repos such as `jido_memory`, `jido_skill`, and `jido_eval`
- durable brain-to-lower-gateway carriage also stays on this seam:
  - `CanonicalJson` defines the lower-gateway-owned canonicalization and hashing basis
    for submission identity
  - `SubmissionIdentity` defines the cross-repo idempotency anchor
  - `AuthorityAuditEnvelope` and `ExecutionGovernanceProjection` keep audit
    payload and operational shadow carriage machine-readable
  - `BrainInvocation` binds those pieces into the durable intake packet
  - `SubmissionAcceptance` and `SubmissionRejection` normalize typed ingress
    results without leaking store implementation details
- provider-factory work in Phase 9 scales on top of that seam instead of
  widening those repos into platform, control-plane, or store-postgres
  dependencies
- `ReviewProjection` is the contracts-only `review_packet/2` metadata shape
  meant for northbound consumers such as `jido_composer`
- `LowerEventPosition`, `ClaimCheckLifecycle`, `InstallationRevisionEpoch`,
  and `LeaseRevocation` are the Phase 4 lower truth integrity contracts. They
  expose append position evidence, claim-check quarantine state, revision/epoch
  fence evidence, and lease revocation propagation without exporting lower
  store internals or raw payloads.
- `RetryPosture` mirrors `Platform.RetryPosture.v1` for lower integration
  consumers so retry, backoff, idempotency scope, safe action, and dead-letter
  refs stay explicit at the lower boundary.
- `AccessGraph.Edge` and `AccessGraph` implement the
  `Platform.AccessGraph.Edge.v1` / graph-only `Platform.AccessGraph.v1`
  contract surface for epoch-stamped authorization, derived views, and
  graph-only recall admissibility. Durable storage lives in
  `core/store_postgres`.
- `MemoryFragment` implements the `Platform.MemoryFragment.V1` envelope for
  immutable source lineage, effective access tuples, content refs, embedding
  metadata, tier-specific policy refs, evidence, governance, and parent
  lineage. Durable tier storage lives in `core/store_postgres`.
- `LowerSubmissionActivity` implements
  `JidoIntegration.LowerSubmissionActivity.v1` for Phase 4 durable workflow
  activity retries. It binds tenant, actor, resource, workflow, activity,
  authority, trace, lower scope, lease evidence, and payload hash while
  declaring the retry idempotency scope as `tenant_ref + submission_dedupe_key`.

## Public Object Notes

## Phase 4 Lower Truth Integrity Contracts

`JidoIntegration.LowerEventPosition.v1`

- stores tenant, installation, workspace, project, environment, actor,
  resource, authority, idempotency, trace, release-manifest, lower-scope,
  stream, event, expected-position, actual-position, dedupe, status, and
  optional conflict evidence
- accepts only `:accepted`, `:duplicate`, or `:conflict` status values
- requires matching expected and actual positions for accepted or duplicate
  evidence
- requires a conflict ref and differing positions for conflict evidence

`JidoIntegration.ClaimCheckLifecycle.v1`

- stores tenant, installation, workspace, project, environment, actor,
  resource, authority, idempotency, trace, release-manifest, claim-check ref,
  payload hash, schema ref, size, retention class, lifecycle state, quarantine
  reason, GC timestamp, and metadata
- accepts only bounded lifecycle states and retention classes
- requires `sha256:<hex>` payload hashes
- requires an explicit quarantine reason when the lifecycle state is
  `:quarantined`

`Platform.InstallationRevisionEpoch.v1`

- mirrors Citadel-owned revision and epoch fence evidence for lower truth
  consumers
- requires tenant, installation, workspace, project, environment, actor,
  resource, authority, idempotency, trace, release-manifest, current
  installation revision, activation epoch, lease epoch, node id, fence decision
  ref, fence status, and stale reason
- accepts only `:accepted` or `:rejected`
- requires `stale_reason: "none"` and no stale attempted values for accepted
  fences
- requires explicit stale attempted revision, activation, or lease epoch
  evidence for rejected fences

`Platform.LeaseRevocation.v1`

- mirrors Citadel-owned lease revocation propagation evidence for lower truth
  consumers
- requires tenant, installation, workspace, project, environment, actor,
  resource, authority, idempotency, trace, release-manifest, lease ref,
  revocation ref, revocation timestamp, non-empty lease scope, cache
  invalidation ref, post-revocation attempt ref, and lease status
- accepts only `:revoked` or `:rejected_after_revocation`

`Platform.RetryPosture.v1`

- mirrors platform retry posture evidence for lower integration consumers
- requires tenant, installation, workspace, project, environment, actor,
  resource, authority, idempotency, trace, release-manifest, operation, owner,
  producer, consumer, retry class, failure class, max attempts, backoff policy,
  idempotency scope, dead-letter ref, and safe action
- accepts only bounded retry classes: `:never`, `:safe_idempotent`,
  `:after_input_change`, `:after_redecision`, or `:manual_operator`
- requires zero attempts for `:never` and at least one attempt for retryable
  classes

## Execution Plane Packet Alignment

The Wave 1 lower-boundary packet now freezes these carried contract names
around this repo:

- `AuthorityDecision.v1`
- `BoundarySessionDescriptor.v1`
- `ExecutionIntentEnvelope.v1`
- `ExecutionRoute.v1`
- `AttachGrant.v1`
- `CredentialHandleRef.v1`
- `ExecutionEvent.v1`
- `ExecutionOutcome.v1`

This package does not replace those lower contracts and it does not flatten
them into one mega-struct. It remains the stable lower-gateway public seam above
that packet.

The family-specific lower intent payload interiors for
`HttpExecutionIntent.v1`, `ProcessExecutionIntent.v1`, and
`JsonRpcExecutionIntent.v1` are explicitly provisional until Wave 3 prove-out.
Wave 1 freezes their names, lineage rules, and ownership semantics only.

`ArtifactRef`

- stores `artifact_id`, `run_id`, `attempt_id`, `artifact_type`,
  `transport_mode`, `checksum`, `size_bytes`, `payload_ref`, `retention_class`,
  and `redaction_status`
- validates the `payload_ref` contract from the artifact transport spec and
  rejects local file paths
- keeps forward-compatible metadata without turning artifacts into inline blobs
  by default

`SubjectRef`, `EvidenceRef`, and `GovernanceRef`

- expose stable `jido://v2/...` reference URIs plus explicit constructors and
  `dump/1` codecs
- keep higher-order repos keyed to source truth instead of copied control-plane
  state
- keep review-packet lineage explicit through `EvidenceRef.packet_ref`
- keep policy approval/denial lineage explicit through `GovernanceRef`
- stay independent of `core/platform`, `core/control_plane`, and
  `core/store_postgres` implementation details

`DerivedStateAttachment`

- packages the canonical higher-order attachment shape over dumped subject,
  evidence, and governance refs
- gives sidecar repos one narrow place to anchor derived state without copying
  run, trigger, auth, or target truth
- is meant to be persisted as dumped refs plus repo-local enrichment, not as a
  second control-plane ledger

`ReviewProjection`

- packages the dumped `review_packet/2` metadata into a contracts-only object
- lets northbound consumers parse `packet.metadata` without taking a
  dependency on `core/platform`
- keeps the review packet a projection over durable source truth instead of a
  second persisted ledger

`TargetDescriptor`

- stores `target_id`, `capability_id`, `runtime_class`, `version`, `features`,
  `constraints`, `health`, and `location`
- keeps unknown fields in `extensions` so mixed-version descriptors remain
  survivable
- reserves `extensions["boundary"]` for the authored baseline boundary
  capability advertisement with `supported`, `boundary_classes`,
  `attach_modes`, and `checkpointing`
- exposes `TargetDescriptor.authored_boundary_capability/1` for the authored
  baseline and `TargetDescriptor.live_boundary_capability/2` for a
  runtime-merged live capability view
- exposes explicit compatibility checks plus runspec and event-schema version
  negotiation
- exposes `authored_requirements/2` so target selection starts from authored
  capability id, runtime class, and non-direct runtime-driver posture instead
  of letting call sites guess

`InvocationRequest`

- stores the stable public invoke fields such as `capability_id`, optional
  `connection_id`, `input`, actor/tenant/environment identity, sandbox posture,
  and optional target selection
- keeps non-reserved extension opts explicit so callers can pass additional
  runtime context without collapsing back to an untyped map wrapper
- exposes `to_opts/1` so `invoke/1` and `invoke/3` can share one normalized
  request shape

`AuthSpec`

## Wave 5 Durable Metadata Vocabulary

When higher repos need boundary-backed session carriage without taking a raw
Execution Plane dependency, this repo now keeps the named metadata groups
explicit:

- `descriptor`
- `route`
- `attach_grant`
- `replay`
- `approval`
- `callback`
- `identity`

`Jido.Integration.V2.Contracts.boundary_metadata_contract_keys/0` publishes
that list for the lower-gateway-owned carrier vocabulary.

- authors connector auth truth through explicit profile records rather than one
  flat auth mode
- derives connector-wide `auth_type`, `management_modes`,
  `requested_scopes`, `durable_secret_fields`, and `lease_fields` from the
  authored profile set when those connector-wide unions are omitted
- normalizes legacy single-profile manifests into one deterministic
  `"default"` profile so older authored connectors can be upgraded without a
  second compatibility struct
- keeps connector install and reauth posture explicit through the top-level
  `install` and `reauth` maps instead of hiding callback or browser-flow rules
  in provider helpers

`OperationSpec` and `TriggerSpec`

- use canonical Zoi-backed struct derivation
- carry explicit `consumer_surface` metadata:
  - `:common` means the entry projects into generated consumer surfaces
  - `:connector_local` means the entry is a stable runtime capability but not a
    generated common surface
- carry explicit `schema_policy` metadata:
  - `:defined` for concrete schemas
  - `:dynamic` for future runtime-resolved schemas
  - `:passthrough` only with an explicit justification, and never for a
    projected common surface
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
- keeps generated consumer surfaces derivative of authored manifest truth
  rather than a second authoring plane
- derives generated action names from normalized surface semantics, not raw
  provider operation ids
- derives generated sensor modules and plugin subscriptions from the same
  authored trigger projection instead of a second trigger-only authored plane
- keeps provider operation ids stable as internal/runtime-facing capability ids
- leaves provider-specific long-tail inventory at the connector or SDK boundary
  instead of auto-projecting it into `Jido.Action` or `Jido.Plugin`

## Inference Contracts

The shared inference contract seam lives here instead of creating a parallel
contracts repo.

The new public objects are:

- `InferenceRequest`
- `InferenceExecutionContext`
- `EndpointDescriptor`
- `BackendManifest`
- `ConsumerManifest`
- `CompatibilityResult`
- `InferenceResult`
- `LeaseRef`

The contract rules are the same as the rest of this package:

- the durable cross-repo form is a JSON-safe map
- `contract_version` is `"inference.v1"`
- `new!/1` validates the authored input
- `dump/1` emits the string-keyed durable map form

`TargetDescriptor` remains the reusable durable target advertisement contract.
`EndpointDescriptor` is the per-attempt execution-ready endpoint summary.

`ReqLLMCallSpec` is intentionally not part of this package. It remains a local
`jido_integration` adapter shape rather than shared durable truth.

## Connector Admission

`Jido.Integration.V2.ConnectorAdmission` is the Phase 4 formal evidence
contract for `Platform.ConnectorAdmission.v1`. It records connector admission
and duplicate-rejection decisions with tenant, installation, workspace, project,
environment, authority, idempotency, trace, release-manifest, connector, pack,
signature, schema, and admission idempotency scope. Duplicate rejections must
carry `duplicate_of_ref`; admitted connectors and signature/schema rejections
must still preserve the same authority and trace scope.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be
installed by adding `jido_integration_contracts` to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_integration_contracts, "~> 0.1.0"}
  ]
end
```

## Related Guides

- [Inference Contracts](guides/inference_contracts.md)
- [Inference Baseline](../../guides/inference_baseline.md)
- [Architecture](../../guides/architecture.md)
- [Runtime Model](../../guides/runtime_model.md)
- [Connector Lifecycle](../../guides/connector_lifecycle.md)
- [Examples](examples/README.md)
