# Architecture Overview

The final V2 repo is a tooling-root monorepo. The root owns only workspace
tooling, repo-level docs, and quality gates. Runtime behavior stays in child
packages.

## Package Graph

Public facade and shared model:

- `core/platform`
  - owns app `:jido_integration_v2`
  - exposes `Jido.Integration.V2`
- `core/contracts`
  - shared public structs and behaviours
- `core/brain_ingress`
  - durable Brain-to-Spine submission intake, scope resolution, and typed
    acceptance or rejection above the runtime path

Core runtime graph:

- `core/auth`
  - profile-driven install, connection, credential, and lease truth behind the
    `connection_id` public auth binding
- `core/control_plane`
  - connector registry, capability lookup, run truth, event truth, artifact
    truth, trigger truth, and target truth
- `core/consumer_surfaces`
  - generated common action, sensor, and plugin runtime support
- `core/policy`
  - pre-attempt allow, deny, and shed decisions
- `core/direct_runtime`
- `core/runtime_asm_bridge`
  - integration-owned projection from the authored
    `jido_harness` (`Jido.Harness`) `asm` driver into
    `agent_session_manager`
- `core/session_runtime`
  - integration-owned home for the authored `jido_session` Harness driver
- `core/dispatch_runtime`
  - async queueing, retry, replay, and transport recovery above the control
    plane
- `core/webhook_router`
  - hosted route lifecycle and ingress bridge above `core/ingress`
- `core/ingress`
  - request normalization and durable trigger admission

Bridge packages:

- `bridges/boundary_bridge`
  - lower-boundary sandbox bridge package that exposes the typed
    `Jido.BoundaryBridge` contract below authored runtime intent and above
    external sandbox kernels such as `jido_os`

Durability tiers:

- in-memory defaults in `core/auth` and `core/control_plane`
- `core/store_local` for restart-safe local durability, including local
  submission-ledger backing
- `core/store_postgres` for the shared database-backed tier, including the
  canonical durable submission ledger

## Direct Versus Runtime Boundary

GitHub, Linear, and Notion stay on the direct provider-SDK path and do not inherit
session or stream runtime-kernel coupling merely because the repo also ships
non-direct capability families.

`Jido.Integration.V2 -> DirectRuntime -> connector -> provider SDK -> pristine`

Only actual `:session` and `:stream` capabilities use
`jido_harness` via `Jido.Harness`.

`Jido.Integration.V2 -> HarnessRuntime -> Jido.Harness -> {asm | jido_session}`

`asm` routes through `core/runtime_asm_bridge` into `agent_session_manager`
and `cli_subprocess_core`, while `jido_session` routes through
`core/session_runtime` via `Jido.Session.HarnessDriver`.

Phase 6A removed the old `core/session_kernel` and `core/stream_runtime`
bridge packages. They are not part of the repo or the target runtime
architecture.

Stage 1 boundary readiness keeps both runtime lanes on this same seam.
`TargetDescriptor.extensions["boundary"]` is the authored baseline boundary
capability advertisement, and runtime code may build a runtime-merged live
capability view when worker-local facts sharpen the lower-boundary result for
boundary-backed `asm` or boundary-backed `jido_session`.

Cross-repo Brain handoff also enters on an explicit seam:

`Brain -> core/brain_ingress -> Gateway/runtime inputs -> {policy | runtime}`

`core/brain_ingress` verifies Spine-owned governance projections, resolves
logical file-scope references before `Gateway.new!/1`, and records durable
submission acceptance or typed rejection through the selected store package.

## Runtime Basis Below Non-Direct Capabilities

Only actual session and stream capabilities stay above a provider-neutral
runtime lane:

- `jido_harness` exposes `Jido.Harness`, the stable
  runtime-driver contract consumed by `core/control_plane`
- authored `runtime.driver` ids such as `asm` stay on connector capabilities
  and target requirements instead of being inferred from targets or apps
