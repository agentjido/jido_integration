# Jido Integration V2 Conformance

Reusable V2-native connector conformance package.

This package owns `Jido.Integration.V2.Conformance`, stable profile
definitions, report rendering, and the reusable suite engine that the workspace
root invokes.

## Owns

- `Jido.Integration.V2.Conformance`
- stable profile definitions such as `:connector_foundation`
- human and JSON report rendering
- suite modules for manifest, capability, runtime-fit, policy, fixture, and
  ingress checks

The root workspace exposes this package through `mix jido.conformance`, but
the implementation stays here so the repo root remains tooling-only.

`mix jido.conformance <ConnectorModule>` is the stable root connector
acceptance command. Package-local fixtures, runtime-driver evidence, and
ingress definitions stay package-local even though the task runs from the
workspace root.

## Current Stable Profile

`connector_foundation` is the current deterministic connector baseline.

Suite order:

1. `manifest_contract`
2. `capability_contracts`
3. `runtime_class_fit`
4. `policy_contract`
5. `deterministic_fixtures`
6. `ingress_definition_discipline`

Future profiles should extend this model with more suites instead of changing
the root task shape.

## Connector Workflow

Typical connector review loop:

1. implement or update the connector package
2. run package-local `mix test`
3. run package-local `mix docs`
4. from the workspace root, run:

```bash
mix jido.conformance <ConnectorModule>
```

5. finish with the root monorepo commands and `mix ci`

## Fixture Companion Module

Connectors can publish deterministic evidence without depending on this package
directly by adding an optional companion module:

```elixir
defmodule MyApp.Connectors.Example.Conformance do
  def fixtures do
    [
      %{
        capability_id: "example.echo",
        input: %{message: "hello"},
        credential_ref: %{id: "cred-1", subject: "operator", scopes: ["echo:run"]},
        credential_lease: %{
          lease_id: "lease-1",
          credential_ref_id: "cred-1",
          subject: "operator",
          scopes: ["echo:run"],
          payload: %{token: "lease-token"},
          issued_at: ~U[2026-03-12 00:00:00Z],
          expires_at: ~U[2026-03-12 00:05:00Z]
        },
        expect: %{
          output: %{message: "hello"},
          event_types: ["attempt.started", "connector.example.echoed", "attempt.completed"],
          artifact_types: [:event_log],
          artifact_keys: ["example/run-1/run-1:1/result.term"]
        }
      }
    ]
  end
end
```

Trigger-capable connectors may also publish `ingress_definitions/0` from the
same companion module.

Non-direct connectors may also publish `runtime_drivers/0` from the same
companion module so conformance can bind accepted Harness driver ids such as
`asm` or `jido_session` to deterministic package-local test drivers.

The companion module is the connector-owned publication point for deterministic
fixtures, runtime-driver evidence, and ingress definitions.

## Direct Package Use

Inside this monorepo, depend on `core/conformance` only when another child
package truly needs the engine directly. The more common path is still the
root task.

## Related Guides

- [Connector Lifecycle](../../guides/connector_lifecycle.md)
- [Conformance](../../guides/conformance.md)
