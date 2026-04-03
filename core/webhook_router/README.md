# Jido Integration V2 Webhook Router

Hosted webhook route registration and route-resolution bridge above
`core/ingress`.

Owns:

- route registration, listing, fetch, and removal
- callback-topology metadata for hosted webhook trigger paths
- hosted route records carrying explicit trigger capability identity plus
  normalized signal metadata
- secret-ref resolution through `core/auth`
- assembly of `Ingress.Definition`
- package-owned `:telemetry` for route resolution and failures
- handoff into `core/dispatch_runtime`

`core/ingress` stays focused on normalization and durable trigger admission.
Hosted OAuth/browser install callbacks are not routed through this package;
they remain auth-control surfaces that apps or host routers hand into
`core/auth`.

## Callback Topology

The router keeps callback topology explicit per route:

- `:dynamic_per_install`
  - one hosted callback binding per install
  - resolved directly from `install_id`
- `:static_per_app`
  - one app-level callback shape shared across tenants or installs
  - resolved from `connector_id` plus configured request lookup keys such as
    `body.account_id`

Static routes use `tenant_resolution_keys` and `tenant_resolution` to map
request fields onto the right route record.

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
same trigger capability. `signal_source` names the normalized ingress signal
source, not the public callback path.

## Secret Resolution

Route verification can use:

- a direct `secret`
- a `secret_ref` carrying a `CredentialRef` plus `secret_key`

When a `secret_ref` is present, the router resolves exactly that secret value
through `core/auth` at request time and does not persist the raw secret in the
route record.

## Bridge Flow

For hosted webhook requests:

1. resolve the route from install or connector context
2. resolve the verification secret when needed
3. assemble `Jido.Integration.V2.Ingress.Definition` from the route's authored
   trigger capability id and signal metadata
4. delegate request admission to `core/ingress`
5. enqueue the admitted trigger into `core/dispatch_runtime`

The package keeps route persistence local and file-backed so route registration
can survive process restarts without pushing that state into `core/ingress`.

## Telemetry

This package owns these stable `:telemetry` families:

- `[:jido, :integration, :webhook_router, :route, :resolved]`
- `[:jido, :integration, :webhook_router, :route, :failed]`

Metadata is redacted through `Jido.Integration.V2.Redaction` before emission.
Raw webhook request bodies are intentionally omitted from the emitted metadata.

## Proof Surface

Current proofs:

- `core/webhook_router/test/jido/integration/v2/webhook_router_route_store_test.exs`
- `core/webhook_router/test/jido/integration/v2/webhook_router_bridge_test.exs`
- `apps/devops_incident_response`, which proves a hosted signed webhook from
  route registration through async replay while keeping the hosted trigger
  manifest, explicit ingress-definition evidence, and route record aligned

## Related Guides

- [Async And Webhooks](../../guides/async_and_webhooks.md)
- [Architecture](../../guides/architecture.md)
- [Observability](../../guides/observability.md)
