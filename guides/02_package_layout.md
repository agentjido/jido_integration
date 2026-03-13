# Package Layout

The repo is intentionally split into small packages instead of keeping all
connector, runtime, and tooling code in one application.

That split is visible under `packages/`.

## Top-Level Shape

At the repo root:

- `lib/`
  thin public facade and application entrypoint
- `guides/`
  HexDocs guide extras
- `examples/`
  deterministic substrate examples
- `reference_apps/`
  host-level proving slices
- `packages/core/`
  shared runtime and tooling packages
- `packages/connectors/`
  in-tree connector packages
- `test/`
  root integration, contract, and package-split tests

The root package composes the packages together and keeps the docs and
end-to-end proofs in one place.

## Dependency Flow

The in-tree package graph is:

```text
jido_integration (root)
  -> jido_integration_contracts
  -> jido_integration_runtime
  -> jido_integration_conformance
  -> jido_integration_factory
  -> jido_integration_http_common

jido_integration_runtime
  -> jido_integration_contracts

jido_integration_conformance
  -> jido_integration_contracts

jido_integration_factory
  -> no in-repo packages

jido_integration_http_common
  -> jido_integration_contracts

jido_integration_github
  -> jido_integration
```

Some planning notes describe a slightly different dependency story, but the
current `mix.exs` files above are the real contract.

Notable details:

- `contracts` is the foundation package for shared types and behaviours
- `runtime` depends on `contracts`
- `conformance` currently depends on `contracts`, not `runtime`
- `factory` currently has no in-repo dependency
- `http_common` depends on `contracts` but is currently empty
- the GitHub connector depends on the root package so it can use the full
  facade and runtime stack together

## Root Package

The root package is `:jido_integration`.

It contains only:

- `Jido.Integration`
- the application entrypoint module in `lib/jido/integration/application.ex`

The application entrypoint starts the default runtime children:

- `Jido.Integration.Registry`
- `Jido.Integration.Auth.Server`
- `Jido.Integration.Webhook.Router`
- `Jido.Integration.Webhook.Dedupe`

It intentionally does not start `Jido.Integration.Dispatch.Consumer`.
`Dispatch.Consumer` is currently host-owned infrastructure so applications can
choose topology, store adapters, retry policy, and callback registration
explicitly.

The root package also owns:

- the HexDocs extras configuration
- the deterministic examples
- the reference-app proofs
- the repo-wide deterministic and conformance-tagged tests

## `packages/core/contracts`

App name: `:jido_integration_contracts`

In-repo dependencies: none

External dependencies:

- `:jason`
- `:nimble_options`
- `:telemetry`
- `:ex_json_schema`

This is the contract package. It defines the shapes every other package relies
on.

### Modules

Core control-plane modules:

- `Jido.Integration.Adapter`
- `Jido.Integration.Manifest`
- `Jido.Integration.Capability`
- `Jido.Integration.Schema`
- `Jido.Integration.Error`
- `Jido.Integration.Telemetry`
- the internal execution helper in `packages/core/contracts/lib/jido/integration/execution.ex`
- `Jido.Integration.Gateway`
- `Jido.Integration.Gateway.Policy`
- `Jido.Integration.Gateway.Policy.Default`
- `Jido.Integration.Gateway.Policy.RateLimit`

Auth modules:

- `Jido.Integration.Auth`
- `Jido.Integration.Auth.Bridge`
- `Jido.Integration.Auth.Connection`
- `Jido.Integration.Auth.ConnectionStore`
- `Jido.Integration.Auth.Credential`
- `Jido.Integration.Auth.Descriptor`
- `Jido.Integration.Auth.InstallSession`
- `Jido.Integration.Auth.InstallSessionStore`
- `Jido.Integration.Auth.Store`

Operation modules:

- `Jido.Integration.Operation`
- `Jido.Integration.Operation.Descriptor`
- `Jido.Integration.Operation.Envelope`
- `Jido.Integration.Operation.Result`

Trigger and webhook modules:

- `Jido.Integration.Trigger`
- `Jido.Integration.Trigger.Descriptor`
- `Jido.Integration.Trigger.Event`
- `Jido.Integration.Webhook.Route`
- `Jido.Integration.Webhook.RouteStore`
- `Jido.Integration.Webhook.DedupeStore`

Dispatch modules:

- `Jido.Integration.Dispatch`
- `Jido.Integration.Dispatch.Record`
- `Jido.Integration.Dispatch.Run`
- `Jido.Integration.Dispatch.Store`
- `Jido.Integration.Dispatch.RunStore`

### Behaviours Defined Here

`contracts` defines the main extensibility points:

- `Adapter`
- `Auth.Bridge`
- `Auth.Store`
- `Auth.ConnectionStore`
- `Auth.InstallSessionStore`
- `Gateway.Policy`
- `Dispatch.Store`
- `Dispatch.RunStore`
- `Webhook.RouteStore`
- `Webhook.DedupeStore`

For dispatch durability specifically:

- `Dispatch.Store` freezes `dispatch_id`-addressable transport records and
  filtered recovery queries
- `Dispatch.RunStore` freezes `run_id`-addressable execution records plus
  durable `idempotency_key` lookup and conflict detection

### Why It Matters

If a package or app wants to speak the Jido integration control plane, this is
the package it must compile against.

## `packages/core/runtime`

App name: `:jido_integration_runtime`

In-repo dependencies:

- `:jido_integration_contracts`

This package turns the contract behaviours into working runtime processes and
local durable adapters.

### Modules

Runtime services:

- `Jido.Integration.Auth.Server`
- `Jido.Integration.Registry`
- `Jido.Integration.Webhook.Router`
- `Jido.Integration.Webhook.Ingress`
- `Jido.Integration.Webhook.Dedupe`
- `Jido.Integration.Dispatch.Consumer`
- the internal runtime persistence helper in
  `packages/core/runtime/lib/jido/integration/runtime/persistence.ex`

