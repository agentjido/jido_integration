# Jido Integration V2 Auth

Owns the control-plane auth lifecycle: install truth, connection truth, durable credential truth, and short-lived execution leases.

Current responsibilities:

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
- resolve `CredentialRef` for policy evaluation without returning raw secret material
- mint short-lived `CredentialLease` values for runtime execution
- refresh expired credentials before lease issuance when a refresh handler is configured
- minimize lease payloads and invalidate lease use through connection state, not run-ledger cleanup
- delegate restart-safe local auth durability to `core/store_local`
- delegate Postgres Repo and migration ownership to `core/store_postgres`
