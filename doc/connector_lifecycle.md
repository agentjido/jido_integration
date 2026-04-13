# Connector Lifecycle

Connectors are authored in `core/contracts` and reviewed through the conformance
engine. The important user-facing point is that connectors stay package-local,
publish explicit capability contracts, and are reviewed against deterministic
evidence rather than hidden repo-wide behavior.

## Lifecycle

1. define the connector manifest and capability contracts
2. implement the runtime handler in the connector package
3. add deterministic fixtures and package-local evidence
4. run `mix test` and `mix docs`
5. run `mix jido.conformance <ConnectorModule>` from the workspace root
6. keep the live acceptance proof package-local if the connector needs one

## Boundary Rules

- direct connectors stay on the provider-SDK path
- non-direct capabilities keep their authored runtime routing explicit
- `connection_id` is the public auth binding
- `credential_ref` remains behind auth and control-plane internals
- hosted webhook and async behavior stays above the connector package when it
  is not the connector's own responsibility
- unpublished first-party runtime deps may resolve from sibling paths locally
  and from pinned git refs otherwise, while published provider SDKs may resolve
  from sibling paths locally and from Hex otherwise, not from connector-local
  vendored `deps/` trees
- compile-time inventory or generation inputs must be owned by the connector
  package when they participate in connector compilation

## Projection Rules

`core/contracts` defines the common projection surface. Authored connector
metadata can project into public actions, sensors, and plugins, but only when
it is explicitly marked as part of the shared consumer surface.

- `:common` publication is for curated, stable surfaces only
- published common operations and triggers must stay schema-backed rather than
  passthrough placeholders
- generated action, sensor, and plugin modules are part of the review claim
- connector-local inventory can stay outside projection when schemas or
  provider posture are still unstable

## Review Rule

If a connector package cannot explain its runtime class, auth posture, and
boundary ownership in one README, it is not ready to be treated as a stable
surface.
