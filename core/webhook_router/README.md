# Jido Integration V2 Webhook Router

Hosted webhook route registration and route-resolution bridge above
`core/ingress`.

Owns:

- route registration, listing, fetch, and removal
- callback-topology metadata for hosted webhook paths
- secret-ref resolution through `core/auth`
- assembly of `Ingress.Definition`
- handoff into `core/dispatch_runtime`

`core/ingress` stays focused on normalization and durable trigger admission.

## Callback Topology

The router keeps callback topology explicit per route:

- `:dynamic_per_install`
  - one hosted callback binding per install
  - resolved directly from `install_id`
- `:static_per_app`
  - one app-level callback shape shared across tenants or installs
  - resolved from `connector_id` plus configured request lookup keys such as
    `body.account_id`

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
3. assemble `Jido.Integration.V2.Ingress.Definition`
4. delegate request admission to `core/ingress`
5. enqueue the admitted trigger into `core/dispatch_runtime`

The package keeps route persistence local and file-backed so route registration
can survive process restarts without pushing that state into `core/ingress`.
