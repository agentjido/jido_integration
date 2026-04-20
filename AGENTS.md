# Monorepo Project Map

- `./apps/devops_incident_response/mix.exs`: Async webhook proof app above the greenfield platform
- `./apps/inference_ops/mix.exs`: Reference proof app for cloud and self-hosted inference execution
- `./apps/trading_ops/mix.exs`: Reference operator app slice above the greenfield platform
- `./connectors/codex_cli/mix.exs`: Example session connector package for the greenfield platform
- `./connectors/github/mix.exs`: Thin direct GitHub connector package backed by github_ex
- `./connectors/linear/mix.exs`: Thin direct Linear connector package backed by linear_sdk
- `./connectors/market_data/mix.exs`: Example stream connector package using the authored Runtime Control `asm` driver
- `./connectors/notion/mix.exs`: Thin direct Notion connector package backed by notion_sdk
- `./core/asm_runtime_bridge/mix.exs`: Integration-owned `asm` adapter into the shared runtime-control seam
- `./core/auth/mix.exs`: Credential storage and resolution for the greenfield platform
- `./core/brain_ingress/mix.exs`: Durable brain-to-lower-gateway submission intake and scope resolution
- `./core/conformance/mix.exs`: Reusable v2-native connector conformance engine and report surface
- `./core/consumer_surfaces/mix.exs`: Runtime support for generated Jido-native consumer surfaces
- `./core/contracts/mix.exs`: Greenfield public contracts for runs, attempts, capabilities, and credentials
- `./core/control_plane/mix.exs`: Capability registry and run ledger for the greenfield platform
- `./core/direct_runtime/mix.exs`: Direct execution runtime for stateless and request/response capabilities
- `./core/dispatch_runtime/mix.exs`: Async trigger dispatch runtime with retry, replay, and recovery
- `./core/ingress/mix.exs`: Webhook and polling trigger admission for the greenfield platform
- `./core/platform/mix.exs`: Public facade package for the Jido Integration platform
- `./core/policy/mix.exs`: Admission policy evaluation for capabilities
- `./core/runtime_control/mix.exs`: Shared runtime-control facade, IR, and driver contract layer
- `./core/runtime_router/mix.exs`: Integration-owned router for session and stream runtime lanes
- `./core/session_runtime/mix.exs`: Integration-owned internal `jido_session` runtime-control runtime
- `./core/store_local/mix.exs`: Restart-safe local durability adapters for auth and control-plane truth
- `./core/store_postgres/mix.exs`: Postgres durability package owning Repo, migrations, and sandbox posture
- `./core/webhook_router/mix.exs`: Hosted webhook route registration and dispatch bridging above ingress
- `./mix.exs`: Tooling root for the Jido Integration non-umbrella monorepo

# AGENTS.md

This file defines the working contract for `/home/home/p/g/n/jido_integration`.

## Purpose

`jido_integration` is a tooling-root Elixir monorepo for the greenfield
integration platform. The repo root owns workspace tooling only. Runtime code
belongs in isolated child packages.

## Repository Shape

The current package layout is:

```text
jido_integration/
  lib/                  # monorepo Mix tasks and workspace helpers only
  test/                 # root tooling tests only
  docs/                 # repo-level docs only
  core/                 # platform/runtime packages
  connectors/           # connector packages, one package per connector
  apps/                 # thin app/reference packages above the public platform
```

Current core packages:

- `core/platform`
- `core/brain_ingress`
- `core/conformance`
- `core/consumer_surfaces`
- `core/contracts`
- `core/control_plane`
- `core/dispatch_runtime`
- `core/webhook_router`
- `core/auth`
- `core/ingress`
- `core/policy`
- `core/direct_runtime`
- `core/asm_runtime_bridge`
- `core/session_runtime`
- `core/store_local`
- `core/store_postgres`

Current connector packages:

- `connectors/github`
- `connectors/linear`
- `connectors/notion`
- `connectors/codex_cli`
- `connectors/market_data`

Current app packages:

- `apps/devops_incident_response`
- `apps/inference_ops`

Archived proof packages kept off the default workspace/CI lane:

- `apps/trading_ops`

## Documentation Homes

Keep documentation aligned to the permanent V2 layout:

- repo-level architecture and operational guides belong in `docs/`
- package-specific workflows belong in package-local `README.md` files and
  package-local docs folders when needed
- host-level proof runbooks belong in `apps/*/README.md`
- proof code belongs in child packages or top-level apps, not in root
  `examples/` or `reference_apps/`

## Operating Rules

- Keep the repo root tooling-only. Do not move runtime or connector logic into
  the root unless it is genuinely monorepo-wide glue.
