# Jido Integration V2 Platform

Public facade package for the final V2 surface.

This is the package consumers depend on when they want the stable
`Jido.Integration.V2` entrypoint without wiring the internal control-plane
packages directly.

## Owns

- the public app identity `:jido_integration_v2`
- the stable `Jido.Integration.V2` facade module
- the typed public invocation helper `Jido.Integration.V2.InvocationRequest`
- public connector and capability discovery
- public auth lifecycle delegation
- durable review and target lookup delegation
- inference review projection over durable phase-0 control-plane truth

## Public API Groups

Connector discovery:

- `connectors/0`
- `capabilities/0`
- `fetch_connector/1`
- `fetch_capability/1`
- `register_connector/1`
- `catalog_entries/0`
- `projected_catalog_entries/0`

Auth lifecycle:

- `start_install/3`
- `complete_install/2`
- `fetch_install/1`
- `connection_status/1`
- `request_lease/2`
- `rotate_connection/2`
- `revoke_connection/2`

Invocation:

- `InvocationRequest.new!/1`
- `invoke/1`
- `invoke/3`

Public invocation uses `connection_id` as the consumer-facing auth binding
when the capability requires a durable connection. Credential refs stay behind
the auth and control-plane seam.

Durable review and target truth:

- `fetch_run/1`
- `fetch_attempt/1`
- `events/1`
- `record_artifact/1`
- `fetch_artifact/1`
- `run_artifacts/1`
- `announce_target/1`
- `fetch_target/1`
- `targets/1`
- `compatible_targets/1`
- `compatible_targets_for/2`
- `review_packet/2`

`catalog_entries/0` remains the authored operator-facing summary surface.
`projected_catalog_entries/0` exports the published generated common consumer
surface, including generated action and sensor names, generated plugin
identity, and JSON Schema derived from the canonical Zoi contracts.

For phase-0 inference runs, `review_packet/2` synthesizes the connector and
capability summary directly from durable run and attempt truth. No registered
connector manifest is required for that review path yet.

## Design Boundary

This package is the public facade, not the place where every runtime concern
lives.

It delegates into child packages that own the real behavior:

- `core/auth`
- `core/control_plane`
- `core/contracts`

Hosted webhook routing and async replay stay in separate package APIs:

- `Jido.Integration.V2.WebhookRouter`
- `Jido.Integration.V2.DispatchRuntime`

## Dependency Posture

- runtime dependencies stay in `core/*`
- connectors remain opt-in and are pulled into this package only for tests
- `core/store_local` and `core/store_postgres` remain explicit durability
  choices, not mandatory runtime dependencies for facade consumers
- packages and apps should still declare every child package whose modules they
  reference directly

## Installation

Inside this monorepo, depend on `core/platform` when a package wants the public
facade. The exact relative `path:` depends on the caller location.

App-style example:

```elixir
def deps do
  [
    {:jido_integration_v2, path: "../../core/platform"}
  ]
end
```

## Proof Surface

Current public-facade proofs:

- `core/platform/test/jido/integration/v2_test.exs`
- `core/platform/test/jido/integration/v2_inference_review_packet_test.exs`
- `core/platform/examples/inference_review_packet.exs`
- `apps/trading_ops`
- `connectors/github` live acceptance, which drives the current auth and
  invocation surface through `Jido.Integration.V2`
- `connectors/notion`, which now proves generated common action, plugin, and
  sensor publication through the facade path

## Related Guides

- [Inference Review Packets](guides/inference_review_packets.md)
- [Inference Baseline](../../guides/inference_baseline.md)
- [Architecture](../../guides/architecture.md)
- [Runtime Model](../../guides/runtime_model.md)
- [Connector Lifecycle](../../guides/connector_lifecycle.md)
- [Examples](examples/README.md)
