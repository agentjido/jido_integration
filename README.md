# Jido Integration

Tooling-root, non-umbrella Elixir monorepo for the greenfield integration
platform.

## Repo Shape

```text
jido_integration/
  mix.exs                    # tooling/workspace root only
  README.md                  # repo architecture + monorepo commands
  AGENTS.md                  # working contract for future agents
  lib/                       # root monorepo tooling only
  test/                      # root tooling tests only
  docs/                      # repo-level docs only
  core/
    platform/               # public facade package (`:jido_integration_v2`)
    contracts/
    control_plane/
    auth/
    ingress/
    policy/
    direct_runtime/
    session_kernel/
    stream_runtime/
    store_postgres/
  connectors/
    github/
    codex_cli/
    market_data/
  apps/
    trading_ops/
```

## Architecture

- the repo root owns monorepo tooling and quality gates only
- `core/platform` owns app `:jido_integration_v2` and module
  `Jido.Integration.V2`
- child projects depend on each other only through explicit `path:` deps
- no child project depends on the repo root
- connectors stay opt-in, so apps compile only the integrations they declare

## Current Slice

Runtime families proved in the repo today:

- `:direct`
  - `github.issue.create`
- `:session`
  - `codex.exec.session`
- `:stream`
  - `market.ticks.pull`

Reference app slice:

- `apps/trading_ops`
  - provisions operator-visible connection state through the public auth API
  - admits a market-alert trigger through `core/ingress`
  - reviews one workflow across market feed pull, analyst session, and operator
    escalation
  - records selected `target_id` values in durable run, attempt, and event
    truth

The connector contract baseline also proves:

- connectors run through auth leases, not durable credential truth
- admitted runs emit connector-specific review events plus canonical
  `artifact.recorded`
- every baseline run persists one durable review artifact reference
- session and stream reuse are keyed to credential ref, not only subject
- runtime sandbox and environment posture stay explicit at the policy boundary

## Dependency Posture

- `core/direct_runtime` and `connectors/github` keep explicit local `jido_action`
  path deps
- `core/ingress` keeps an explicit local `jido_signal` path dep
- `core/platform` does not pull connectors at runtime; connector packages are
  only test deps there
- host apps should still declare explicit deps on any child package whose
  modules they reference directly

## Docs

The connector review baseline notes live in
`docs/connector_review_baseline.md`.

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
