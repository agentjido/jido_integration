# Jido Integration V2 Conformance

Reusable v2-native connector conformance package.

Owns:

- the stable `Jido.Integration.V2.Conformance` engine
- profile definitions such as `:connector_foundation`
- report rendering for human and JSON output
- suite modules for manifest, capability, runtime-fit, policy, fixture, and
  ingress discipline checks

The root workspace exposes this package through `mix jido.conformance`, but the
implementation stays here so the repo root remains tooling-only.

## Current Profile Model

`connector_foundation` is the base profile for deterministic connector review.
It locks a stable suite order that future generated packages and docs can rely
on:

1. `manifest_contract`
2. `capability_contracts`
3. `runtime_class_fit`
4. `policy_contract`
5. `deterministic_fixtures`
6. `ingress_definition_discipline`

Future async and webhook-routing profiles are expected to extend this model by
adding suites, not by changing the task API.

## Fixture Companion Module

Connectors can publish deterministic conformance evidence without depending on
this package directly by adding an optional companion module:

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

## Package Use

Inside this monorepo, depend on `core/conformance` when another child package
needs the engine directly:

```elixir
def deps do
  [
    {:jido_integration_v2_conformance, path: "../conformance"}
  ]
end
```
