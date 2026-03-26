# Jido Integration Guides

This is the main documentation entry point for platform users and integrators.
These guides explain the product surface, runtime choices, durability model,
connector publication posture, and proof apps. For repo internals and
contributor workflows, use the developer section.

## Menu

### General

- [Architecture](architecture.md)
- [Runtime Model](runtime_model.md)
- [Durability](durability.md)
- [Connector Lifecycle](connector_lifecycle.md)
- [Conformance](conformance.md)
- [Async And Webhooks](async_and_webhooks.md)
- [Reference Apps](reference_apps.md)
- [Observability](observability.md)

### Developer

- [Developer Index](developer/index.md)

## Suggested Reading Order

1. read `architecture.md` to understand what the platform packages own
2. read `runtime_model.md` to choose the right execution lane
3. read `durability.md` before selecting a state tier
4. read `connector_lifecycle.md` to understand connector publication and review
5. read `async_and_webhooks.md` if you need hosted ingress or replay
6. read `reference_apps.md` to see end-to-end proofs
7. read `observability.md` for telemetry and pressure semantics
8. read `conformance.md` if you are validating connector publication claims
9. read `developer/index.md` only when you need the internal package map
