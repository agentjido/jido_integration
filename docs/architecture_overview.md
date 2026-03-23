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
- `core/session_kernel`
- `core/stream_runtime`
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

Connector packages:

- `connectors/github`
- `connectors/notion`
- `connectors/codex_cli`
- `connectors/market_data`
  - publishes the ASM-backed stream operation proof plus the first common
    projected poll trigger proof
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
