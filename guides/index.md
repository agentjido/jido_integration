# Jido Integration Guides

This is the main documentation entry point for platform users and integrators.
These guides explain the product surface, runtime choices, durability model,
connector publication posture, and proof apps. For repo internals and
contributor workflows, use the developer section.

## Menu

### General

- [Architecture](architecture.md)
- [Runtime Model](runtime_model.md)
- [Inference Baseline](inference_baseline.md)
- [Durability](durability.md)
- [Connector Lifecycle](connector_lifecycle.md)
- [Conformance](conformance.md)
- [Async And Webhooks](async_and_webhooks.md)
- [Publishing](publishing.md)
- [Reference Apps](reference_apps.md)
- [Observability](observability.md)

### Developer

- [Developer Index](developer/index.md)

## Suggested Reading Order

1. read `architecture.md` to understand what the platform packages own
2. read `runtime_model.md` to choose the right execution lane
3. read `inference_baseline.md` for the live inference contracts,
   durability model, and proof surface
4. read `durability.md` before selecting a state tier
5. read `connector_lifecycle.md` to understand connector publication and review
6. read `async_and_webhooks.md` if you need hosted ingress or replay
7. read `publishing.md` if you need the welded `mix release.prepare ->
   mix release.publish -> mix release.archive` workflow
8. read `reference_apps.md` to see end-to-end proofs
9. read `observability.md` for telemetry and pressure semantics
10. read `conformance.md` if you are validating connector publication claims
11. read `developer/index.md` only when you need the internal package map
