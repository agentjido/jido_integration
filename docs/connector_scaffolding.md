# Connector Authoring And Scaffolding

Connector generation stays in the workspace root because the root owns
monorepo layout and package naming concerns. Connector implementation stays in
the generated child package.

The entry point is:

```bash
mix jido.integration.new <connector_name>
```

Example commands:

```bash
mix jido.integration.new acme_crm
mix jido.integration.new custom_ai --module MyApp.Connectors.CustomAi --package-name "Custom AI Connector"
mix jido.integration.new analyst_cli --runtime-class session --runtime-driver asm
mix jido.integration.new market_feed --runtime-class stream --runtime-driver asm
```

## Choose The Runtime Class First

The runtime model still distinguishes:

- `direct`
- `session`
- `stream`

Pick the runtime class based on the connector contract you intend to publish:

- `direct`
  - one request maps to one bounded execution
- `session`
  - execution should reuse a provider-managed session
- `stream`
  - execution should reuse a provider-managed stream reference or cursor

The workspace scaffold supports all three runtime classes, but non-direct
packages require an explicit Harness runtime-driver selection. The scaffold
only emits the intended non-direct driver ids and does not invent a legacy
bridge default.

Accepted non-direct runtime drivers are:

- `asm`
- `jido_session`

Rules:

- `direct`
  - do not pass `--runtime-driver`
- `session`
  - `--runtime-driver` is required
  - supported drivers: `asm`, `jido_session`
- `stream`
  - `--runtime-driver` is required
  - supported drivers: `asm`

Hosted webhook routing is not a runtime class. If the proof depends on route
registration, secret resolution, or async transport, keep that proof in an app
or package above the connector rather than forcing it into the scaffold.

## Name The Runtime Basis In This Order

When documenting or reviewing a non-direct connector, describe the stack in
this order:

1. `/home/home/p/g/n/jido_harness` exposes `Jido.Harness`, the stable
   runtime-driver contract referenced by `runtime.driver`
2. `runtime.driver: "asm"` selects
   `Jido.Integration.V2.RuntimeAsmBridge.HarnessDriver` in
   `/home/home/p/g/n/jido_integration`.
3. `runtime.driver: "jido_session"` selects `Jido.Session.HarnessDriver` in
   `/home/home/p/g/n/jido_integration/core/session_runtime`.
4. Only the `asm` branch projects further into provider-neutral
   `/home/home/p/g/n/agent_session_manager`, which itself uses
   `/home/home/p/g/n/cli_subprocess_core` for subprocess, event, and provider
   profile foundations.

Connector packages should usually stop their direct dependencies at
`/home/home/p/g/n/jido_harness`. Do not add `core/session_runtime`,
`/home/home/p/g/n/agent_session_manager`, or
`/home/home/p/g/n/cli_subprocess_core` directly to session or stream connector
packages just to restate the shared runtime basis.

`metadata.runtime_family.runtime_ref` names the stable public Harness handle,
not the runtime class itself. A `:stream` capability may still publish
`runtime_ref: :session` when the selected Harness driver exposes session-scoped
handles.

## Generated Package Contract

The emitted package lands under `connectors/<name>/` by default and uses
explicit `path:` deps only for the child packages it actually needs.

If the connector also needs external SDK/runtime repos outside this workspace,
use the same policy:

- prefer sibling-relative `path:` deps when the local checkout exists
- otherwise fall back to pinned git `ref:` deps
- do not vendor those repos into connector-local committed `deps/` directories

Generated files include:

- package-local `mix.exs`, `mix.lock`, `.formatter.exs`, and `.gitignore`
- a connector module that authors `AuthSpec`, `CatalogSpec`, and `OperationSpec`
- a derived executable capability projection through `Manifest`
- a runtime-class-appropriate handler skeleton
- a `<ConnectorModule>.Conformance` companion module with deterministic fixtures
- for non-direct scaffolds, a package-local `runtime_drivers/0` proof hook and
  deterministic Harness driver under `lib/` so downstream package tests can
  load the same conformance surface
- package-local tests, including a baseline conformance test
- a package README suitable for `mix docs`

When the workspace root already has a `mix.lock`, the scaffold copies that lock
snapshot into the new package so it participates in the same monorepo
dependency surface as the existing child packages.

## Generated Versus Authored Checklist

The scaffold output is the starting contract, not the finished connector
package.

The scaffold generates:

- package-local project wiring and explicit child-package deps
- a manifest-shaped connector module and derived executable projection seam
- package-local conformance publication through `<ConnectorModule>.Conformance`
- baseline tests and docs structure

Connector authors still need to author by hand:

- the real auth, catalog, operation, and trigger contract
- the real deterministic fixture expectations and any non-direct runtime driver
  behavior
- the package README sections for runtime family, auth posture, package-local
  verification, live-proof status, and package boundary
- any package-local examples, scripts, or live acceptance proofs

## Inventory, Runtime Publication, And Consumer Projection

Connector authors now need to keep three layers distinct:

1. provider inventory
   Keep the full upstream SDK inventory in connector-local catalogs or helper modules when that is useful for reviewability, parity tracking, or future planning.
2. runtime publication
   Only put the runtime capabilities you are actually publishing through `Manifest.operations` or `Manifest.triggers` into the authored manifest.
