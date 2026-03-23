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

Core runtime graph:

- `core/auth`
  - install, connection, credential, and lease truth
- `core/control_plane`
  - connector registry, capability lookup, run truth, event truth, artifact
    truth, trigger truth, and target truth
- `core/policy`
  - pre-attempt allow, deny, and shed decisions
- `core/direct_runtime`
- `core/runtime_asm_bridge`
  - integration-owned projection from the authored
    `/home/home/p/g/n/jido_harness` (`Jido.Harness`) `asm` driver into
    `/home/home/p/g/n/agent_session_manager`
- `core/session_kernel`
- bridge-era residue slated for Phase 6A removal, not part of the target
  runtime architecture
- `core/stream_runtime`
- bridge-era residue slated for Phase 6A removal, not part of the target
  runtime architecture
- `core/dispatch_runtime`
  - async queueing, retry, replay, and transport recovery above the control
    plane
- `core/webhook_router`
  - hosted route lifecycle and ingress bridge above `core/ingress`
- `core/ingress`
  - request normalization and durable trigger admission

Durability tiers:

- in-memory defaults in `core/auth` and `core/control_plane`
- `core/store_local` for restart-safe local durability
- `core/store_postgres` for the shared database-backed tier

## Direct Versus Runtime Boundary

GitHub and Notion stay on the direct provider-SDK path and do not inherit
session or stream runtime-kernel coupling merely because the repo also ships
non-direct capability families.

`Jido.Integration.V2 -> DirectRuntime -> connector -> provider SDK -> pristine`

Only actual `:session` and `:stream` capabilities use
`/home/home/p/g/n/jido_harness` via `Jido.Harness`.

`Jido.Integration.V2 -> HarnessRuntime -> Jido.Harness -> {asm | jido_session}`

`core/session_kernel` and `core/stream_runtime` still exist only as bridge-era
residue slated for Phase 6A removal; they are not part of the target runtime
architecture.

## Runtime Basis Below Non-Direct Capabilities

Only actual session and stream capabilities stay above a provider-neutral
runtime lane:

- `/home/home/p/g/n/jido_harness` exposes `Jido.Harness`, the stable
  runtime-driver contract consumed by `core/control_plane`
- authored `runtime.driver` ids such as `asm` stay on connector capabilities
  and target requirements instead of being inferred from targets or apps
- `core/runtime_asm_bridge` is the integration-owned projection for the `asm`
  driver; it adapts the Harness seam to
  `/home/home/p/g/n/agent_session_manager`
- `/home/home/p/g/n/agent_session_manager` keeps provider-neutral session
  orchestration and lane selection below `jido_integration` ownership
- `/home/home/p/g/n/cli_subprocess_core` remains the subprocess, event, and
  provider-profile foundation below ASM
- `metadata.runtime_family.runtime_ref` names the stable Harness handle shape,
  so a `:stream` capability may honestly publish `:session` when the selected
  driver exposes session-scoped handles

Connector packages:

- `connectors/github`
- `connectors/notion`
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
  they do not take `/home/home/p/g/n/jido_harness`,
  `/home/home/p/g/n/agent_session_manager`,
  `/home/home/p/g/n/cli_subprocess_core`, or `/home/home/p/g/n/jido_session`
  as package dependencies
- session and stream connector packages depend on
  `/home/home/p/g/n/jido_harness` for the shared seam rather than taking
  direct `/home/home/p/g/n/agent_session_manager` or
  `/home/home/p/g/n/cli_subprocess_core` deps

## Public Invocation And Discovery

`Jido.Integration.V2` is the stable public entrypoint.

Discovery surface:

- `connectors/0`
- `capabilities/0`
- `fetch_connector/1`
- `fetch_capability/1`
- `catalog_entries/0`

Auth lifecycle surface:

- `start_install/3`
- `complete_install/2`
- `fetch_install/1`
- `installs/1`
- `connection_status/1`
- `connections/1`
- `request_lease/2`
- `rotate_connection/2`
- `revoke_connection/2`

Invocation surface:

- `InvocationRequest.new!/1`
- `invoke/1`
- `invoke/3`

Public invoke requests use `connection_id` as the consumer-facing auth binding
when the capability requires auth. Anonymous capabilities may omit it.

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
- `targets/1` lists announced durable target descriptors
- `compatible_targets_for/2` derives authored compatibility requirements from
  the durable capability contract instead of forcing apps to restitch that
  logic locally
- `review_packet/2` bundles one run's durable attempts, events, artifacts,
  trigger context, target context, connection/install context, and connector
  catalog context into one reusable operator packet

## Async And Webhook Boundary

The final V2 architecture does not push async transport or hosted webhook logic
back into the root or the public facade.

Instead:

- `core/webhook_router` owns route registration, route lookup, callback
  topology, secret resolution, and ingress-definition assembly
- `core/ingress` owns request normalization and durable trigger admission
- generated common poll-trigger sensors and plugin subscriptions remain
  projections of authored trigger truth, not durable subscription state
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

Root `examples/` and `reference_apps/` are intentionally not part of the V2
layout.