- `core/runtime_asm_bridge` is the integration-owned projection for the `asm`
  driver; it adapts the Harness seam to
  `agent_session_manager`
- `bridges/boundary_bridge` is the lower-boundary package reserved for sandbox
  bridge code, typed bridge IO, and descriptor normalization that do not belong
  in `core/` and are not an app-level proof
- `core/session_runtime` is the integration-owned home for `jido_session` via
  `Jido.Session.HarnessDriver`; `jido_integration` still consumes it through
  authored `runtime.driver` metadata rather than a local compatibility shim
- `agent_session_manager` keeps provider-neutral session
  orchestration and lane selection below `jido_integration` ownership
- `cli_subprocess_core` remains the subprocess, event, and
  provider-profile foundation below ASM
- `metadata.runtime_family.runtime_ref` names the stable Harness handle shape,
  so a `:stream` capability may honestly publish `:session` when the selected
  driver exposes session-scoped handles

Connector packages:

- `connectors/github`
- `connectors/linear`
  - publishes a curated generated common action/plugin slice backed by
    `linear_sdk`
- `connectors/notion`
  - publishes a curated generated common action/plugin slice plus one common
    poll-trigger sensor slice backed by `notion_sdk`
- `connectors/codex_cli`
- `connectors/market_data`
  - publishes the Harness-routed stream operation proof through the authored
    `asm` driver plus the first common projected poll trigger proof
  - projects one generated `Jido.Sensor` and plugin subscription surface from
    authored trigger truth

Proof apps:

- `apps/trading_ops`
- `apps/devops_incident_response`

## Dependency Rules

- the repo root stays tooling-only
- child packages depend on each other only through explicit `path:` deps
- no child package depends on the repo root
- `core/platform` does not pull connectors at runtime; connector packages are
  test-only deps there
- apps declare every child package whose modules they reference directly
- direct connector packages depend on `core/direct_runtime` plus provider SDKs;
  they do not take `jido_harness`, `agent_session_manager`,
  `cli_subprocess_core`, or `core/session_runtime`
  as package dependencies
- session and stream connector packages depend on
  `jido_harness` for the shared seam rather than taking direct
  `core/session_runtime`, `agent_session_manager`, or
  `cli_subprocess_core` deps

## Public Invocation And Discovery

`Jido.Integration.V2` is the stable public entrypoint.

Discovery surface:

- `connectors/0`
- `capabilities/0`
- `fetch_connector/1`
- `fetch_capability/1`
- `catalog_entries/0`
- `projected_catalog_entries/0`

Auth lifecycle surface:

- `start_install/3`
- `resolve_install_callback/1`
- `complete_install/2`
- `fetch_install/1`
- `installs/1`
- `cancel_install/2`
- `expire_install/2`
- `connection_status/1`
- `connections/1`
- `reauthorize_connection/2`
- `request_lease/2`
- `rotate_connection/2`
- `revoke_connection/2`

Invocation surface:

- `InvocationRequest.new!/1`
- `invoke/1`
- `invoke/3`

Public invoke requests use `connection_id` as the consumer-facing auth binding
when the capability requires auth. Anonymous capabilities may omit it.
Authenticated invoke and retry paths always re-resolve current durable auth
truth before issuing a short-lived execution lease.

That lifecycle is now profile-driven from authored connector manifests:

- connectors publish `supported_profiles`, `default_profile`, connector-level
  `install`/`reauth` posture, and per-profile scope, lease, and management
  rules through `AuthSpec`
- durable auth records keep `profile_id`, credential lineage, and
  secret-source posture behind `core/auth` and the selected durability tier
- runtime execution still receives only short-lived leases, never durable
  credential truth
- connector conformance also checks curated common-surface uniqueness and
  review-safe lease redaction so generated publication remains derivative and
  safe to expose

Hosted browser/provider callbacks, install cancellation, install expiration,
and reauth are auth-control flows, not connector invoke capabilities. Apps may
own the HTTP endpoint that receives those callback params, but the durable
correlation, callback validation, and connection/install state transitions stay
inside `core/auth` rather than `core/ingress` or `core/control_plane`.

