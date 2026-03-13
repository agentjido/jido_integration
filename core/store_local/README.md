# Jido Integration V2 Store Local

Restart-safe local durability package for the current `auth` and
`control_plane` store behaviours.

Owns:

- explicit local adapters for:
  - credential, connection, install, and lease truth from `core/auth`
  - run, attempt, event, artifact, ingress, and target truth from
    `core/control_plane`
- a package-owned local storage server that persists one restart-safe state file
- package-local contract tests and restart-recovery tests
- a configuration surface for local development, proof apps, and tests that do
  not want to require Postgres

This package intentionally does not replace the in-memory defaults inside
`core/auth` and `core/control_plane`. If a host only needs process-scoped state,
keep those defaults. `core/store_local` is the middle tier between that
in-memory posture and `core/store_postgres`.

## Configuration

Add `core/store_local` as an explicit dependency from the package that wants
local durability, then point `auth` and `control_plane` at the local adapters.

Reference-app style dependency example:

```elixir
def deps do
  [
    {:jido_integration_v2_store_local, path: "../../core/store_local"}
  ]
end
```

Runtime configuration:

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
can set the same application env values programmatically.

## Semantics

Compared with the owner-package in-memory defaults:

- `store_local` survives BEAM restarts
- ingress dedupe, checkpoint, transaction, and rollback semantics stay explicit
- run, attempt, and event truth stay redacted at persistence time
- credential truth stays behind `auth` and is persisted with
  `Auth.SecretEnvelope` encryption rather than plain text
- lease rows persist bounded metadata only; lease payload is reconstructed from
  durable credential truth on fetch

Compared with `core/store_postgres`:

- both packages implement the same current v2 behaviours they claim to support
- `store_local` is single-node, file-backed durability for development,
  reference apps, and restart-recovery proofs
- `store_postgres` remains the shared database-backed tier with migrations,
  sandbox helpers, and stronger operational posture
- `store_local` does not try to replace Postgres for multi-writer, production,
  or SQL-queryable scenarios

## When To Use Which Tier

- Use the in-memory defaults in `core/auth` and `core/control_plane` when the
  process lifetime is enough.
- Use `core/store_local` when you need restart-safe local truth without
  provisioning Postgres.
- Use `core/store_postgres` when you need the canonical durable tier for shared
  environments, migrations, and stronger operational guarantees.
