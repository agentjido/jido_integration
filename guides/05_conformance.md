# Conformance

Conformance code lives in `jido_integration_conformance`.

Its job is to answer a narrow question:

does this connector package satisfy the control-plane contract described by the
repo today?

That contract is deterministic by default. Live-provider behavior is separate.

## Two Different Commands

There are two related commands in this repo, and they serve different purposes.

### `mix conformance`

From the repo root, `mix conformance` is an alias for:

```bash
mix test --only conformance
```

It runs the tests tagged with `:conformance`.

In this repo, that means:

- the root conformance test lane
- connector package conformance tests when run from that package and if they
  are included by that package's test run

This command is a test lane. It does not generate a structured connector report
for a specific module.

### `mix jido.conformance`

`mix jido.conformance` is the report-generating task.

Example:

```bash
mix jido.conformance Jido.Integration.Connectors.GitHub --profile bronze
```

It:

- loads one adapter module
- runs the conformance suites for the requested profile
- prints a summary or JSON report
- can write the full JSON report to a file
- exits with an error if the report fails

Use it when you want a connector-specific report instead of a test lane.

## Profiles

`Jido.Integration.Conformance.profiles/0` returns four profiles:

- `:mvp_foundation`
- `:bronze`
- `:silver`
- `:gold`

The profiles are cumulative.

### `:mvp_foundation`

Checks the minimum control-plane contract:

- `manifest`
- `security`
- `telemetry`
- `compliance_minimum`

It also includes the distributed-role suites in the report, but those are
normally `:skipped` unless the repo opts into the right roles.

Passing `:mvp_foundation` currently maps to bronze-tier eligibility in the
report.

### `:bronze`

Adds the bronze-level connector surface:

- `operations`
- `auth`
- `gateway`

This is the first profile that checks declared operations, auth descriptors,
and per-operation rate-limit declarations.

### `:silver`

Adds the parts of the contract that require richer connector definitions:

- `triggers`
- `determinism`

This is the profile that starts reading fixtures and checking declared trigger
metadata.

### `:gold`

`gold` currently runs the same suite set as `silver`.

That is the current code contract. There are no gold-only suites yet, so a
gold report is mainly a stricter eligibility label on top of the same current
suite set.

## Suites

The runner always emits the same suite list in the report, even when a suite is
skipped by profile or role gating.

### `manifest`

Checks:

- manifest ID presence and type
- display name and vendor presence
- domain validity
- semantic version validity
- quality-tier validity
- auth presence
- operations list shape
- capability keys and statuses if capabilities are declared

### `operations`

Checks every declared operation for:

- ID presence
- summary presence
- input schema presence
- output schema presence
- positive timeout
- error list shape

### `triggers`

Checks every declared trigger for:

- ID presence
- valid trigger class
- summary presence
- valid delivery semantics
- valid callback topology

### `auth`

Checks every auth descriptor for:

- ID presence
- valid auth type
- display name presence
- `secret_refs` list shape
- `scopes` list shape
- valid tenant binding

### `security`

Checks:

- adapter IDs are strings
- connector source does not call `String.to_atom/1`
- connector packages do not implement webhook verification directly
- runtime code does not read raw secrets from env or app config in the adapter
  source

### `gateway`

Checks:

- `Jido.Integration.Gateway.Policy.Default` is available
- every declared operation has a `rate_limit` value

### `determinism`

Reads every JSON fixture under the configured fixture directory.

Each fixture is executed through the control plane and compared against:

- `expected_output`, or
- `expected` path assertions

If no fixture directory is provided or no JSON fixtures are present, the suite
is skipped with `not_applicable: no_fixtures`.

### `telemetry`

Checks:

- `manifest.telemetry_namespace` starts with `jido.integration.`
- any manifest-advertised telemetry events are canonical standard events

This is what rejects legacy `dispatch_stub.*` telemetry from the public
contract.

### `compliance_minimum`

Checks declared operation errors against the taxonomy:

- error class is known
- retryability matches the default taxonomy mapping

### Role-Gated Suites

