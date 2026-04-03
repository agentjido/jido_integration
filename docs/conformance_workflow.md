# Connector Conformance Guide

`core/conformance` is the reusable V2-native connector review package. The
workspace root exposes it through a stable task surface:

```bash
mix jido.conformance <ConnectorModule>
```

Example:

```bash
mix jido.conformance Jido.Integration.V2.Connectors.GitHub
mix jido.conformance Jido.Integration.V2.Connectors.Linear
mix jido.conformance Jido.Integration.V2.Connectors.MarketData
mix jido.conformance Jido.Integration.V2.Apps.DevopsIncidentResponse.GitHubIssueConnector
mix jido.conformance Jido.Integration.V2.Connectors.Notion
```

## Connector Acceptance Contract

A connector package is not review-complete until its package-local
verification, root conformance, and root acceptance gates all pass.

Treat `mix jido.conformance <ConnectorModule>` as the root connector
acceptance command for package-local authored truth. Package-local fixtures
stay package-local even though `mix jido.conformance <ConnectorModule>` runs
from the workspace root.

The minimum acceptance loop is:

1. package-local `mix compile --warnings-as-errors`
2. package-local `mix test`
3. package-local `mix docs`
4. root `mix jido.conformance <ConnectorModule>`
5. root monorepo gates and `mix ci`

## Why It Exists

Conformance keeps connector review semantics out of the workspace root while
giving the repo one canonical connector acceptance command.

It exists to prove that a connector:

- publishes a valid authored manifest contract and derived executable capabilities
- keeps authored auth profiles, connector-level auth unions, install posture,
  and reauth posture internally consistent
- ships loadable generated common consumer surfaces whose action/plugin/sensor
  metadata stays aligned with authored projection truth and remains unique
- fits the declared runtime family
- declares policy posture explicitly
- can execute deterministic fixtures through lease-only auth context without
  leaking raw lease secrets
- publishes ingress definitions when it claims trigger capability

For direct provider-SDK connectors, conformance proves the published surface
and lease-only runtime posture. Package tests still need to prove the
connector-local call-graph boundary:

- `install_binding` stays in install, reauth, manual-auth, or rotation flows
- runtime execution builds provider clients from credential leases only
- generated actions, plugins, and sensors remain derivative common projections,
  not a second authoring plane

## Current Stable Profile

The default and current stable profile is `connector_foundation`.

It runs these suites in order:

1. `manifest_contract`
2. `consumer_surface_projection`
3. `capability_contracts`
4. `runtime_class_fit`
5. `policy_contract`
6. `deterministic_fixtures`
7. `ingress_definition_discipline`

The task API is intentionally narrow:

- `--profile`
- `--format`
- `--output`

Future async or webhook-routing profiles should extend the suite list, not
change the root task shape.

## Standard Workflow

For a connector package under `connectors/<name>/`:

Hosted proofs that intentionally stay app-local use the same workflow, but the
conformance target is the app-owned connector module instead of the shared
provider connector package.

1. implement or update the connector `manifest/0`
2. author auth, catalog, operation, and trigger entries in that manifest rather than hand-writing executable capabilities
   Keep `auth.requested_scopes` as the authored superset of every operation and
   trigger `required_scopes`, and keep `auth.secret_names` as the authored
   superset of trigger `verification.secret_name` and
   `secret_requirements`.
   Keep `supported_profiles`, `default_profile`, `install.profiles`, and
   `reauth.profiles` aligned, and keep connector-level auth unions honest
   against the authored profiles.
   If the connector wraps a provider SDK, keep install and reauth normalization
   in connector-local `install_binding` helpers and keep runtime execution on a
   lease-built `client_factory` seam instead of reaching back into durable or
   provider-edge auth state.
3. keep runtime handlers in the connector package and declare explicit child
   deps in that package `mix.exs`
4. add or update deterministic tests in the connector package
5. add or update the optional `<ConnectorModule>.Conformance` companion module
   or the app-local companion surface that publishes ingress evidence
6. run package-local `mix compile --warnings-as-errors`, `mix test`, and `mix docs`
7. run `mix jido.conformance <ConnectorModule>` from the workspace root for the
   module that owns the published trigger evidence
8. finish with the root monorepo gates and `mix ci`

For thin provider-SDK connectors such as `connectors/linear` and
`connectors/notion`, deterministic
fixtures should run through the provider package's transport seam instead of a
second handwritten fake provider layer.

Conformance is part of connector review. It does not replace package-local
tests, docs, or the root acceptance gate.

## Companion Module Contract

Connectors can publish deterministic conformance evidence through an optional
companion module named `<ConnectorModule>.Conformance`.

The companion module may expose:

- `fixtures/0`: deterministic execution fixtures for runtime/result review
- `runtime_drivers/0`: non-direct runtime-driver ids mapped to deterministic
  package-local test drivers
- `ingress_definitions/0`: ingress definitions for trigger-capable connectors

The companion module is the connector-owned publication point for deterministic
fixtures, runtime-driver evidence, and ingress definitions. It returns plain
maps so the publishing package does not need to depend on `core/conformance`.

Hosted webhook proofs can use the same companion pattern from an app-local
connector module when trigger ownership intentionally lives above the shared
connector package.

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

For profile-driven connectors, fixture `credential_ref` and
`credential_lease` should also carry `profile_id`, and
`credential_lease.lease_fields` plus payload keys should match the authored
profile `lease_fields`.

## How To Read Failures

- `manifest_contract`
  - fix connector id stability, authored auth/catalog/operation/trigger completeness, auth profile/install/reauth drift, auth scope or trigger-secret coverage, or derived capability ownership
- `capability_contracts`
  - fix authored operation or trigger ids, projection drift, invalid policy metadata, or malformed derived capability structs
- `consumer_surface_projection`
  - fix common-surface metadata, generated action/plugin/sensor module
    loadability, generated projection drift, plugin action drift, plugin
    subscription drift, curated common-surface uniqueness, or
    placeholder-schema posture
  - if the connector wraps an SDK, keep in mind that conformance only proves
    the published generated surface boundary; package tests still need to prove
    `install_binding` and lease-built client seams do not leak into runtime
- `runtime_class_fit`
  - fix handler modules so they match `direct`, `session`, or `stream`
- `policy_contract`
  - declare scopes, environment, runtime class, and sandbox posture explicitly
- `deterministic_fixtures`
  - fix provider determinism, expected output/events/artifacts, auth lease
    projection drift, or review-safe redaction failures
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
companion module. Non-direct scaffolds also emit a package-local
`runtime_drivers/0` hook plus a deterministic Harness driver under `lib/`.
Treat that output as the starting contract, not the finished
connector.

Generated connectors still need:

- real provider or handler implementation
- real fixture expectations
- package-local docs
- optional live acceptance or proof code kept inside the connector package when
  appropriate