- Keep package boundaries explicit. If a connector uses a library directly, declare that dependency in the connector package instead of relying on transitive deps.
- Prefer adding new capabilities by adding or extending child packages, not by broadening the root project.
- Treat `contracts` as the shared public model and keep downstream packages honest against it.
- Treat `core/brain_ingress` as the durable brain-to-lower-gateway intake seam. Scope
  resolution, submission acceptance, and typed rejection normalization belong
  there rather than in the workspace root or connector packages.
- Treat `platform` as the public facade package. The root workspace must not
  reclaim app identity `:jido_integration_v2`.
- Treat connector packages as isolated deliverables. Each connector should compile, test, lint, type-check, and document cleanly on its own.
- Use the root `mix jido.integration.new` scaffold for new connector packages
  so they start with explicit child-package deps, runtime-fit handlers, and
  package-local conformance coverage.
- Keep webhook and async proof surfaces where they belong:
  - connector-local when the behavior is part of the connector contract
  - app-local when the behavior depends on hosted routing, dispatch handlers, or
    package composition above the connector
- Do not recreate the old root `examples/` or `reference_apps/` layout.

## Required Validation Workflow

The root monorepo commands are the canonical quality surface for this repo.

At minimum, future agents should preserve this invariant:

> The repo docs now match the tooling-root workspace slice. I’m finishing with
> the root `mix ci` pass so the package graph is validated under the same
> monorepo commands the repo is supposed to expose.

Run these from the repo root:

```bash
mix monorepo.format
mix monorepo.compile
mix monorepo.test
mix monorepo.credo --strict
mix monorepo.dialyzer
mix monorepo.docs
mix ci
```

`mix ci` is the main acceptance gate. If it fails, the repo is not done.

For connector-facing slices, also run the root conformance task against every
affected connector module, for example:

```bash
mix jido.conformance Jido.Integration.V2.Connectors.GitHub
mix jido.conformance Jido.Integration.V2.Connectors.Linear
```

The root `mix.exs` also exposes equivalent `mr.*` shortcuts for day-to-day
use:

```bash
mix mr.deps.get
mix mr.format
mix mr.compile
mix mr.test
mix mr.credo --strict
mix mr.dialyzer
mix mr.docs
```

Package-local live proofs remain opt-in. They should never be required for the
default root acceptance gate.

## Working Style

- Make changes package-first, then validate from the root.
- When adding a new package, wire it into the root monorepo task surface so it is covered by the same commands as the rest of the repo.
- When changing connector review semantics, keep `core/conformance`, the root
  `mix jido.conformance` task, and connector companion evidence modules aligned.
- When adding a new connector package, prefer generating it from
  `mix jido.integration.new <connector_name>` and then editing the emitted
  package in place instead of hand-rolling a new child project.
- Keep README/package docs aligned with the current slice. Do not leave architecture or package docs behind the code.
- Keep repo guide text aligned with the actual package graph and proof surfaces.
- When documenting workflows, point to package-local or app-level proofs rather
  than inventing new root-level examples.
- Prefer TDD/RGR for new vertical slices: add or extend tests first, implement, then run the full root gate.
- Do not silently weaken quality gates to get green CI. Fix package boundaries or dependency shape instead.

## Common Pitfalls

- Do not rely on transitive dependencies between child packages.
- Do not let a connector or app depend on the repo root; keep dependencies
  minimal and explicit.
- Do not let a connector package depend on unrelated runtime packages “because
  it works”; keep dependencies minimal and explicit.
- Do not assume root Dialyzer coverage is enough. The monorepo tasks intentionally run quality checks inside each child package as well.
- Do not treat generated docs as proof of correctness unless `mix monorepo.docs` or `mix docs.all` passes cleanly.
- Do not let V1-only layout language drift back into repo docs or package docs.

## Expected Next Steps

The current skeleton proves four runtime families:

- direct
- session
- stream
- inference

Natural future slices include:

- additional durable stores
- richer auth lifecycle
- composed policy/gateway rules
- live CLI-published inference endpoints
- additional self-hosted inference backends
- more connectors
- more operator/reference apps above the public platform

## Temporal developer environment

Temporal CLI is implicitly available on this workstation as `temporal` for local durable-workflow development. Do not make repo code silently depend on that implicit machine state; prefer explicit scripts, documented versions, and README-tracked ergonomics work.

## Native Temporal development substrate

When Temporal runtime behavior is required, use the stack substrate in `/home/home/p/g/n/mezzanine`:

```bash
just dev-up
just dev-status
just dev-logs
just temporal-ui
```

Do not invent raw `temporal server start-dev` commands for normal work. Do not reset local Temporal state unless the user explicitly approves `just temporal-reset-confirm`.
