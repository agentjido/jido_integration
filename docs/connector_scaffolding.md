# Connector Scaffolding

Connector generation stays in the workspace root because it owns monorepo
layout concerns.

The entry point is:

```bash
mix jido.integration.new <connector_name>
```

Example commands:

```bash
mix jido.integration.new acme_crm
mix jido.integration.new analyst_cli --runtime-class session
mix jido.integration.new market_feed --runtime-class stream
mix jido.integration.new custom_ai --module MyApp.Connectors.CustomAi --package-name "Custom AI Connector"
```

## Runtime Classes

The scaffold currently supports these runtime families:

- `direct`
- `session`
- `stream`

The emitted package always lands under `connectors/<name>/` by default and
uses explicit `path:` deps to the specific child packages it needs.

## Generated Files

Each scaffolded package includes:

- package-local `mix.exs`, `.formatter.exs`, and `.gitignore`
- a connector module that publishes `Manifest` and `Capability`
- a runtime-class-appropriate action/provider skeleton
- a `<ConnectorModule>.Conformance` companion module with deterministic fixtures
- package-local tests, including a baseline conformance test
- a package README suitable for `mix docs`

## Current Options

- `--runtime-class`: `direct`, `session`, or `stream`
- `--module`: fully qualified connector module override
- `--path`: output path override relative to the workspace root
- `--package-name`: human-readable package name override for docs and `mix.exs`

## Validation Workflow

After generation, the intended loop is:

1. replace the placeholder capability contract with the real provider surface
2. update the action/provider implementation
3. update the deterministic fixture expectations
4. run `mix deps.get`
5. run `mix test`
6. run `mix docs`
7. from the workspace root, run `mix jido.conformance <ConnectorModule>`

## Non-Goals In This Slice

The root scaffold does not currently emit:

- trigger-capable ingress skeletons
- live acceptance tests
- repo-root dependencies or hidden transitive child-package deps

If those are needed later, they should land as explicit follow-on extensions to
the root scaffold rather than as hand-built connector drift.
