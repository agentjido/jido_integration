# Local Durability Guide

V2 keeps durability explicit. There are three current tiers:

- in-memory defaults in `core/auth` and `core/control_plane`
- `core/store_local` for restart-safe single-node durability
- `core/store_postgres` for the shared database-backed tier

## When To Use Each Tier

Use the in-memory defaults when:

- process lifetime is enough
- restart recovery is not required
- you want the lightest local setup

Use `core/store_local` when:

- you need restart-safe auth and control-plane truth
- you are running local proofs or app tests without provisioning Postgres
- a single-node file-backed store is enough

Use `core/store_postgres` when:

- the environment needs the canonical shared durable tier
- you need migrations, SQL sandbox helpers, or stronger operational posture
- multiple writers or shared environments matter

## Wiring `core/store_local`

Add it as an explicit dependency from the package or app that wants local
durability, then point `auth` and `control_plane` at the local adapters.

Configuration:

```elixir
config :jido_integration_v2_store_local,
  storage_dir: System.get_env("JIDO_INTEGRATION_LOCAL_STORE_DIR", ".jido/store_local")

config :jido_integration_v2_auth,
  credential_store: Jido.Integration.V2.StoreLocal.CredentialStore,
  lease_store: Jido.Integration.V2.StoreLocal.LeaseStore,
  connection_store: Jido.Integration.V2.StoreLocal.ConnectionStore,
  install_store: Jido.Integration.V2.StoreLocal.InstallStore

config :jido_integration_v2_control_plane,
  run_store: Jido.Integration.V2.StoreLocal.RunStore,
  attempt_store: Jido.Integration.V2.StoreLocal.AttemptStore,
  event_store: Jido.Integration.V2.StoreLocal.EventStore,
  artifact_store: Jido.Integration.V2.StoreLocal.ArtifactStore,
  ingress_store: Jido.Integration.V2.StoreLocal.IngressStore,
  target_store: Jido.Integration.V2.StoreLocal.TargetStore
```

For tests and scripts, `Jido.Integration.V2.StoreLocal.configure_defaults!/1`
can set the same application environment programmatically.

## What `store_local` Does And Does Not Own

`core/store_local` owns restart-safe auth and control-plane truth.

It does not own:

- dispatch-runtime transport files
- webhook-router route files

Those packages keep their own storage directories and should be configured
alongside `store_local` when you need full local restart recovery for the
hosted webhook path.

## Recovery Model

With `core/store_local` in place:

- installs, connections, and credentials survive BEAM restart
- lease metadata survives and lease payload is reconstructed from durable
  credential truth
- runs, attempts, events, artifacts, ingress records, and targets survive
  restart

For the hosted webhook path:

- pair `core/store_local` with `core/dispatch_runtime` storage for durable async
  transport state
- pair it with `core/webhook_router` storage for durable route state

## Proof Surface

Current proofs:

- `core/store_local` package tests
- `apps/devops_incident_response`

The `apps/devops_incident_response` proof is the honest reference for local
restart-safe auth, control-plane truth, hosted routes, and async replay without
Postgres.
