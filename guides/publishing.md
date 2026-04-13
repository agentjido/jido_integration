# Publishing

`jido_integration` now treats publication as a welded artifact workflow, not as
an ad hoc branch rewrite.

## Release Shape

The source-of-truth stays in the monorepo. Publishing happens from a prepared
release bundle generated from `build_support/weld.exs`.

`build_support/weld.exs` is intentionally thin and delegates the actual
publication contract to `build_support/weld_contract.exs`, where the published
roots, source-only exclusions, and source-only monolith test support projects
are declared together.

The default published artifact intentionally excludes the runtime-control-backed
session and stream runtime slice for now:

- `core/runtime_router`
- `core/asm_runtime_bridge`
- `core/session_runtime`
- `bridges/boundary_bridge`
- `connectors/codex_cli`
- `connectors/market_data`

Those packages remain source-only by explicit monorepo publication policy. They
still participate in the source workspace and monolith test lane, but they are
not part of the published unified artifact.

The monolith test lane is allowed to use source-only support from that excluded
slice, but the allowed support set is now explicit in the Weld manifest through
`monolith_opts[:test_support_projects]`.

The release lifecycle is:

1. `mix release.prepare`
2. `mix release.track`
3. `mix release.publish.dry_run`
4. `mix release.publish`
5. `mix release.archive`

`mix release.prepare` runs the welded-artifact verification lane, builds the
exact package tarball, and writes the release bundle under `dist/`.
The prepared project inside that bundle remains a real runnable Mix project, so
dist validation can continue there with the normal package gates:
`mix format --check-formatted`, `mix compile --warnings-as-errors`,
`mix test`, `mix credo --strict`, `mix dialyzer`,
`mix docs --warnings-as-errors`, plus `mix ecto.create` and
`mix ecto.migrate` when the published slice includes database-backed
packages.

`mix release.track` updates the default orphan-backed
`projection/jido_integration` branch from the prepared bundle. That is the
durable generated-source surface for unreleased and pre-release welded
artifacts, and it gives downstream repos a real Git ref to pin before a Hex
release exists.

While implementing or debugging this release flow locally, point the repo at a
sibling Weld checkout with `WELD_PATH=../weld`. For shared pre-release
validation, use `WELD_GIT_REF=<commit_sha>` and optionally
`WELD_GIT_URL=<repo_url>`. The committed steady state should return to the
released Hex dependency line after the release is live.

`mix release.publish` then runs `mix hex.publish` from the prepared bundle
snapshot, not from the source repo root. That keeps the published artifact tied
to an inspectable, durable snapshot.

`mix release.archive` copies the prepared bundle into the archive tree so the
published release remains reviewable after the immediate publish step.

## What Gets Tested

There are two verification lanes:

- the source monorepo still runs `mix ci` and the package-local quality lanes
- the welded package runs its own `mix deps.get`, `mix compile --warnings-as-errors`,
  `mix test`, `mix docs --warnings-as-errors`, `mix hex.build`,
  `mix hex.publish --dry-run --yes`, and the smoke app

The welded package test surface lives under
`packaging/weld/jido_integration/test/`. Those tests are package-owned checks
for the unified public artifact, not a blind copy of every child package's
tests.

## Operational Commands

- `mix weld.inspect`
- `mix weld.graph`
- `mix weld.project`
- `mix weld.verify`
- `mix weld.release.prepare`
- `mix weld.release.track`
- `mix weld.release.archive`
- `mix release.prepare`
- `mix release.track`
- `mix release.publish.dry_run`
- `mix release.publish`
- `mix release.archive`

Use the `weld.*` commands when you want the raw projector tooling. Use the
`release.*` commands when you are operating the actual Hex release flow for the
published package.
