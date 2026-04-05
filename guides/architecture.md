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
- `core/platform` exposes the stable public facade `Jido.Integration.V2`,
  including raw authored catalog summaries and the projected common consumer
  catalog export plus live inference invocation and review projection over
  durable truth.
- `core/auth` owns installs, credentials, connection truth, and leases.
- `core/control_plane` owns runs, attempts, events, triggers, artifacts,
  target truth, the local `ReqLLMCallSpec`, live inference execution, and the
  durable inference event minimum.
- `core/consumer_surfaces` owns generated common action, sensor, and plugin
  runtime support.
- `core/direct_runtime` handles direct provider-SDK execution.
- `core/harness_runtime` owns the authored non-direct adapter and session
  reuse boundary above Harness.
- `core/runtime_asm_bridge` projects the authored `asm` driver into Harness.
- `core/session_runtime` owns the integration-managed `jido_session` driver
  implementation consumed by the harness adapter.
- `core/dispatch_runtime` handles async transport, retry, replay, and recovery.
- `core/ingress` normalizes triggers and admits them into the control plane.
- `core/webhook_router` owns hosted route registration and route resolution.
- `core/policy` decides whether work is admitted, denied, or shed.
- `core/store_local` and `core/store_postgres` implement the explicit
  durability tiers.

Connector packages stay isolated and package-owned. Proof apps compose those
packages without reclaiming platform ownership.

`apps/inference_ops` is the permanent app-level proof home for the first live
inference runtime family.

## Runtime Boundary

The repo keeps a hard split between direct SDK execution and Harness-backed
execution.

`Jido.Integration.V2 -> DirectRuntime -> connector -> provider SDK -> pristine`

`Jido.Integration.V2 -> HarnessRuntime -> Jido.Harness -> {asm | jido_session}`

Direct connectors stay on the provider SDK path. Only actual `:session` and
`:stream` capabilities use `Jido.Harness`.

`core/harness_runtime` is the package boundary that translates authored runtime
metadata into Harness execution. `asm` stays behind `core/runtime_asm_bridge`.
`jido_session` stays behind `core/session_runtime`.

The active core runtime graph stops there. Legacy lower-boundary bridge code is
not part of the default workspace CI or the active dependency path for those
two runtime packages.

Inference stays on a separate seam:

`Jido.Integration.V2 -> ControlPlane.Inference -> req_llm -> {cloud provider | self-hosted OpenAI-compatible endpoint}`

For self-hosted execution, endpoint publication remains below the control plane:

`Jido.Integration.V2 -> ControlPlane.Inference -> self_hosted_inference_core -> llama_cpp_ex`

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
- `apps/inference_ops` owns the hosted proof harness

No new root runtime lane or separate contracts repo is introduced.
