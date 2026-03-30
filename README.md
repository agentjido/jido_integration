# Jido Integration

Jido Integration is an Elixir integration platform for publishing connector
capabilities, managing auth lifecycle, invoking work across direct and
Harness-backed runtimes, and reviewing durable execution state.

This repository includes the public platform facade, bridge packages,
connector packages, durability tiers, and app-level proofs for hosted webhook
and async flows. If you are evaluating or using the platform, start here. If
you are changing the internals of the monorepo itself, use the developer
guides linked below.

Connector packages that depend on external SDK or runtime repos should prefer
sibling-relative paths during active local development and fall back to pinned
git refs otherwise. They should not rely on connector-local vendored `deps/`
trees for runtime dependency sourcing.

## Start Here

- read [Architecture](guides/architecture.md) for the platform shape and
  package responsibilities
- read [Runtime Model](guides/runtime_model.md) to choose between direct,
  session, and stream execution
- read [Durability](guides/durability.md) before selecting in-memory,
  local-file, or Postgres-backed state
- read [Publishing](guides/publishing.md) for the welded package release flow
- read [Reference Apps](guides/reference_apps.md) for end-to-end proof
  surfaces
- read [Developer Index](guides/developer/index.md) only if you are working on
  repo internals

## Documentation

### General

- [Guide Index](guides/index.md)
- [Architecture](guides/architecture.md)
- [Runtime Model](guides/runtime_model.md)
- [Durability](guides/durability.md)
- [Connector Lifecycle](guides/connector_lifecycle.md)
- [Conformance](guides/conformance.md)
- [Async And Webhooks](guides/async_and_webhooks.md)
- [Publishing](guides/publishing.md)
- [Reference Apps](guides/reference_apps.md)
- [Observability](guides/observability.md)

### Developer

- [Developer Index](guides/developer/index.md)

## What The Platform Exposes

- `Jido.Integration.V2` is the stable public entrypoint for connector
  discovery, auth lifecycle calls, invocation, review lookups, and target
  lookup.
- connector packages publish authored capability contracts and may also expose
  curated generated `Jido.Action`, `Jido.Sensor`, and `Jido.Plugin` surfaces.
- `core/dispatch_runtime` and `core/webhook_router` provide the hosted async
  and webhook APIs above the main facade.

Key public capabilities today include:

- connector discovery through `connectors/0`, `capabilities/0`,
  `fetch_connector/1`, `fetch_capability/1`, and
  `projected_catalog_entries/0`
- auth lifecycle through `start_install/3`, `complete_install/2`,
  `fetch_install/1`, `connection_status/1`, `request_lease/2`,
  `rotate_connection/2`, and `revoke_connection/2`
- invocation through `InvocationRequest.new!/1`, `invoke/1`, and `invoke/3`
- review and targeting through `fetch_run/1`, `fetch_attempt/1`, `events/1`,
  `run_artifacts/1`, `fetch_artifact/1`, `announce_target/1`, `fetch_target/1`,
  and `compatible_targets/1`

Hosted webhook routing and async replay are intentionally separate public
package APIs:

- `Jido.Integration.V2.DispatchRuntime`
- `Jido.Integration.V2.WebhookRouter`

## Current Proof Surface

Runtime families proved in-tree:

- `:direct`
  - GitHub issue and comment operations
  - Notion user, search, page, block, data-source, and comment operations
- `:session`
  - `codex.exec.session`
- `:stream`
  - `market.ticks.pull`

Reference apps:

- `apps/trading_ops`
  - proves one operator-visible workflow across stream, session, and direct
    runtimes
  - keeps trigger admission in `core/ingress`
  - keeps durable review truth in `core/control_plane`
- `apps/devops_incident_response`
  - proves hosted webhook registration, async dispatch, dead-letter, replay,
    and restart recovery
  - keeps webhook behavior app-local instead of widening `connectors/github`

The current surface also proves:

- connectors execute through short-lived auth leases, not durable credential
  truth
- public invocation binds auth through `connection_id`; `credential_ref`
  remains internal execution plumbing
- GitHub and Notion both publish generated common consumer surfaces from
  authored contracts
- conformance runs from the root while connector evidence stays package-local
- local durability, async queue state, and webhook route state are all
  explicit opt-in packages

## Publishing The Unified Package

The source monorepo remains the system of record. The publishable Hex package
is generated from this repo through `weld`.

The release path is explicit:

1. `mix release.prepare`
2. `mix release.publish.dry_run`
3. `mix release.publish`
4. `mix release.archive`

