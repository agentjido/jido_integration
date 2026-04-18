# Architecture

Jido Integration is organized as a set of explicit packages with one public
facade, several runtime and durability layers, dedicated bridge packages,
isolated connector packages, and top-level proof apps.

If you are consuming the platform, the main idea is simple:

- use `core/platform` through `Jido.Integration.V2`
- choose connector packages for the capabilities you want to publish
- add durability and hosted webhook or async packages only when your host needs
  them

The workspace root coordinates docs, tests, and scaffolding. It is not where
runtime behavior lives.

## Package Boundaries

- `core/contracts` defines the public IR, behaviours, projection rules, and
  the shared inference contract seam.
- `core/brain_ingress` owns the durable brain-to-lower-gateway intake seam, including
  submission acceptance, governance-shadow verification, and logical scope
  resolution before runtime execution.
- `core/platform` exposes the stable public facade `Jido.Integration.V2`,
  including raw authored catalog summaries and the projected common consumer
  catalog export plus live inference invocation, durable operator reads, and
  review projection over durable truth.
- `core/auth` owns installs, credentials, connection truth, and leases.
- `core/control_plane` owns runs, attempts, events, triggers, artifacts,
  target truth, the local `ReqLLMCallSpec`, live inference execution, and the
  durable inference event minimum.
- `core/consumer_surfaces` owns generated common action, sensor, and plugin
  runtime support.
- `core/direct_runtime` handles direct provider-SDK execution.
- `core/runtime_router` owns the authored non-direct adapter and session
  reuse boundary above Runtime Control.
- `core/asm_runtime_bridge` projects the authored `asm` driver into Runtime Control.
- `core/session_runtime` owns the integration-managed `jido_session` driver
  implementation consumed by the runtime router.
- `core/dispatch_runtime` handles async transport, retry, replay, and recovery.
- `core/ingress` normalizes triggers and admits them into the control plane.
- `core/webhook_router` owns hosted route registration and route resolution.
- `core/policy` decides whether work is admitted, denied, or shed.
- `core/store_local` and `core/store_postgres` implement the explicit
  durability tiers, including submission-ledger adapters for
  `core/brain_ingress`.

Connector packages stay isolated and package-owned. Proof apps compose those
packages without reclaiming platform ownership.

`apps/inference_ops` is the permanent app-level proof home for the first live
inference runtime family.

## Runtime Boundary

The repo keeps a hard split between direct SDK execution and runtime-control-backed
execution.

`Jido.Integration.V2 -> DirectRuntime -> connector -> provider SDK -> pristine`

`Jido.Integration.V2 -> RuntimeRouter -> Jido.RuntimeControl -> {asm | jido_session}`

Direct connectors stay on the provider SDK path. Only actual `:session` and
`:stream` capabilities use `Jido.RuntimeControl`.

`core/runtime_router` is the package boundary that translates authored runtime
metadata into Runtime Control execution. `asm` stays behind `core/asm_runtime_bridge`.
`jido_session` stays behind `core/session_runtime`.

The active core runtime graph stops there. Legacy lower-boundary bridge code is
not part of the default workspace CI or the active dependency path for those
two runtime packages.

Inference stays on a separate seam:

`Jido.Integration.V2 -> ControlPlane.Inference -> req_llm -> {cloud provider | self-hosted OpenAI-compatible endpoint}`

For self-hosted execution, endpoint publication remains below the control plane:

`Jido.Integration.V2 -> ControlPlane.Inference -> self_hosted_endpoint_provider -> self_hosted_inference_core -> llama_cpp_sdk`

## Execution Plane Contract Carriage

The lower-boundary contract packet is now frozen above this repo even though
the broad runtime extraction is not yet complete.

`jido_integration` stays the lower acceptance gateway:

- it carries `AuthorityDecision.v1` as Brain-authored direction
- it owns durable `BoundarySessionDescriptor.v1`
- it projects `ExecutionIntentEnvelope.v1` plus family-specific lower intents
- it owns durable `ExecutionRoute.v1`, attach-grant issuance, replay,
  approvals, and outcome interpretation
- it keeps durable service descriptor, lease lineage, and attachability truth
  above lower process state for self-hosted runtime families
- it consumes `ExecutionEvent.v1` and `ExecutionOutcome.v1` as raw execution
  facts rather than turning lower runtime state into durable truth

The public product surface here remains `Jido.Integration.V2` plus the current
`core/contracts` seam. This repo may carry Execution Plane contracts, but it
must not re-export raw `execution_plane/*` packages as the platform API.

That means northbound operator products should use this repo for durable run,
boundary-session, attach-grant, auth, target, retry, and review truth, while
continuing to use `execution_plane` for hot-path attach, PTY, and transport
mechanics.

Durable brain-to-lower-gateway carriage also stays on that same ownership split:

- `core/contracts` owns the canonical JSON, audit envelope, submission
  identity, and governance projection contracts
- `core/brain_ingress` verifies those contracts, resolves logical scope refs,
  and records durable acceptance or typed rejection before runtime policy
  evaluation continues
- storage packages own the concrete durable ledger backends, not the workspace
  root

The minimal-lane interiors for `HttpExecutionIntent.v1`,
`ProcessExecutionIntent.v1`, and `JsonRpcExecutionIntent.v1` remain
provisional until Wave 3 prove-out. Wave 1 freezes the carrier names, lineage,
ownership, and surface rules only.

## Consumer Surface Boundary

The authored connector catalog and the published generated consumer surface are
not the same thing.

- connector-local inventory may stay authored and callable without becoming a
  shared generated surface
- only explicit `consumer_surface.mode: :common` operations and triggers
  project into generated actions, sensors, and plugins
- `core/platform` exposes that projected view through
  `projected_catalog_entries/0`
- `core/consumer_surfaces` owns the generated runtime support for those common
  surfaces
- hosted webhook proofs may stay app-local while still converging on the same
  generated sensor contract family as common poll-backed triggers

## Durability Boundary

Durability is explicit and opt-in.

- `core/auth` and `core/control_plane` can run in-memory by default.
- `core/store_local` gives restart-safe single-node durability.
- `core/store_postgres` gives the canonical shared durable tier.

The root never owns the store implementation itself; it only wires the package
that the host wants.

## Inference Runtime

The live inference runtime stays inside the existing package boundaries:

- `core/contracts` owns the shared contract seam
- `core/control_plane` owns route resolution, `req_llm` execution, and durable
  inference attempt truth
- `core/platform` owns the public `invoke_inference/2` and operator-facing
  review projection
- `apps/inference_ops` owns the hosted proof app

No new root runtime lane or separate contracts repo is introduced.