Durable review surface:

- `fetch_run/1`
- `fetch_attempt/1`
- `events/1`
- `run_artifacts/1`
- `fetch_artifact/1`
- `announce_target/1`
- `fetch_target/1`
- `targets/1`
- `compatible_targets/1`
- `compatible_targets_for/2`
- `review_packet/2`

The shared operator surface is intentionally read-only. It packages durable
truth that already lives in `core/auth` and `core/control_plane`:

- `installs/1` and `connections/1` list durable auth state without copying it
- `catalog_entries/0` summarizes authored connector and capability catalog
  truth for downstream consumers
- `projected_catalog_entries/0` exports the published common generated
  action/plugin/sensor surface with JSON Schema derived from the authored Zoi
  contracts
- `targets/1` lists announced durable target descriptors
- `compatible_targets_for/2` derives authored compatibility requirements from
  the durable capability contract instead of forcing apps to restitch that
  logic locally
- `review_packet/2` bundles one run's durable attempts, events, artifacts,
  trigger context, target context, connection/install context, and connector
  catalog context into one reusable operator packet
- planning, review, and sandbox execution stay secret-decoupled; operator
  packets and replay surfaces expose durable lineage and redacted execution
  truth, not raw secret material
- auth install callback, state, PKCE, and redirect material stay on the
  auth-control surface; `review_packet/2` only exposes a review-safe redacted
  install projection
- `review_packet/2` now keeps packet metadata explicit:
  - `ReviewProjection` is the contracts-only metadata object for northbound
    consumers
  - `SubjectRef` names the primary run subject
  - `EvidenceRef` entries point at durable run, attempt, event, artifact,
    trigger, target, connection, and install truth
  - `GovernanceRef` entries point at durable policy-lineage events when they
    exist
  - packet metadata stays a projection over source facts rather than becoming
    a separate persisted review record family
  - higher-order repos such as `jido_composer` should consume that metadata
    through `core/contracts` and keep their own state orchestration-local

Phase 8 also freezes the higher-order seam: higher-order sidecars such as
`jido_memory`, `jido_skill`, and `jido_eval` stay on the `core/contracts` seam
and may persist only derived state.

Phase 9 provider-factory work builds on that already-correct ownership split
instead of reopening control-plane, catalog, or review authority in those
repos.

## Async And Webhook Boundary

The final V2 architecture does not push async transport or hosted webhook logic
back into the root or the public facade.

Instead:

- `core/webhook_router` owns route registration, route lookup, callback
  topology, secret resolution, and ingress-definition assembly
- `core/ingress` owns request normalization and durable trigger admission
- generated common poll-trigger sensors and plugin subscriptions remain
  projections of authored trigger truth, not durable subscription state
- app-owned hosted webhook triggers can converge on the same generated sensor
  contract layer without moving route ownership or ingress ownership out of the
  app package
- `core/dispatch_runtime` owns queueing, retry, dead-letter, replay, and
  recovery once work is admitted
- app packages own host-controlled trigger handlers and any end-to-end proofs

## Proof Surface

Proofs live where the behavior belongs:

- package-local READMEs and docs for package-specific workflows
- package-local examples and scripts for connector-local proofs
- top-level `apps/*` for host-level reference workflows

The current app proofs are:

- `apps/trading_ops`
  - cross-runtime operator workflow
  - consumption of the connector-authored `market.alert.detected` poll trigger
    before the explicit downstream `market.ticks.pull` invocation
  - workflow-local shaping over the shared `Jido.Integration.V2.review_packet/2`
    operator packet
- `apps/devops_incident_response`
  - hosted webhook to async replay and restart recovery
  - app-owned webhook trigger publication through the same generated
    sensor-facing contract family used by common poll triggers

Root `examples/` and `reference_apps/` are intentionally not part of the V2
layout.
