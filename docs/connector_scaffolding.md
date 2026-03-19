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

The workspace scaffold currently supports direct connectors only.

Phase 0 intentionally refuses to generate `session` or `stream` packages from
the root scaffold. That keeps new connector work from deepening the frozen
`integration_session_bridge` and `integration_stream_bridge` compatibility
paths. Compose non-direct connectors manually against the real Harness target
kernels, `asm` or `jido_session`, instead:

- `asm`
- `jido_session`

Hosted webhook routing is not a runtime class. If the proof depends on route
registration, secret resolution, or async transport, keep that proof in an app
or package above the connector rather than forcing it into the scaffold.

## Generated Package Contract

The emitted package lands under `connectors/<name>/` by default and uses
explicit `path:` deps only for the child packages it actually needs.

Generated files include:

- package-local `mix.exs`, `mix.lock`, `.formatter.exs`, and `.gitignore`
- a connector module that authors `AuthSpec`, `CatalogSpec`, and `OperationSpec`
- a derived executable capability projection through `Manifest`
- a direct-runtime action skeleton
- a `<ConnectorModule>.Conformance` companion module with deterministic fixtures
- package-local tests, including a baseline conformance test
- a package README suitable for `mix docs`

When the workspace root already has a `mix.lock`, the scaffold copies that lock
snapshot into the new package so it participates in the same monorepo
dependency surface as the existing child packages.

## Current Options

- `--runtime-class`: `direct`, `session`, or `stream`; only `direct` is
  scaffoldable in Phase 0
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
2. implement the action or provider logic inside the generated package
3. declare every child-package dependency explicitly in that connector package
4. update the companion fixtures so conformance reflects the real behavior
5. update the package README with the real operation and trigger inventory plus validation
   commands
6. add any package-local examples, scripts, or live acceptance proofs inside
   that connector package
7. run package-local tests and docs
8. run root conformance from the workspace root

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