These suites are always present in the report but are skipped unless the repo
opts into distributed roles:

- `distributed_correctness`
- `artifact_transport`
- `policy_enforcement`

The allowed roles are:

- `:dispatch_consumer`
- `:run_aggregator`
- `:control_plane`

Without those roles, the runner reports `not_applicable: role_mismatch`.

In the current repo, `:dispatch_consumer` is a host-owned runtime role rather
than a default child of the root `:jido_integration` application. Opt into that
role when the host runtime actually wires and exercises a consumer.

## Report Shape

`Jido.Integration.Conformance.run/2` returns a map with:

- `connector_id`
- `connector_version`
- `profile`
- `runner_version`
- `suite_results`
- `pass_fail`
- `quality_tier_eligible`
- `evidence_refs`
- `exceptions_applied`
- `timestamp`
- `duration_ms`

Each suite result contains:

- `suite`
- `status`
- `checks`
- `duration_ms`
- `reason`

Each check contains:

- `name`
- `status`
- `message`

### Example JSON Shape

```json
{
  "connector_id": "github",
  "profile": "bronze",
  "pass_fail": "pass",
  "quality_tier_eligible": "bronze",
  "suite_results": [
    {
      "suite": "manifest",
      "status": "passed",
      "checks": [],
      "duration_ms": 1,
      "reason": null
    }
  ]
}
```

The actual report contains all suites, not just the one above.

## How To Read Failures

A failed report means one or more checks inside one or more suites returned
`status: :failed`.

The useful debugging path is:

1. look at failed suites first
2. then inspect failed checks inside those suites
3. treat skipped suites as informational unless you expected them to run

Examples of common failures:

- `security.webhook_verification_control_plane_only`
  The adapter implemented webhook verification itself. Move that logic into the
  control plane.
- `telemetry.event_valid.<event>`
  The manifest advertised a telemetry event that is not part of
  `Telemetry.standard_events/0`.
- `gateway.<operation>.rate_limit_declared`
  An operation is missing a `rate_limit` declaration.
- `determinism.<fixture>.json`
  The fixture output does not match the connector result.
- `compliance.<operation>.<class>_retryability_matches_taxonomy`
  The declared retryability does not match the shared error taxonomy.

You can also pull just the failed checks in Elixir with:

```elixir
report = Jido.Integration.Conformance.run(MyConnector, profile: :silver)
Jido.Integration.Conformance.failures(report)
```

## `mix jido.conformance` Options

The task supports:

- `--profile`
- `--output`
- `--json`
- `--format`

Examples:

```bash
mix jido.conformance Jido.Integration.Connectors.GitHub --profile bronze
mix jido.conformance Jido.Integration.Connectors.GitHub --profile silver --format json
mix jido.conformance Jido.Integration.Connectors.GitHub --profile bronze --output conformance_report.json
```

### `conformance.exs`

The task also reads an optional `conformance.exs` file from the current working
directory.

It can provide:

- `profile`
- `roles`
- `fixture_dir` or `fixtures_dir`

That is how a connector or repo can opt into role-gated suites or point the
runner at fixtures without spelling those options in every command.

## Factory Workflow Integration

The connector factory is designed around conformance from the start.

A generated package already includes:

- a valid manifest
- a placeholder operation
- adapter tests
- conformance tests
- a deterministic fixture

The intended workflow is:

1. scaffold with `mix jido.integration.new <connector>`
2. replace placeholder manifest data with the real contract
3. implement `run/3`
4. update fixtures
5. run `mix test`
6. run `mix jido.conformance ...`

That sequence is deliberate. Conformance should validate real connector
contracts, not act as an afterthought after provider code is already live.

## Root Test Lane Versus Connector Report

Use the commands for different reasons:

- `mix conformance`
  quick deterministic conformance-tagged test lane
- `mix jido.conformance`
  connector-specific report with suite and check detail

The first is good for CI stages and tag-based test selection.

The second is good when you need to inspect a connector module directly, export
JSON, or debug one failing connector without running the whole test suite.
