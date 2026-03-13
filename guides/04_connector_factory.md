# Connector Factory

Connector scaffolding lives in `jido_integration_factory`.

The entry point is:

```bash
mix jido.integration.new <connector_name>
```

For example:

```bash
mix jido.integration.new acme_crm
```

By default, that generates a standalone connector package under
`packages/connectors/<connector_name>`.

## Supported Layouts

The task supports two layouts.

### Package Layout

Default command:

```bash
mix jido.integration.new acme_crm
```

This writes a full package under `packages/connectors/acme_crm`.

### Core Layout

Core-layout command:

```bash
mix jido.integration.new acme_crm --layout core
```

This writes adapter files directly into the current project instead of creating
a package `mix.exs`.

Use core layout only when the connector truly belongs inside an existing app.
For this monorepo, package layout is the normal path.

## Exact Scaffold Output

The task summary printed by the generator includes the real file list. For the
default `acme_crm` package layout, the generated files are:

```text
packages/connectors/acme_crm/mix.exs
packages/connectors/acme_crm/README.md
packages/connectors/acme_crm/test/test_helper.exs
packages/connectors/acme_crm/lib/jido/integration/connectors/acme_crm.ex
packages/connectors/acme_crm/priv/jido/integration/connectors/acme_crm/manifest.json
packages/connectors/acme_crm/test/jido/integration/connectors/acme_crm_test.exs
packages/connectors/acme_crm/test/jido/integration/connectors/acme_crm_conformance_test.exs
packages/connectors/acme_crm/test/fixtures/acme_crm/success.json
```

That file list is verified by the task output and by
`test/mix/tasks/jido_integration_new_test.exs`.

## What Each Generated File Does

### `mix.exs`

Creates a standalone package app:

- app name `:jido_integration_acme_crm`
- path dependency on `{:jido_integration, path: "../../.."}` when scaffolded
  in-tree
- `preferred_cli_env` for the `conformance` alias

### `README.md`

Seeds a minimal package README with:

- connector module name
- deterministic development commands
- a starter `mix jido.conformance ...` command

### `test/test_helper.exs`

Starts ExUnit with `exclude: [:skip]`.

### `lib/jido/integration/connectors/acme_crm.ex`

Creates the adapter module.

The default scaffold includes:

- `@behaviour Jido.Integration.Adapter`
- `id/0`
- `manifest/0`
- `validate_config/1`
- `health/1`
- a placeholder `run/3` for `acme_crm.hello`
- an `unsupported` fallback clause

The placeholder operation simply echoes a message. That keeps the first test
and conformance run deterministic.

### `priv/jido/integration/connectors/acme_crm/manifest.json`

Creates a bronze-tier manifest with:

- connector ID and display metadata
- a `none` auth descriptor
- one placeholder operation: `acme_crm.hello`
- `rate_limit: "gateway_default"`
- `telemetry_namespace: "jido.integration.acme_crm"`

The factory does not guess provider-specific operations. You must replace the
placeholder manifest content with the real connector contract.

### `test/jido/integration/connectors/acme_crm_test.exs`

Creates deterministic adapter tests for:

- `id/0`
- `manifest/0`
- `validate_config/1`
- `health/1`
- placeholder operation behavior
- execution through `Jido.Integration.execute/3`

### `test/jido/integration/connectors/acme_crm_conformance_test.exs`

Creates conformance coverage for:

- `:mvp_foundation`
- `:bronze`
- `:silver`

The silver check points at the generated fixture directory so the scaffold
passes determinism once the placeholder operation still matches the fixture.

### `test/fixtures/acme_crm/success.json`

Creates a deterministic fixture describing:

- `operation_id`
- input
- expected output

That fixture is what lets the generated package pass the silver determinism
suite immediately.

## The Scaffolded `acme_crm` Walkthrough

The generated `acme_crm` package is intentionally simple. It shows the expected
workflow without pretending to know your provider API yet.

### Step 1: Generate The Package

```bash
mix jido.integration.new acme_crm
```

### Step 2: Read The Placeholder Contract

The generated manifest declares one operation:

```json
{
  "id": "acme_crm.hello",
  "summary": "Placeholder operation"
}
```

The generated adapter implements that operation with a trivial echo response.

That placeholder exists for one reason: the scaffold should compile, test, and
run conformance immediately.

### Step 3: Replace The Placeholder Manifest

Your real work starts in `priv/jido/integration/connectors/acme_crm/manifest.json`.

Replace the placeholder operation list with the real provider contract:

- add real operation IDs
- add input and output schemas
- declare required scopes
- declare error classes and retryability correctly
- add triggers if the connector has inbound events
- replace `none` auth with the real auth descriptors

### Step 4: Implement `run/3`

Then update `lib/jido/integration/connectors/acme_crm.ex` so `run/3` handles
every declared operation.

The workflow should stay one-way:

1. define the manifest contract first
2. implement `run/3` to satisfy that contract
3. keep unsupported operations returning normalized `Error` values

### Step 5: Update Fixtures

Once the real operations exist, replace the placeholder fixture with provider-
specific deterministic fixtures.

The conformance runner reads every JSON fixture under:

```text
test/fixtures/acme_crm/
```

Each fixture should include:

- `operation_id`
- `input`
- `expected_output`, or
- `expected` path assertions

### Step 6: Run Tests

From the package root:

```bash
cd packages/connectors/acme_crm
mix test
```

That should keep the connector deterministic by default.

### Step 7: Run Conformance

From the package root:

```bash
cd packages/connectors/acme_crm
mix jido.conformance Jido.Integration.Connectors.AcmeCrm --profile bronze
```

Once fixtures are in place, run silver:

```bash
cd packages/connectors/acme_crm
mix jido.conformance Jido.Integration.Connectors.AcmeCrm --profile silver
```

## Recommended Post-Scaffold Workflow

After generation, the expected sequence is:

1. define operations and auth in the manifest
2. implement adapter `run/3`
3. add or update deterministic fixtures
4. run `mix test`
5. run `mix jido.conformance ...`
6. add any live acceptance only after the deterministic path is stable

The scaffold is intentionally strict about that order. It nudges connector work
toward a manifest-first, deterministic-first workflow.

## Adding The Connector As A Dependency

The generated package is independent, but no existing app will compile or load
it automatically until you add it as a dependency.

In this monorepo, that usually means adding a path dependency in the consuming
app:

```elixir
defp deps do
  [
    {:jido_integration, path: "../jido_integration"},
    {:jido_integration_acme_crm, path: "../jido_integration/packages/connectors/acme_crm"}
  ]
end
```

If the consumer lives inside this repo, the relative path may differ, but the
pattern stays the same: add the connector package explicitly where it will be
compiled and started.

After that, register the adapter at runtime or look it up from whatever host
boot path you use.

## Customizing The Scaffold

The generator supports a few useful flags:

```bash
mix jido.integration.new my_saas --module MyApp.Connectors.MySaas
mix jido.integration.new my_saas --domain saas
mix jido.integration.new my_ai --layout core --path lib/custom/adapter.ex
```

`--module` changes the module name.

`--domain` seeds the manifest domain.

`--layout core` writes adapter files into the current project instead of a new
package.

## What The Factory Does Not Do

The factory does not:

- invent provider operations for you
- generate a production HTTP client
- create host-specific `Auth.Bridge` code
- wire the new package into root docs or release automation
- add live acceptance scripts automatically

Those steps remain deliberate follow-on work.
