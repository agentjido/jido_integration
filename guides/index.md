# Jido Integration Guides

This is the HexDocs entry point for the workspace root. Use the guides here
for the long-lived architecture and operational model, and use `docs/` for the
more implementation-specific workspace notes.

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

## Reading Order

1. read `architecture.md` to understand the package boundaries
2. read `runtime_model.md` to understand direct, session, and stream execution
3. read `durability.md` before choosing a store tier
4. read `connector_lifecycle.md` before authoring or reviewing a connector
5. read `conformance.md` before running package acceptance
6. read `async_and_webhooks.md` before using hosted async or webhook paths
7. read `reference_apps.md` to see end-to-end proof surfaces
8. read `observability.md` for telemetry and pressure semantics
9. read `developer/index.md` when you need the internals and package map
