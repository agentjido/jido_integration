# Jido Integration V2 Auth

Credential lifecycle and lease issuance for the integration control plane.

This package owns install truth, connection truth, durable credential truth,
and short-lived execution leases. It keeps secret-bearing state behind the auth
boundary and lets the control plane consume opaque handles instead of raw
material.

## Responsibilities

- expose the host-facing auth boundary:
  - `start_install/3`
  - `complete_install/2`
  - `fetch_install/1`
  - `connection_status/1`
  - `request_lease/2`
  - `rotate_connection/2`
  - `revoke_connection/2`
- define credential, lease-record, connection, and install store behaviours
- keep durable secret truth inside `auth` and out of runtime packages
- return opaque `CredentialRef` handles to the control plane
- resolve `CredentialRef` for policy evaluation without returning raw secret
  material
- mint short-lived `CredentialLease` values for runtime execution
- refresh expired credentials before lease issuance when a refresh handler is
  configured
- minimize lease payloads and invalidate lease use through connection state,
  not run-ledger cleanup
- delegate restart-safe local auth durability to `core/store_local`
- delegate Postgres repo and migration ownership to `core/store_postgres`

## Boundary

`core/auth` owns auth truth only.

- it does not own run, attempt, or event truth
- it does not own runtime execution
- it does not own hosted webhook routing
- it does not own transport retry or replay

## Related Guides

- [Architecture](../../guides/architecture.md)
- [Durability](../../guides/durability.md)
- [Connector Lifecycle](../../guides/connector_lifecycle.md)
