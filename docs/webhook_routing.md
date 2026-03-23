# Webhook Routing Guide

`core/webhook_router` owns hosted webhook route lifecycle above
`core/ingress`.

## Responsibilities

It owns:

- route registration, lookup, listing, and removal
- callback-topology metadata
- secret resolution through `core/auth`
- ingress-definition assembly
- handoff into `core/dispatch_runtime`
- route-resolution telemetry

It does not replace `core/ingress`. Request normalization and durable trigger
admission stay in `core/ingress`.

## Callback Topologies

Supported topologies:

- `:dynamic_per_install`
  - requires `install_id`
  - resolves directly from install context
- `:static_per_app`
  - resolves by connector context plus request-derived tenant resolution keys

Static routes use:

- `tenant_resolution_keys`
- `tenant_resolution`

to map request fields such as `body.account_id` to a concrete route.

## Route Contract

Registered routes include:

- `connector_id`
- `tenant_id`
- optional `connection_id`
- optional `install_id`
- `trigger_id`
- `capability_id`
- `signal_type`
- `signal_source`
- `callback_topology`
- optional `validator`
- optional `verification`
- optional `delivery_id_headers`
- optional `tenant_resolution_keys`
- optional `tenant_resolution`
- optional `dedupe_ttl_seconds`

For hosted trigger routes, `trigger_id` and `capability_id` should name the
same trigger capability. `signal_type` and `signal_source` should match the
explicit ingress-definition evidence published by the connector-local hosted
proof. `signal_source` is the normalized ingress signal source, not the public
callback path.

Root conformance treats `trigger_id`, `signal_type`, and `signal_source` as
reviewable ingress evidence. If they drift from the trigger capability
metadata, the ingress-definition suite should fail.

Verification can use:

- a direct `secret`
- a `secret_ref` containing a `CredentialRef` and `secret_key`

## Bridge Flow

For hosted webhook requests:

1. resolve the route from install or connector context
2. resolve the verification secret when needed
3. assemble an `Ingress.Definition` from the route's trigger capability id and
   normalized signal metadata
4. delegate request normalization and admission to `core/ingress`
5. enqueue the admitted trigger into `core/dispatch_runtime`

This keeps routing concerns out of `core/ingress` and keeps async execution
out of the router.

## Durable Local State

`core/webhook_router` persists route state in its own storage directory so
route registration can survive process restart.

For full local restart-safe hosted workflows, pair it with:

- `core/store_local` for auth and control-plane truth
- `core/dispatch_runtime` storage for transport recovery

## Proof Surface

Current proofs:

- `core/webhook_router/test/jido/integration/v2/webhook_router_route_store_test.exs`
- `core/webhook_router/test/jido/integration/v2/webhook_router_bridge_test.exs`
- `apps/devops_incident_response`

The app proof is the reference for a real hosted route, signed request, async
handoff, replay, restart recovery, and explicit alignment between the
connector-local manifest, ingress-definition evidence, and route record.
