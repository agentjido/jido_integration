# Jido Integration V2 Store Postgres

Canonical Postgres durability surface for the platform.

## Owns

- the canonical `Ecto.Repo`
- migrations for control-plane and auth truth
- SQL sandbox helpers for durability tests
- Postgres adapters for `control_plane` and `auth` behaviours
- durable tables for `ArtifactRef` and `TargetDescriptor`
- durable `access_graph_edges` and `access_graph_epochs` tables for
  `Platform.AccessGraph.v1`
- encrypted durable credential rows plus safe connection/install/lease rows
  for auth lifecycle truth
- the canonical durable submission ledger used by `core/brain_ingress`

Repo ownership and migration ownership are explicit here by design. During the
foundation phase, owner packages define behaviours while `store_postgres`
implements them and keeps database startup, migrations, and test posture
coherent.

Use `core/store_local` when a host needs restart-safe single-node durability
without provisioning Postgres. Use `core/store_postgres` when the environment
needs the canonical shared durable tier, migrations, sandbox support, and
database-backed operational guarantees.

## Current Control-Plane Durability

- runs, attempts, and append-only run events
- trigger records, dedupe keys, and polling checkpoints
- artifact refs keyed by `artifact_id` and indexed by `run_id`
- target descriptors keyed by `target_id`
- durable round-tripping of integrity metadata and target compatibility inputs
- auth rows with:
  - encrypted secret-bearing credential fields
  - explicit install-session state including `profile_id`, flow/callback
    correlation, and reauth lineage
  - explicit connection state including profile, management, secret-source, and
    current-credential lineage fields
  - versioned credential lineage through `credential_ref_id`, `version`,
    source/source-ref metadata, and supersession links
- lease records that persist only bounded metadata, not raw lease payloads,
  including `credential_id` and `profile_id`
- access graph rows with immutable edge identity, controlled revocation close,
  and per-tenant monotonic epochs allocated once per graph transaction

The auth tables now also carry a forward-only expansion migration,
`20260403000000_expand_phase_0_auth_truth_columns.exs`, which repairs already
migrated dev/test databases that applied an older auth-table shape before the
current lineage columns landed.

## Test And Validation Defaults

`core/store_postgres` is also the shared test-time durability seam for packages
that validate the public platform and ingress layers against the canonical
database-backed stores.

That means root validation commands such as `mix mr.test` and `mix ci` expect
a reachable Postgres test database unless the relevant packages are
reconfigured explicitly.

Before calling the root acceptance surface blocked on Postgres reachability,
run the root preflight task:

```bash
mix mr.pg.preflight
```

That check confirms the canonical `store_postgres` tier is reachable for the
root `:test` surface. It does not change the other durability tiers:

- in-memory defaults remain available in `core/auth` and `core/control_plane`
- `core/store_local` remains the restart-safe local middle tier
- `core/store_postgres` remains the shared database-backed tier

Default test settings:

- `JIDO_INTEGRATION_V2_DB_HOST=127.0.0.1`
- `JIDO_INTEGRATION_V2_DB_PORT=5432`
- `JIDO_INTEGRATION_V2_DB_NAME=jido_integration_v2_test`
- `JIDO_INTEGRATION_V2_DB_USER=postgres`
- `JIDO_INTEGRATION_V2_DB_PASSWORD=postgres`
- `JIDO_INTEGRATION_V2_DB_POOL_SIZE=10`

If you validate against a socket-mounted local Postgres instead of TCP, set
`JIDO_INTEGRATION_V2_DB_SOCKET_DIR`.

The same package now backs the canonical shared submission ledger for durable
brain-to-lower-gateway intake. Hosts that adopt `core/brain_ingress` in shared
environments should point that package at the Postgres-backed ledger adapter.

## Related Guides

- [Durability](../../guides/durability.md)
- [Architecture](../../guides/architecture.md)
- [Observability](../../guides/observability.md)
