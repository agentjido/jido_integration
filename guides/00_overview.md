# Overview

`jido_integration` is the connector control plane for this monorepo.

It does not try to hide every provider behind one giant runtime abstraction.
Instead, it standardizes the parts that every connector eventually needs:

- manifest loading
- operation envelopes and result validation
- auth lifecycle ownership
- webhook ingress and replay protection
- admission control
- durable dispatch
- telemetry and conformance

The root package stays intentionally thin. Most of the behavior lives in the
packages under `packages/`, and the root package exposes:

- the public facade in `Jido.Integration`
- the top-level HexDocs guides
- deterministic examples and reference-app proofs
- end-to-end tests that exercise the package split together

## What Problem It Solves

Connectors usually start small and then accumulate the same control-plane
problems:

- how to declare what a connector can do
- how to validate requests before provider code runs
- how to route authenticated requests to the right tenant installation
- how to accept webhooks safely
- how to deduplicate and replay inbound events
- how to classify errors consistently
- how to observe runtime behavior without every connector inventing its own
  telemetry scheme

This repo gives those problems one shared implementation model.

Connector packages still own provider-specific logic:

- API request shapes
- provider error mapping
- provider manifests
- provider fixtures and live acceptance

The substrate owns the control-plane rules around that logic.

## What The System Looks Like

At a high level, the repo is built around three layers.

```text
Contracts -> Runtime -> Host
```

Those layers mean different things here than they do in a typical Phoenix app.

### Contracts

The contracts layer defines the shared language of the control plane.

It includes:

- `Adapter`
- `Manifest`
- `Operation.Envelope`
- `Operation.Result`
- `Trigger.Descriptor`
- `Webhook.Route`
- auth, dispatch, and webhook store behaviours
- `Gateway` and `Gateway.Policy`
- the normalized error taxonomy in `Error`
- the canonical event catalog in `Telemetry`

This layer is where connector packages and runtime packages agree on types and
behaviours.

### Runtime

The runtime layer executes the contracts durably.

It includes:

- `Auth.Server`
- `Registry`
- `Webhook.Router`
- `Webhook.Ingress`
- `Webhook.Dedupe`
- `Dispatch.Consumer`
- disk and ETS implementations for the durable store behaviours

This layer is where the repo turns abstract contracts into restart-safe control
plane behavior.

### Host

The host layer is the application embedding the runtime.

In this repo, the host role is demonstrated by:

- examples under `examples/`
- the active reference app under
  `reference_apps/devops_incident_response`

Hosts own:

- HTTP routing
- actor and tenant resolution
- choosing the correct runtime instance
- wiring stores, vaults, and secrets
- supervising and configuring `Dispatch.Consumer`
- deciding what callback module handles a dispatched trigger

Hosts do not own:

- install-session validation
- callback anti-replay rules
- connection lifecycle truth
- token refresh coordination
- scope gating semantics

Those stay inside `Auth.Server`.

The same boundary applies to dispatch. `Dispatch.Consumer` is part of the
runtime package, but the current repo treats it as host-owned infrastructure.
The root OTP application does not auto-start a default consumer. Hosts wire the
consumer explicitly so they can choose store adapters, retry policy, naming, and
callback registration strategy.

## The Public Entry Point

The root facade exposes a small API on purpose.

The main public entry points are:

- `Jido.Integration.execute/3`
- `Jido.Integration.lookup/1`
- `Jido.Integration.list_connectors/0`

Everything else in the repo is arranged around making those entry points safe
and predictable.

## Core Concepts

The guides use a few words very precisely.

### Adapter

An adapter is a module implementing `Jido.Integration.Adapter`.

It is the provider-specific boundary.

Every adapter must define:

- `id/0`
- `manifest/0`
- `validate_config/1`
- `health/1`

It can also define:

- `run/3`
- `handle_trigger/2`
- `init/1`

The adapter should not absorb control-plane duties that already belong to the
runtime. For example, webhook signature verification belongs in the control
plane, not in the connector package. The conformance suite checks for that.

### Manifest

A manifest is the control-plane source of truth for a connector.

`Jido.Integration.Manifest` declares:

- connector identity
- display name and vendor
- domain and version
- quality tier
- auth descriptors
- operations
- triggers
- capability declarations
- telemetry namespace
- optional config schema and extensions

The manifest is what the runtime consults before it allows an operation or
webhook path to proceed.

### Operation

An operation is an outbound connector action described in the manifest and
carried at runtime by `Operation.Envelope`.

An operation descriptor declares:

- operation ID
- summary
- input schema
- output schema
- declared errors
- idempotency requirements
- timeout
- rate-limit declaration
- required scopes

