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
- resolve external-secret-backed lease or refresh material at execution time
  when an external secret resolver is configured
- minimize lease payloads and invalidate lease use through connection state,
  not run-ledger cleanup
- delegate restart-safe local auth durability to `core/store_local`
- delegate Postgres repo and migration ownership to `core/store_postgres`

## Current Durable Auth Model

- `Install` is the control-plane-managed install or reauth attempt and records
  `profile_id`, `flow_kind`, callback/state correlation, PKCE digest,
  requested/granted scopes, and terminal timestamps/reasons
- `Connection` is the durable public auth binding keyed by `connection_id` and
  records `profile_id`, `management_mode`, `secret_source`,
  `current_credential_ref_id`, `current_credential_id`, refresh/rotation
  posture, and degradation or revocation reasons
- `CredentialRef` is the stable non-secret handle owned by auth
- `Credential` is the versioned secret-bearing record tied back to
  `credential_ref_id`, `connection_id`, and `profile_id`
- `CredentialLease` and auth-owned `LeaseRecord` keep runtime execution
  short-lived; durable lease rows store only safe lineage and payload-key
  metadata, and auth reconstructs lease payloads from current credential truth
  plus any required external-secret resolution at lease-read time

External-secret-backed connections keep durable ownership in auth without
copying external material into lease rows. Lease issuance fails deterministically
when required external runtime material cannot be resolved, and auth records
the non-secret resolution outcome on the durable connection while transitioning
the connection to `:degraded` or `:reauth_required` according to the current
stage and configured failure policy.

The public facade still binds authenticated invocation through `connection_id`
only. `credential_ref_id`, `credential_id`, and secret-bearing lineage stay
inside auth and store implementations.

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
