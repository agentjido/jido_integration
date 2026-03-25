# Architecture

Jido Integration is a tooling-root monorepo, not an umbrella application.
The root exists to coordinate docs, tests, and workspace tasks. The real
surfaces live in `core/`, `connectors/`, and `apps/`.

## Package Boundaries

- `core/contracts` defines the public IR, behaviours, and projection rules.
- `core/platform` exposes the stable public facade `Jido.Integration.V2`,
  including raw authored catalog summaries and the projected common consumer
  catalog export.
- `core/auth` owns installs, credentials, connection truth, and leases.
- `core/control_plane` owns runs, attempts, events, triggers, artifacts, and
  target truth.
- `core/direct_runtime` handles direct provider-SDK execution.
- `core/runtime_asm_bridge` projects the authored `asm` driver into Harness.
- `core/dispatch_runtime` handles async transport, retry, replay, and recovery.
- `core/ingress` normalizes triggers and admits them into the control plane.
- `core/webhook_router` owns hosted route registration and route resolution.
- `core/policy` decides whether work is admitted, denied, or shed.
- `core/store_local` and `core/store_postgres` implement the explicit
  durability tiers.

## Runtime Boundary

The repo keeps a hard split between direct SDK execution and Harness-backed
execution.

`Jido.Integration.V2 -> DirectRuntime -> connector -> provider SDK -> pristine`

`Jido.Integration.V2 -> HarnessRuntime -> Jido.Harness -> {asm | jido_session}`

Direct connectors stay on the provider SDK path. Only actual `:session` and
`:stream` capabilities use `Jido.Harness`.

## Consumer Surface Boundary

The authored connector catalog and the published generated consumer surface are
not the same thing.

- connector-local inventory may stay authored and callable without becoming a
  shared generated surface
- only explicit `consumer_surface.mode: :common` operations and triggers
  project into generated actions, sensors, and plugins
- `core/platform` exposes that projected view through
  `projected_catalog_entries/0`
- hosted webhook proofs may stay app-local while still converging on the same
  generated sensor contract family as common poll-backed triggers

## Durability Boundary

Durability is explicit and opt-in.

- `core/auth` and `core/control_plane` can run in-memory by default.
- `core/store_local` gives restart-safe single-node durability.
- `core/store_postgres` gives the canonical shared durable tier.

The root never owns the store implementation itself; it only wires the package
that the host wants.
