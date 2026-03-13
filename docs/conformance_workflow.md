# Connector Conformance Workflow

`core/conformance` is the reusable v2-native connector review package.

The repo root exposes it through:

```bash
mix jido.conformance <ConnectorModule>
```

Example:

```bash
mix jido.conformance Jido.Integration.V2.Connectors.GitHub
```

## Current Profile

The default and current stable profile is `connector_foundation`.

It runs these suites in order:

1. `manifest_contract`
2. `capability_contracts`
3. `runtime_class_fit`
4. `policy_contract`
5. `deterministic_fixtures`
6. `ingress_definition_discipline`

The task API is intentionally only `--profile`, `--format`, and `--output` so
future async or webhook-routing profiles can be added without changing the root
command shape.

## Output Modes

- human: default stdout summary
- json: full JSON report to stdout with `--format json`
- file: `--output path.json` always writes the JSON report to disk

## Companion Module Contract

Connectors should publish deterministic conformance evidence through an
optional companion module named `<ConnectorModule>.Conformance`.

The companion module may expose:

- `fixtures/0`: deterministic execution fixtures for runtime/result review
- `ingress_definitions/0`: ingress definitions for trigger-capable connectors

The companion module returns plain maps so connectors do not need a runtime
dependency on `core/conformance`.

### Fixture Shape

Each fixture map should declare:

- `capability_id`
- `input`
- `credential_ref`
- `credential_lease`
- optional `context`
- optional `expect`

`expect` currently supports:

- `output`
- `event_types`
- `artifact_types`
- `artifact_keys`

## What The Foundation Profile Checks

- manifests stay deterministic and non-empty
- capability ownership and ids stay explicit
- handlers fit the declared runtime family
- policy metadata declares scopes, environment, and sandbox posture explicitly
- fixtures execute through lease-only runtime context and return deterministic
  `RuntimeResult` review surfaces
- trigger capabilities publish matching ingress definitions when applicable