`mix release.prepare` generates the welded package, runs the artifact quality
lane, builds the tarball, and writes a durable release bundle under `dist/`.

`mix release.publish` publishes from that prepared bundle snapshot rather than
from the monorepo root. `mix release.archive` then preserves the prepared
bundle in the archive tree so the exact released artifact remains inspectable.

The first published welded artifact intentionally ships the direct-runtime,
webhook, async, durability, auth, and public-facade surface. The Harness-backed
session and stream packages, plus lower-boundary bridge packages, stay
source-repo packages until their external runtime dependencies become
independently publishable.

## Repository Layout

The repo root is a workspace and documentation layer. Runtime code lives in
child packages and top-level apps.

```text
jido_integration/
  mix.exs                    # workspace root only
  README.md                  # user-facing repo entry point
  guides/                    # user-facing and developer guide entry points
  docs/                      # repo-level developer notes and workflows
  lib/                       # root Mix tasks and workspace helpers only
  test/                      # root tooling tests only
  core/
    platform/                # public facade package (`:jido_integration_v2`)
    contracts/               # shared public structs and behaviours
    auth/                    # install, connection, credential, and lease truth
    control_plane/           # durable run, trigger, and artifact truth
    harness_runtime/         # Harness-backed session/stream adapter package
    consumer_surfaces/       # generated common Jido surface runtime support
    direct_runtime/          # direct capability execution
    runtime_asm_bridge/      # integration-owned `asm` Harness driver projection
    session_runtime/         # integration-owned `jido_session` Harness driver
    ingress/                 # trigger normalization and durable admission
    policy/                  # pre-attempt policy and shed decisions
    dispatch_runtime/        # async queue, retry, replay, recovery
    webhook_router/          # hosted route lifecycle and ingress bridge
    conformance/             # reusable connector conformance engine
    store_local/             # restart-safe local durability tier
    store_postgres/          # database-backed durable tier
  bridges/
    boundary_bridge/         # lower-boundary sandbox bridge package
  connectors/
    github/                  # direct GitHub connector + live acceptance runbook
    notion/                  # direct Notion connector + package-local live proofs
    codex_cli/               # Harness-routed session connector via `asm`
    market_data/             # Harness-routed stream connector via `asm`
  apps/
    trading_ops/             # cross-runtime operator proof
    devops_incident_response # hosted webhook + async recovery proof
```

## Direct Versus Runtime Boundary

GitHub and Notion stay on the direct provider-SDK path and do not inherit
session or stream runtime-kernel coupling merely because the repo also ships
non-direct capability families.

`Jido.Integration.V2 -> DirectRuntime -> connector -> provider SDK -> pristine`

Only actual `:session` and `:stream` capabilities use
`/home/home/p/g/n/jido_harness` via `Jido.Harness`.

`Jido.Integration.V2 -> HarnessRuntime -> Jido.Harness -> {asm | jido_session}`

`asm` routes through `core/runtime_asm_bridge` into `/home/home/p/g/n/agent_session_manager`
and `/home/home/p/g/n/cli_subprocess_core`, while `jido_session` routes
through `core/session_runtime` via `Jido.Session.HarnessDriver`.

Phase 6A removed the old `core/session_kernel` and `core/stream_runtime`
bridge packages. They are not part of the repo or the target runtime
architecture.

## Developer Docs

User-facing guides live under `guides/`. Developer-focused repo notes remain in
`docs/`, and package-specific workflows remain in package-local READMEs.

Primary package and app runbooks:

- `core/platform/README.md`
- `core/consumer_surfaces/README.md`
- `core/conformance/README.md`
- `core/session_runtime/README.md`
- `core/store_local/README.md`
- `core/dispatch_runtime/README.md`
- `core/webhook_router/README.md`
- `bridges/boundary_bridge/README.md`
- `connectors/github/README.md`
- `connectors/github/docs/live_acceptance.md`
- `connectors/notion/README.md`
- `connectors/notion/docs/live_acceptance.md`
- `apps/trading_ops/README.md`
- `apps/devops_incident_response/README.md`

## Validation Prerequisites

The monorepo test and CI surface now includes packages that wire
`core/store_postgres` in `:test`.

`mix mr.test` and `mix ci` therefore expect a reachable Postgres test store.
Before calling the repo blocked on Postgres reachability, run:

```bash
mix mr.pg.preflight
```

That check validates the canonical `core/store_postgres` test tier only. The
repo still supports the other two durability tiers in parallel:

- in-memory defaults in `core/auth` and `core/control_plane`
- `core/store_local` for restart-safe local durability
- `core/store_postgres` for the shared database-backed tier
