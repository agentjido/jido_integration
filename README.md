# Jido Integration

Tooling-root, non-umbrella Elixir monorepo for the final V2 integration
platform.

The repo root owns workspace tooling, quality gates, and repo-level guides
only. Runtime code, connector code, and proof surfaces live in child packages
and top-level apps. We do not restore root `examples/` or `reference_apps/`.

## Workspace Model

```text
jido_integration/
  mix.exs                    # tooling/workspace root only
  README.md                  # repo architecture + command index
  AGENTS.md                  # working contract for future agents
  lib/                       # root Mix tasks and workspace helpers only
  test/                      # root tooling tests only
  docs/                      # repo-level architecture and operational guides
  core/
    platform/               # public facade package (`:jido_integration_v2`)
    contracts/              # shared public structs and behaviours
    control_plane/          # connector registry + durable run/trigger truth
    conformance/            # reusable connector conformance engine
    auth/                   # install, connection, credential, and lease truth
    ingress/                # trigger normalization and durable admission
    policy/                 # pre-attempt policy and shed decisions
    direct_runtime/         # direct capability execution
    session_kernel/         # reusable session execution
    stream_runtime/         # reusable stream execution
    store_local/            # restart-safe local durability tier
    store_postgres/         # database-backed durable tier
    dispatch_runtime/       # async queue, retry, replay, recovery
    webhook_router/         # hosted route lifecycle and ingress bridge
  connectors/
    github/                # direct GitHub connector + live acceptance runbook
    notion/                # direct Notion connector + package-local live proofs
    codex_cli/             # session baseline connector
    market_data/           # stream baseline connector
  apps/
    trading_ops/           # cross-runtime operator proof
    devops_incident_response/ # hosted webhook + async recovery proof
```

## Final V2 Surface

- `core/platform` owns the public app identity `:jido_integration_v2` and the
  stable facade module `Jido.Integration.V2`.
- `Jido.Integration.V2` exposes typed invocation, connector discovery, auth
  lifecycle calls, durable review lookups, and target lookup through a single
  public surface.
- `core/conformance` owns reusable connector review logic behind the root
  `mix jido.conformance` task.
- `core/dispatch_runtime` and `core/webhook_router` stay as child packages.
  Hosted async and webhook behavior does not move back into the root or the
  facade package.
- Durability is explicit and package-owned:
  - `core/auth` and `core/control_plane` still ship in-memory defaults.
  - `core/store_local` is the restart-safe local durability tier.
  - `core/store_postgres` is the shared database-backed durable tier.
- Child packages depend on each other only through explicit `path:` deps.
- No child package depends on the repo root.

## Public API Highlights

The stable public entrypoint is `Jido.Integration.V2`.

Key calls:

- connector discovery:
  - `connectors/0`
  - `capabilities/0`
  - `fetch_connector/1`
  - `fetch_capability/1`
- auth lifecycle:
  - `start_install/3`
  - `complete_install/2`
  - `fetch_install/1`
  - `connection_status/1`
  - `request_lease/2`
  - `rotate_connection/2`
  - `revoke_connection/2`
- invocation:
  - `InvocationRequest.new!/1`
  - `invoke/1`
  - `invoke/3`
- durable review truth:
  - `fetch_run/1`
  - `fetch_attempt/1`
  - `events/1`
  - `run_artifacts/1`
  - `fetch_artifact/1`
- target announcement and lookup:
  - `announce_target/1`
  - `fetch_target/1`
  - `compatible_targets/1`

Hosted webhook routing and async replay are intentionally separate public
package APIs:

- `Jido.Integration.V2.DispatchRuntime`
- `Jido.Integration.V2.WebhookRouter`

## Current Proof Surface

Runtime families proved in-tree:

- `:direct`
  - `github.issue.list`
  - `github.issue.fetch`
  - `github.issue.create`
  - `github.issue.update`
  - `github.issue.label`
  - `github.issue.close`
  - `github.comment.create`
  - `github.comment.update`
  - `notion.users.get_self`
  - `notion.search.search`
  - `notion.pages.create`
  - `notion.pages.retrieve`
  - `notion.pages.update`
  - `notion.blocks.list_children`
  - `notion.blocks.append_children`
  - `notion.data_sources.query`
  - `notion.comments.create`
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
- Notion OAuth control flows stay in the auth/install lifecycle instead of the
  normal invoke surface
- `InvocationRequest` is the typed public invoke object
- conformance runs from the root while connector evidence stays package-local
- local durability, async queue state, and webhook route state are all explicit
  opt-in packages

## Guide Index

Repo-level guides in `docs/`:

- [Architecture Overview](docs/architecture_overview.md)
- [Connector Review Baseline](docs/connector_review_baseline.md)
- [Connector Authoring And Scaffolding](docs/connector_scaffolding.md)
- [Connector Conformance Guide](docs/conformance_workflow.md)
- [Local Durability Guide](docs/local_durability.md)
- [Async Dispatch And Replay Guide](docs/async_dispatch_and_replay.md)
- [Webhook Routing Guide](docs/webhook_routing.md)
- [Reference Apps Guide](docs/reference_apps.md)
- [Observability And Pressure Semantics](docs/observability_and_pressure_semantics.md)

Package and app runbooks:

- `core/platform/README.md`
- `core/conformance/README.md`
- `core/store_local/README.md`
- `core/dispatch_runtime/README.md`
- `core/webhook_router/README.md`
- `connectors/github/README.md`
- `connectors/github/docs/live_acceptance.md`
- `connectors/notion/README.md`
- `connectors/notion/docs/live_acceptance.md`
- `apps/trading_ops/README.md`
- `apps/devops_incident_response/README.md`

## Monorepo Commands

Run these from the repo root:

```bash
mix test
mix monorepo.deps.get
mix monorepo.format
mix monorepo.compile
mix monorepo.test
mix monorepo.credo --strict
mix monorepo.dialyzer
mix monorepo.docs
mix quality
mix docs.all
mix ci
mix jido.conformance Jido.Integration.V2.Connectors.GitHub
mix jido.conformance Jido.Integration.V2.Connectors.Notion
mix jido.integration.new acme_crm --runtime-class direct
```

`mix ci` is the main acceptance gate.

## Shortcuts

The root `mix.exs` also defines `mr.*` aliases for the same monorepo task
surface:

```bash
mix mr.deps.get
mix mr.format
mix mr.compile
mix mr.test
mix mr.credo --strict
mix mr.dialyzer
mix mr.docs
```

These are shortcuts for the corresponding `mix monorepo.*` commands above.
