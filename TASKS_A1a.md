# A1a: Core Contract Implementation — Task List

**Date:** 2026-03-07
**Method:** TDD (Red-Green-Refactor)
**Goal:** Implement the real infrastructure behind A0's frozen contracts

---

## Block 1: Credential Types (5 tasks)

- [x] 1.1 RED: Test `Auth.Credential` struct for oauth2 type (access_token, refresh_token, expires_at, scopes, token_semantics)
- [x] 1.2 RED: Test `Auth.Credential` struct for api_key type (key, scopes)
- [x] 1.3 RED: Test `Auth.Credential` struct for service_account, session_token, webhook_secret types
- [x] 1.4 RED: Test `Auth.Credential.expired?/1` — checks expires_at against now
- [x] 1.5 GREEN: Implement `Auth.Credential` module

## Block 2: Credential Store Backend (7 tasks)

- [x] 2.1 RED: Test `Auth.Store` behaviour definition — `store/3`, `fetch/2`, `delete/2`, `list/1`
- [x] 2.2 RED: Test `Auth.Store.ETS.start_link/1` creates named ETS table
- [x] 2.3 RED: Test store + fetch roundtrip (store credential, fetch by auth_ref)
- [x] 2.4 RED: Test scope enforcement on fetch — connector_id in context must match auth_ref prefix
- [x] 2.5 RED: Test delete removes credential
- [x] 2.6 RED: Test TTL expiry — expired credentials return `{:error, :expired}`
- [x] 2.7 GREEN: Implement `Auth.Store.ETS` GenServer

## Block 3: Connection State Machine (8 tasks)

- [x] 3.1 RED: Test `Auth.Connection` struct creation (id, connector_id, tenant_id, state, scopes, revision, actor_trail)
- [x] 3.2 RED: Test valid transitions: `new→installing`, `installing→connected`, `connected→degraded`
- [x] 3.3 RED: Test valid transitions: `degraded→connected`, `connected→reauth_required`, `reauth_required→installing`
- [x] 3.4 RED: Test valid transitions: `*→revoked`, `*→disabled`, `revoked→installing`, `disabled→installing`
- [x] 3.5 RED: Test INVALID transitions are rejected (e.g. `connected→installing`, `revoked→connected`)
- [x] 3.6 RED: Test revision increments on every transition
- [x] 3.7 RED: Test actor_trail records (actor_id, from_state, to_state, timestamp) on each transition
- [x] 3.8 GREEN: Implement `Auth.Connection` with state machine

## Block 4: Auth Server — Credential Operations (10 tasks)

- [x] 4.1 RED: Test `Auth.Server.start_link/1` starts supervised GenServer
- [x] 4.2 RED: Test `store_credential/4` — stores cred, returns auth_ref in format `"auth:<connector>:<scope_id>"`
- [x] 4.3 RED: Test `resolve_credential/2` — returns credential when scope matches
- [x] 4.4 RED: Test `resolve_credential/2` — returns `:scope_violation` when connector_id doesn't match
- [x] 4.5 RED: Test `resolve_credential/2` — returns `:not_found` for unknown auth_ref
- [x] 4.6 RED: Test `rotate_credential/3` — replaces credential, preserves auth_ref
- [x] 4.7 RED: Test `revoke_credential/2` — removes credential, emits telemetry
- [x] 4.8 RED: Test `list_credentials/1` — lists all creds for a connector type
- [x] 4.9 RED: Test telemetry events: `auth.install.started`, `auth.install.succeeded`, `auth.revoked`, `auth.rotated`
- [x] 4.10 GREEN: Implement `Auth.Server` GenServer

## Block 5: Auth Server — Connection Lifecycle (8 tasks)

- [x] 5.1 RED: Test `start_install/3` — creates connection in :installing state, returns auth_url
- [x] 5.2 RED: Test `handle_callback/3` — validates state token, transitions to :connected, stores credential
- [x] 5.3 RED: Test `handle_callback/3` — rejects invalid/expired state token
- [x] 5.4 RED: Test `get_connection/1` — returns connection with current state
- [x] 5.5 RED: Test `transition_connection/3` — validates and applies state transition
- [x] 5.6 RED: Test `check_scopes/2` — passes when connection has required scopes
- [x] 5.7 RED: Test `check_scopes/2` — fails with missing_scopes error
- [x] 5.8 GREEN: Wire connection lifecycle into Auth.Server

## Block 6: Token Refresh (6 tasks)

- [x] 6.1 RED: Test `resolve_credential/2` with expired oauth2 token triggers refresh callback
- [x] 6.2 RED: Test refresh callback receives refresh_token and returns new access_token
- [x] 6.3 RED: Test successful refresh updates stored credential transparently
- [x] 6.4 RED: Test refresh failure transitions connection to :reauth_required
- [x] 6.5 RED: Test telemetry: `auth.token.refreshed` and `auth.token.refresh_failed`
- [x] 6.6 GREEN: Implement refresh logic in Auth.Server

## Block 7: Scope Enforcement in Execute Pipeline (5 tasks)