3. common consumer projection
   Only mark an authored entry as `consumer_surface.mode: :common` when it represents a curated normalized surface that should become a generated `Jido.Action`, `Jido.Sensor`, or `Jido.Plugin` entry.

If an authored runtime capability is useful but still provider-specific, keep it `consumer_surface.mode: :connector_local`.

If a provider SDK method is long-tail inventory that should remain at the SDK boundary, leave it out of the manifest entirely instead of inflating the generated Jido surface.

Generated actions, sensors, and plugins are always derivative. They are
reviewable consumer outputs built from authored manifest truth. Do not treat
the generated files or modules as a second authoring plane.

For non-direct authored operations, keep routing metadata on the authored
contract itself:

- `runtime.driver`
- `runtime.provider`
- `runtime.options`

There is no implicit `asm` fallback for `:session` or `:stream` routing. If a
non-direct connector omits `runtime.driver`, the control plane rejects that
authored capability instead of guessing.

Targets must align to those authored routing keys. A `TargetDescriptor` is a
compatibility and location advertisement, not a second place to override the
selected runtime driver, provider, or options.

When a caller needs target requirements, build them from authored capability
truth through `Jido.Integration.V2.TargetDescriptor.authored_requirements/2`
instead of re-inventing the merge at each call site.

For non-direct target lookup, require the authored `runtime.driver` as a target
feature as well. That keeps a `:session` or `:stream` capability from matching
another target that happens to share the same `capability_id` and
`runtime_class` but advertises the wrong Harness seam.

If a `:session` or `:stream` operation is published as
`consumer_surface.mode: :common`, it must also carry the canonical
`metadata.runtime_family` keys:

- `session_affinity`
- `resumable`
- `approval_required`
- `stream_capable`
- `lifecycle_owner`
- `runtime_ref`

Connector-local non-direct operations may omit `metadata.runtime_family`, but
that is an explicit authored exception, not the default posture for those
runtime families.

Keep those keys provider-neutral. They should describe the public Harness seam
and lifecycle posture, not ASM lane internals, provider-profile modules, or
CLI subprocess implementation details.

## Current Options

- `--runtime-class`: `direct`, `session`, or `stream`; default: `direct`
- `--runtime-driver`: required for `session` and `stream`; supported values are
  `asm` or `jido_session` for `session`, and `asm` for `stream`
- `--module`: fully qualified connector module override
- `--path`: output path override relative to the workspace root
- `--package-name`: human-readable package name override for docs and `mix.exs`

## Authoring Workflow

After generation:

1. replace the placeholder authored auth, catalog, and operation contract with the real connector surface
   Keep `auth.requested_scopes` aligned as the authored superset of every
   published operation or trigger `required_scopes`.
   Keep `auth.secret_names` aligned as the authored superset of any trigger
   verification secret or `secret_requirements`.
   Declare `consumer_surface` explicitly on every authored operation or trigger.
   If a trigger is `consumer_surface.mode: :common`, also declare
   deterministic `jido.sensor.name`, `jido.sensor.signal_type`, and
   `jido.sensor.signal_source` metadata, and keep those generated sensor names
   unique within the connector.
   Declare `schema_policy` explicitly on every authored operation or trigger.
   If a connector keeps passthrough payloads but knows some regions are
   late-bound, encode that authored truth in `OperationSpec.metadata`
   with `schema_strategy`, `schema_context_source`, and `schema_slots`.
   Reserve `:none` for static operations only; late-bound metadata must point
   at real lookup sources.
2. implement the action or provider logic inside the generated package
3. declare every child-package dependency explicitly in that connector package
   For external sibling repos, use sibling-path-or-pinned-git fallback rather
   than connector-local vendored dependencies.
4. update the companion fixtures so conformance reflects the real behavior
5. update the package README with the real operation and trigger inventory plus validation
   commands
6. add any package-local examples, scripts, or live acceptance proofs inside
   that connector package
7. run package-local tests and docs
8. run root conformance from the workspace root

## Proof Code Homes

Keep deterministic fixtures, companion modules, examples, scripts, and live
acceptance inside the connector package.

Do not move connector proof code into the workspace root.

If hosted routing, webhook registration, async recovery, or operator
composition is needed, keep that proof in an app or package above the
connector rather than widening the connector scaffold.

## Package Boundary Rules

- Do not make the connector depend on the repo root.
- Do not rely on transitive child-package deps.
- Keep deterministic fixtures package-local.
- Keep live acceptance package-local and opt-in.
- Keep app-specific webhook handlers, async callbacks, and host composition in
  app packages unless that behavior is part of the connector contract itself.
- Do not recreate root `examples/`.

## Validation Workflow

Typical loop after implementation:

```bash
cd connectors/<name> && mix deps.get
cd connectors/<name> && mix compile --warnings-as-errors
cd connectors/<name> && mix test
cd connectors/<name> && mix docs
mix jido.conformance <ConnectorModule>
mix ci
```

## Non-Goals

The root scaffold does not currently emit:

- trigger-capable ingress skeletons
- webhook-router registrations
- dispatch-runtime handlers
- live acceptance tests
- repo-root dependencies or hidden transitive child-package deps

If those are needed later, add them as explicit package or app work, not as
hand-built drift around the generated baseline.

It also does not assume that every authored runtime capability should become a
generated common-surface action or plugin entry. Authors must make that
projection decision explicitly.