At execution time, an envelope wraps:

- the operation ID
- args
- trace context
- an optional idempotency key
- an optional timeout override
- an optional auth reference

### Trigger

A trigger is an inbound event source declared in the manifest.

Triggers model things such as:

- provider webhooks
- polling feeds
- scheduled sync sources
- streaming event sources

The current in-tree runtime is strongest on the webhook path. Trigger
descriptors still define the normalized contract for the broader event-ingress
surface.

### Auth

Auth in this repo is split deliberately.

`Auth.Server` owns runtime truth:

- credential storage
- connection lifecycle
- install-session issuance and consume-once callback acceptance
- token refresh coordination
- scope checks
- revocation and degradation transitions

`Auth.Bridge` is the host-facing contract around that engine.

Hosts implement `Auth.Bridge` when they want framework-specific controllers,
tenant resolution, or admin APIs without copying the lifecycle rules.

### Webhook

A webhook is the ingress shape the runtime accepts from a provider.

Webhook processing in this repo always passes through control-plane stages:

1. route resolution
2. signature verification
3. dedupe
4. trigger normalization
5. dispatch acceptance

That keeps ingress restart-safe and replayable.

### Gateway

The gateway is the admission-control layer for outbound operations.

It runs before connector code executes and returns one of three decisions:

- `:admit`
- `:backoff`
- `:shed`

Gateway policies let the control plane reject or delay work before a provider
request is attempted.

### Dispatch

Dispatch is the durable handoff from ingress acceptance to callback execution.

It uses two normalized records:

- `Dispatch.Record` for transport acceptance
- `Dispatch.Run` for callback execution attempts

The stable logical identities are:

- `dispatch_id` for transport acceptance
- `run_id` for callback execution state
- `idempotency_key` for durable duplicate binding back to an existing run

This is the main durability boundary for webhook-triggered work.

It is why ingress does not call connector trigger logic inline.

## Request Flow: Outbound Execution

The outbound execution path starts at `Jido.Integration.execute/3`.

The call shape looks like this:

```elixir
alias Jido.Integration.Operation

envelope =
  Operation.Envelope.new("github.fetch_issue", %{
    "owner" => "agentjido",
    "repo" => "jido_integration",
    "issue_number" => 1
  })

Jido.Integration.execute(
  Jido.Integration.Connectors.GitHub,
  envelope,
  auth_server: MyApp.AuthServer,
  connection_id: "conn_123"
)
```

The execution pipeline is:

1. Load the adapter manifest.
2. Resolve the operation descriptor by `operation_id`.
3. Validate the input payload against the declared input schema.
4. Validate auth options.
5. Require auth context if the operation declares required scopes.
6. Check scopes through `Auth.Server` or `Auth.Bridge`.
7. Apply gateway policy.
8. Resolve a credential or token when auth context is present.
9. Call the adapter's `run/3`.
10. Validate the adapter result against the declared output schema.
11. Wrap the result in `Operation.Result`.

Several design decisions fall out of that sequence.

### Validation Happens Before Provider Code

The substrate validates the request shape before the adapter runs. A connector
does not need to duplicate manifest-level input or output validation in every
`run/3` clause.

### Scope Gating Is Runtime-Owned

If an operation declares `required_scopes`, the caller must provide:

- `auth_server` and `connection_id`, or
- `auth_bridge` and `connection_id`

Otherwise execution fails with an auth error before the adapter runs.

### Gateway Policy Is Part Of Execution

The gateway is not a host-only concern bolted on afterward. It is part of the
control-plane path enforced by `Execution.execute/3`.

If no policy is supplied, execution defaults to
`Jido.Integration.Gateway.Policy.Default`.

### Token Resolution Is A Control-Plane Concern

If `auth_server` is present, execution can resolve a token through:

- an explicit `auth_ref`
- `envelope.auth_ref`
- a `connection_id` linked to a credential

That keeps token lookup and refresh coordination out of individual adapters.

## Webhook Flow: Inbound Ingress

The ingress path starts at `Webhook.Ingress.process/2`.

The runtime expects the host to provide:

- a router
- a dedupe store
- a dispatch consumer
- optionally an auth server or webhook secret

That `dispatch_consumer` requirement is intentional. The ingress path is
consumer-backed, but consumer supervision belongs to the host application rather
than the root `:jido_integration` supervisor.

A simplified call shape looks like this:

```elixir
Jido.Integration.Webhook.Ingress.process(
  %{
    install_id: "install_123",
    headers: %{
      "x-hub-signature-256" => "sha256=...",
      "x-github-delivery" => "delivery_123"
    },
    raw_body: raw_body,
    body: decoded_body,
    context: %{"trace_id" => "trace_123"}
  },
  router: router,
  dedupe: dedupe,
  dispatch_consumer: dispatch_consumer,
  auth_server: auth_server
)
```

The ingress pipeline is:

1. Emit `webhook.received` and `trigger.received`.
2. Resolve the route through `Webhook.Router`.
3. Resolve the verification secret directly or through `Auth.Server`.
4. Verify the signature.
5. Compute or read a dedupe key.
6. Reject duplicates through `Webhook.Dedupe`.
7. Resolve the adapter if needed.
8. Determine the trigger ID.
9. Normalize the request into `Trigger.Event`.
10. Convert that event into a dispatch record.
11. Hand the dispatch record to `Dispatch.Consumer`.
12. Mark the dedupe key as seen after successful acceptance.

The return from ingress is an acceptance result, not the result of the final
callback execution.

That distinction matters:

- ingress is durable
- callback execution is asynchronous
- failed runs can be replayed later

## Why Dispatch Exists

The dispatch consumer makes webhook handling durable.

When ingress accepts a trigger:

- a `Dispatch.Record` is written first
- a `Dispatch.Run` is created at acceptance
- execution happens asynchronously
- dead-lettered runs can be replayed with `Dispatch.Consumer.replay/2`

If any pre-ack store write fails, dispatch returns an error instead of claiming
success. The consumer does not acknowledge accepted work until the durable
acceptance writes complete.

The host owns the consumer process that performs that handoff. That keeps the
dispatch topology flexible while the repo is still proving what the right
default assembly should be for future host environments.

This gives the control plane:

- restart recovery
- idempotent acceptance
- dead-letter inspection
- replay
- direct dispatch and run inspection through consumer query APIs
- separate telemetry for transport and execution

## The Six In-Tree Packages

The repo is intentionally package-split.

### 1. `packages/core/contracts`

Owns the normalized language of the platform:

- manifests
- descriptors
- behaviours
- error taxonomy
- telemetry catalog
- execution pipeline helpers
- gateway contracts

This package is where connector code and runtime code agree on shapes.

### 2. `packages/core/runtime`

Owns the durable implementations:

- `Auth.Server`
- `Registry`
- webhook router, dedupe, and ingress
- dispatch consumer
- local disk and ETS store implementations

This package is where lifecycle state becomes restart-safe behavior.

### 3. `packages/core/conformance`

Owns connector validation:

- conformance profiles
- suite definitions
- the `mix jido.conformance` task

This package is what turns the contracts into a repeatable quality gate.

### 4. `packages/core/factory`

Owns connector scaffolding:

- `mix jido.integration.new`

It creates the initial package or core-layout files for a new connector and
seeds them with a deterministic placeholder operation and conformance tests.

### 5. `packages/core/http_common`

Owns shared HTTP support when the repo needs it.

In the current tree, the package exists and is wired as a dependency, but it
does not yet expose any `lib/**/*.ex` modules.

### 6. `packages/connectors/github`

Owns the first in-tree provider connector:

- the GitHub adapter
- its default HTTP client
- deterministic package tests
- env-gated live acceptance

It is both a usable connector and the reference package layout for future
providers.

## What Is Shipped Today

The docs should stay aligned with the code and tests.

Shipped and exercised now:

- deterministic root tests
- deterministic examples
- deterministic incident-response reference app
- durable auth install and callback correlation
- durable webhook ingress and dispatch
- GitHub connector package tests
- opt-in live GitHub acceptance

Not shipped as a first-class end-user flow:

- public browser-based OAuth onboarding from the internet
- public tunnel-backed GitHub webhook delivery runbooks
- finished `sales_pipeline` reference-app proof
- generalized distributed artifact transport

When a guide mentions one of those future paths, it should be explicit that the
path is not yet finished in-tree.

## Where To Read Next

After this overview, the most useful next guides are:

- `guides/01_architecture.md` for the subsystem boundaries
- `guides/02_package_layout.md` for the package split and dependency flow
- `guides/03_runtime_and_durability.md` for the store contracts and restart
  behavior
- `guides/04_connector_factory.md` if you are creating a connector
- `guides/05_conformance.md` if you are validating a connector
- `guides/06_reference_apps.md` for the current host-level proofs
- `guides/07_live_examples.md` for the GitHub live runbook
- `guides/08_operations_and_release.md` for deterministic release gates

If you only need one rule to orient the repo, use this one:

keep provider-specific behavior in connector packages, and keep control-plane
truth in the shared runtime.
