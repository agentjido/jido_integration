# Jido Integration Guides

This is the main documentation entry point for platform users and integrators.
These guides explain the package surface, runtime choices, durability model,
connector publication posture, and release flow. Repo-internal contributor
notes stay in `docs/`, package-local READMEs, and app-local proof runbooks.

## Menu

### General

- [Architecture](architecture.md)
- [Execution Plane Alignment](execution_plane_alignment.md)
- [Runtime Model](runtime_model.md)
- [Inference Baseline](inference_baseline.md)
- [Durability](durability.md)
- [Connector Lifecycle](connector_lifecycle.md)
- [Conformance](conformance.md)
- [Async And Webhooks](async_and_webhooks.md)
- [Publishing](publishing.md)
- [Observability](observability.md)

## Suggested Reading Order

1. read `architecture.md` to understand what the platform packages own
2. read `execution_plane_alignment.md` to understand the frozen lower-boundary
   packet and what this repo may carry versus expose
3. read `runtime_model.md` to choose the right execution lane
4. read `inference_baseline.md` for the live inference contracts,
   durability model, and proof surface
5. read `durability.md` before selecting a state tier
6. read `connector_lifecycle.md` to understand connector publication and review
7. read `async_and_webhooks.md` if you need hosted ingress or replay
8. read `publishing.md` if you need the welded
   `mix release.prepare -> mix release.track -> mix release.publish ->
   mix release.archive` workflow
9. read `observability.md` for telemetry and pressure semantics
10. read `conformance.md` if you are validating connector publication claims