`Dispatch.Consumer` lives in `runtime`, but the root package does not supervise
it by default. The reference app and examples start it from the host layer.

The runtime implementations now expose the store-side query surface the consumer
needs for recovery and operator inspection:

- filtered dispatch listing by status and scope
- filtered run listing by status and scope
- durable run lookup by `idempotency_key`

Auth store implementations:

- `Jido.Integration.Auth.Store.Disk`
- `Jido.Integration.Auth.Store.ETS`
- `Jido.Integration.Auth.ConnectionStore.Disk`
- `Jido.Integration.Auth.ConnectionStore.ETS`
- `Jido.Integration.Auth.InstallSessionStore.Disk`
- `Jido.Integration.Auth.InstallSessionStore.ETS`

Dispatch store implementations:

- `Jido.Integration.Dispatch.Store.Disk`
- `Jido.Integration.Dispatch.Store.ETS`
- `Jido.Integration.Dispatch.RunStore.Disk`
- `Jido.Integration.Dispatch.RunStore.ETS`

Webhook store implementations:

- `Jido.Integration.Webhook.RouteStore.Disk`
- `Jido.Integration.Webhook.RouteStore.ETS`
- `Jido.Integration.Webhook.DedupeStore.Disk`
- `Jido.Integration.Webhook.DedupeStore.ETS`

### Behaviours Implemented Here

This package implements the store behaviours defined in `contracts` and owns the
GenServer processes that operate on them.

### Why It Matters

This is the package to read if you need to understand:

- where durability boundaries sit
- how callback recovery works after restart
- how webhook routing and dedupe are performed
- how `Auth.Server` persists state across installs, callbacks, and refreshes

## `packages/core/conformance`

App name: `:jido_integration_conformance`

In-repo dependencies:

- `:jido_integration_contracts`

External dependencies:

- `:jason`

This package owns connector-quality validation.

### Modules

- `Jido.Integration.Conformance`
- `Mix.Tasks.Jido.Conformance`

### What It Defines

`Jido.Integration.Conformance` defines:

- conformance profiles
- suite membership by profile
- role-gated suites
- report generation
- fixture-driven determinism checks

`Mix.Tasks.Jido.Conformance` provides the report-generating Mix task.

### Why It Matters

Connector packages use this package to verify that:

- their manifest is coherent
- operations and triggers are declared correctly
- security and telemetry contracts are respected
- fixture-based deterministic behavior holds

## `packages/core/factory`

App name: `:jido_integration_factory`

In-repo dependencies: none

External dependencies:

- `:jason`

This package owns connector scaffolding.

### Modules

- `Mix.Tasks.Jido.Integration.New`

### What It Generates

The task can generate:

- a standalone connector package layout
- a core-layout adapter living directly in an existing codebase

It writes:

- a manifest
- an adapter module
- adapter tests
- conformance tests
- deterministic fixtures

For package layout, it also writes:

- `mix.exs`
- `README.md`
- `test/test_helper.exs`

### Why It Matters

This package is the fastest path to a connector that already speaks the control
plane correctly enough to run tests and conformance from day one.

## `packages/core/http_common`

App name: `:jido_integration_http_common`

In-repo dependencies:

- `:jido_integration_contracts`

Current `lib/` modules: none

This package exists as a placeholder for shared HTTP helpers, but the current
tree does not expose any library modules from it yet.

That is worth documenting explicitly because it means:

- there is no hidden shared HTTP abstraction to learn today
- connector packages currently own their client adapters directly
- future HTTP reuse should land here instead of leaking into `contracts` or
  `runtime`

## `packages/connectors/github`

App name: `:jido_integration_github`

In-repo dependencies:

- `:jido_integration`

External dependencies:

- `:jason`
- optional `:req`

This package is the first in-tree connector package and the best concrete
example of how a connector should be structured.

### `lib/` Modules

- `Jido.Integration.Connectors.GitHub`
- `Jido.Integration.Connectors.GitHub.DefaultClient`

### Package Structure Around `lib/`

The package also contains:

- `priv/jido/integration/connectors/github/manifest.json`
- `examples/` for live examples
- `test/` for deterministic and env-gated tests
- `scripts/live_acceptance.sh`
- `README.md`

### What It Owns

The GitHub adapter owns:

- GitHub issue and comment operations
- GitHub-specific manifest data
- GitHub HTTP request and error mapping
- env-gated live acceptance

It does not reimplement runtime auth, webhook ingress, or dispatch durability.

## Connector Package Structure Pattern

Using GitHub as the reference, a connector package typically looks like:

```text
packages/connectors/<provider>/
  mix.exs
  README.md
  lib/jido/integration/connectors/<provider>.ex
  priv/jido/integration/connectors/<provider>/manifest.json
  test/test_helper.exs
  test/jido/integration/connectors/<provider>_test.exs
  test/jido/integration/connectors/<provider>_conformance_test.exs
  test/fixtures/<provider>/
  examples/
  scripts/
```

Not every connector will need `examples/` or `scripts/`, but the package split
is designed to make those additions natural.

## Where The Factory Fits

`packages/core/factory` generates the initial version of the structure above.

The scaffold does not register the connector automatically in the root package
or add it to docs groups. It only creates the connector package or adapter
files.

That separation is deliberate:

- scaffolding creates connector code
- package wiring remains an explicit maintainer decision

## Reading Order

If you are orienting yourself by package:

1. start with `contracts`
2. read `runtime`
3. read `conformance`
4. inspect `factory`
5. use `connectors/github` as the concrete example

That order mirrors the dependency graph and avoids learning the repo backwards.
