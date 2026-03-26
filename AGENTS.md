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
- `core/runtime_asm_bridge`
- `core/session_runtime`
- `core/store_local`
- `core/store_postgres`

Current connector packages:

- `connectors/github`
- `connectors/notion`
- `connectors/codex_cli`
- `connectors/market_data`

Current app packages:

- `apps/trading_ops`
- `apps/devops_incident_response`

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

The current skeleton proves three runtime families:

- direct
- session
- stream

Natural future slices include:

- additional durable stores
- richer auth lifecycle
- composed policy/gateway rules
- more connectors
- more operator/reference apps above the public platform
