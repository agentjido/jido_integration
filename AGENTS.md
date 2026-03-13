# AGENTS.md

This file defines the working contract for `/home/home/p/g/n/jido_brainstorm/nshkrdotcom/jido_integration_v2`.

## Purpose

`jido_integration_v2` is a thin-root Elixir monorepo for the greenfield integration platform. The root app is intentionally small. Most real code belongs in isolated child packages.

## Repository Shape

The current package layout is:

```text
jido_integration_v2/
  lib/                  # thin root facade + monorepo Mix tasks
  test/                 # root-level integration tests for the monorepo facade
  packages/
    core/               # platform/runtime packages
    connectors/         # connector packages, one package per connector
    apps/               # thin app/reference packages above the public platform
```

Current core packages:

- `packages/core/contracts`
- `packages/core/control_plane`
- `packages/core/auth`
- `packages/core/ingress`
- `packages/core/policy`
- `packages/core/direct_runtime`
- `packages/core/session_kernel`
- `packages/core/store_postgres`
- `packages/core/stream_runtime`

Current connector packages:

- `packages/connectors/github`
- `packages/connectors/codex_cli`
- `packages/connectors/market_data`

Current app packages:

- `packages/apps/trading_ops`

## Operating Rules

- Keep the root app thin. Do not move runtime or connector logic into the root unless it is genuinely monorepo-wide glue.
- Keep package boundaries explicit. If a connector uses a library directly, declare that dependency in the connector package instead of relying on transitive deps.
- Prefer adding new capabilities by adding or extending child packages, not by broadening the root project.
- Treat `contracts` as the shared public model and keep downstream packages honest against it.
- Treat connector packages as isolated deliverables. Each connector should compile, test, lint, type-check, and document cleanly on its own.

## Required Validation Workflow

The root monorepo commands are the canonical quality surface for this repo.

At minimum, future agents should preserve this invariant:

> The repo docs now match the second slice. I’m finishing with the root `mix ci` pass so the new package graph is validated under the same monorepo commands the repo is supposed to expose.

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

## Working Style

- Make changes package-first, then validate from the root.
- When adding a new package, wire it into the root monorepo task surface so it is covered by the same commands as the rest of the repo.
- Keep README/package docs aligned with the current slice. Do not leave architecture or package docs behind the code.
- Prefer TDD/RGR for new vertical slices: add or extend tests first, implement, then run the full root gate.
- Do not silently weaken quality gates to get green CI. Fix package boundaries or dependency shape instead.

## Common Pitfalls

- Do not rely on transitive dependencies between child packages.
- Do not let a connector package depend on unrelated runtime packages “because it works”; keep dependencies minimal and explicit.
- Do not assume root Dialyzer coverage is enough. The monorepo tasks intentionally run quality checks inside each child package as well.
- Do not treat generated docs as proof of correctness unless `mix monorepo.docs` or `mix docs.all` passes cleanly.

## Expected Next Steps

The current skeleton proves three runtime families:

- direct
- session
- stream

Natural future slices include:

- durable stores
- richer auth lifecycle
- composed policy/gateway rules
- more connectors
- more operator/reference apps above the public platform