- [x] 7.1 RED: Test `execute/3` with `auth_server` option uses real Auth.Server for scope checking
- [x] 7.2 RED: Test `execute/3` blocks operation when scopes missing (via Auth.Server)
- [x] 7.3 RED: Test `execute/3` resolves token and passes to adapter run/3
- [x] 7.4 RED: Test `execute/3` with no required_scopes skips auth entirely
- [x] 7.5 GREEN: Wire Auth.Server into execute/3 pipeline

## Block 8: Webhook Route Registry (6 tasks)

- [x] 8.1 RED: Test `Webhook.Route` struct (connector_id, callback_topology, path_pattern, verification)
- [x] 8.2 RED: Test `Webhook.Router.register_route/2` adds route
- [x] 8.3 RED: Test `Webhook.Router.resolve/2` — matches path to connector + tenant (dynamic_per_install)
- [x] 8.4 RED: Test `Webhook.Router.resolve/2` — matches static_per_app with payload tenant resolution
- [x] 8.5 RED: Test `Webhook.Router.unregister_route/1` removes route
- [x] 8.6 GREEN: Implement `Webhook.Router` GenServer

## Block 9: Webhook Dedupe Store (5 tasks)

- [x] 9.1 RED: Test `Webhook.Dedupe.start_link/1` creates ETS table
- [x] 9.2 RED: Test `seen?/2` returns false for new delivery_id
- [x] 9.3 RED: Test `mark_seen/2` + `seen?/2` returns true for duplicate
- [x] 9.4 RED: Test TTL cleanup — expired entries are pruned
- [x] 9.5 GREEN: Implement `Webhook.Dedupe` GenServer with TTL sweep

## Block 10: Webhook Ingress Pipeline (7 tasks)

- [x] 10.1 RED: Test `Webhook.Ingress.process/2` full pipeline: route → verify → dedupe → dispatch
- [x] 10.2 RED: Test ingress rejects unroutable webhook (unknown path)
- [x] 10.3 RED: Test ingress rejects invalid signature
- [x] 10.4 RED: Test ingress deduplicates (same delivery_id → :duplicate)
- [x] 10.5 RED: Test ingress dispatches to adapter.handle_trigger/2 on success
- [x] 10.6 RED: Test telemetry: webhook.received, webhook.routed, webhook.signature_failed, webhook.dispatched
- [x] 10.7 GREEN: Implement `Webhook.Ingress` module

## Block 11: Supervision Tree (3 tasks)

- [x] 11.1 RED: Test Application starts Auth.Server, Webhook.Router, Webhook.Dedupe
- [x] 11.2 GREEN: Update Application module
- [x] 11.3 REFACTOR: Ensure all GenServers accept `:name` option for test isolation

## Block 12: Integration Tests — Full Lifecycle (5 tasks)

- [x] 12.1 RED: Test full OAuth lifecycle: install → callback → store credential → execute operation → verify token used
- [x] 12.2 RED: Test full webhook lifecycle: register route → receive webhook → verify → dedupe → dispatch
- [x] 12.3 RED: Test scope evolution: execute with read scope → upgrade to write scope → execute write
- [x] 12.4 RED: Test connection degradation: token expires → refresh fails → reauth_required
- [x] 12.5 GREEN: Make all integration tests pass

## Block 13: Examples — Real Auth Flows (4 tasks)

- [x] 13.1 Update hello_world example to demonstrate auth server usage
- [x] 13.2 Create `examples/github_auth_lifecycle.ex` — full OAuth flow with GitHub adapter
- [x] 13.3 Create `examples/webhook_ingress_demo.ex` — webhook receive + verify + dedupe
- [x] 13.4 Update harness_core_loop dispatcher to use Auth.Server for credential resolution

## Block 14: Cleanup & Conformance (3 tasks)

- [x] 14.1 Ensure all 228+ existing tests still pass
- [x] 14.2 Run conformance on GitHub adapter with auth server wired in
- [x] 14.3 Update STATUS.md with A1a completion

---

## Module Map

```
lib/jido/integration/auth/
  credential.ex          # Credential struct (5 types)
  connection.ex          # Connection state machine
  store.ex               # Store behaviour
  store/ets.ex           # ETS backend
  server.ex              # Auth GenServer (orchestrates store + connections + refresh)

lib/jido/integration/webhook/
  route.ex               # Route struct
  router.ex              # Route registry GenServer
  dedupe.ex              # Dedupe store GenServer (ETS + TTL)
  ingress.ex             # Ingress pipeline module

examples/
  hello_world.ex         # (update) auth flow demo
  github_auth_lifecycle.ex  # Full OAuth lifecycle
  webhook_ingress_demo.ex   # Webhook pipeline demo
  harness_core_loop/     # (update) auth + webhook wiring
```

## Test Map

```
test/jido/integration/auth/
  credential_test.exs
  connection_test.exs
  store/ets_test.exs
  server_test.exs

test/jido/integration/webhook/
  router_test.exs
  dedupe_test.exs
  ingress_test.exs

test/jido/integration/
  lifecycle_test.exs     # Full end-to-end integration tests

test/examples/
  hello_world_test.exs   # (update)
  github_auth_lifecycle_test.exs
  webhook_ingress_demo_test.exs
  harness_core_loop_test.exs  # (update)
```

---

**Total: 82 tasks across 14 blocks**
**Estimated new modules: 10**
**Estimated new test files: 8**
