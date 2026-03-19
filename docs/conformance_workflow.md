# Connector Conformance Guide

`core/conformance` is the reusable V2-native connector review package. The
workspace root exposes it through a stable task surface:

```bash
mix jido.conformance <ConnectorModule>
```

Example:

```bash
mix jido.conformance Jido.Integration.V2.Connectors.GitHub
mix jido.conformance Jido.Integration.V2.Connectors.Notion
```

## Why It Exists

Conformance keeps connector review semantics out of the workspace root while
giving the repo one canonical connector acceptance command.

It exists to prove that a connector:

- publishes a valid authored manifest contract and derived executable capabilities
- fits the declared runtime family
- declares policy posture explicitly
- can execute deterministic fixtures through lease-only auth context
- publishes ingress definitions when it claims trigger capability

## Current Stable Profile

The default and current stable profile is `connector_foundation`.

It runs these suites in order:

1. `manifest_contract`
2. `capability_contracts`
3. `runtime_class_fit`
4. `policy_contract`
5. `deterministic_fixtures`
6. `ingress_definition_discipline`

The task API is intentionally narrow:

- `--profile`
- `--format`
- `--output`

Future async or webhook-routing profiles should extend the suite list, not
change the root task shape.

## Standard Workflow

For a connector package under `connectors/<name>/`:

1. implement or update the connector `manifest/0`
2. author auth, catalog, operation, and trigger entries in that manifest rather than hand-writing executable capabilities
3. keep runtime handlers in the connector package and declare explicit child
   deps in that package `mix.exs`
4. add or update deterministic tests in the connector package
5. add or update the optional `<ConnectorModule>.Conformance` companion module
6. run package-local `mix test` and `mix docs`
7. run `mix jido.conformance <ConnectorModule>` from the workspace root
8. finish with the root monorepo gates and `mix ci`

For thin provider-SDK connectors such as `connectors/notion`, deterministic
fixtures should run through the provider package's transport seam instead of a
second handwritten fake provider layer.

Conformance is part of connector review. It does not replace package-local
tests, docs, or the root acceptance gate.

## Companion Module Contract

Connectors can publish deterministic conformance evidence through an optional
companion module named `<ConnectorModule>.Conformance`.

The companion module may expose:

- `fixtures/0`: deterministic execution fixtures for runtime/result review
- `ingress_definitions/0`: ingress definitions for trigger-capable connectors

The companion module returns plain maps so the connector package does not need
to depend on `core/conformance`.

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

## How To Read Failures

- `manifest_contract`
  - fix connector id stability, authored auth/catalog/operation/trigger completeness, or derived capability ownership
- `capability_contracts`
  - fix authored operation or trigger ids, projection drift, invalid policy metadata, or malformed derived capability structs
- `runtime_class_fit`
  - fix handler modules so they match `direct`, `session`, or `stream`
- `policy_contract`
  - declare scopes, environment, runtime class, and sandbox posture explicitly
- `deterministic_fixtures`
  - fix provider determinism, expected output/events/artifacts, or auth lease
    assumptions
- `ingress_definition_discipline`
  - keep trigger definitions explicit and aligned with the derived trigger capability surface

## Output Modes

- human
  - default stdout summary
- json
  - full JSON report to stdout with `--format json`
- file
  - `--output path.json` writes the JSON report to disk

## Relationship To The Generator

`mix jido.integration.new` emits a package-local baseline conformance test and
companion module. Treat that output as the starting contract, not the finished
connector.

Generated connectors still need:

- real provider or handler implementation
- real fixture expectations
- package-local docs
- optional live acceptance or proof code kept inside the connector package when
  appropriate
