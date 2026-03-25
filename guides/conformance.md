# Conformance

`core/conformance` owns the reusable connector review engine.

## Stable Entry Point

The workspace root exposes the stable acceptance command:

```bash
mix jido.conformance <ConnectorModule>
```

## Baseline Profile

`connector_foundation` is the deterministic baseline profile. Its suite order
is intentionally fixed so review runs are comparable across connector packages.

1. `manifest_contract`
2. `consumer_surface_projection`
3. `capability_contracts`
4. `runtime_class_fit`
5. `policy_contract`
6. `deterministic_fixtures`
7. `ingress_definition_discipline`

`consumer_surface_projection` is the common-surface hardening suite. It proves
that generated actions, sensors, and plugins for published common surfaces
actually resolve and that their projection metadata stays internally
consistent. Connector-local inventory is intentionally outside that check.

## Working Rule

Conformance stays reusable by keeping evidence package-local.
Connector packages own the fixtures, runtime-driver evidence, and live proof
status. `core/conformance` owns the orchestration and rendering only.

## Extension Rule

If a future profile needs more checks, add suites to the profile rather than
changing the root command shape.
