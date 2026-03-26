# State And Verification

This guide covers the local state model and the commands contributors should
use to verify changes.

## State Model

- `core/auth` and `core/control_plane` default to in-memory truth
- `core/store_local` is the restart-safe local file-backed tier
- `core/store_postgres` is the canonical shared durable tier
- `core/dispatch_runtime` persists async transport state separately from the
  control plane
- `core/webhook_router` persists route state separately from trigger admission

## Development Choices

- use in-memory defaults when the process lifetime is enough
- use `store_local` when you need restart recovery without Postgres
- use `store_postgres` when you want the canonical durable behavior and SQL
  testing path

## Verification Ladder

1. package-level `mix test`
2. package-level `mix docs`
3. root `mix jido.conformance <ConnectorModule>` for connector packages
4. root `mix mr.pg.preflight` when the test surface needs Postgres
5. root `mix monorepo.format`
6. root `mix monorepo.compile`
7. root `mix monorepo.credo --strict`
8. root `mix monorepo.dialyzer`
9. root `mix monorepo.docs`
10. root `mix monorepo.test`
11. root `mix ci`

## What To Check First

- if a change touches public contracts, update `core/contracts` and re-run the
  relevant docs
- if a change touches state ownership, check the owning package README first
- if a change touches runtime behavior, verify the request lifecycle through
  the relevant package and app proof

## Anti-Pattern

Do not make the root the hidden owner of state or verification rules. The root
should coordinate the workspace, not replace the package that actually owns the
behavior.
