# Jido Integration V2 Platform

Public facade package for the non-umbrella Jido Integration monorepo.

Owns:

- the public app identity `:jido_integration_v2`
- the stable `Jido.Integration.V2` facade module
- the typed public invocation helper `Jido.Integration.V2.InvocationRequest`
- connector and capability discovery through `connectors/0`,
  `fetch_connector/1`, `fetch_capability/1`, and `capabilities/0`
- connector contract integration tests that prove direct, session, and stream
  execution through the public API

Key public calls:

- `Jido.Integration.V2.invoke/1`
- `Jido.Integration.V2.invoke/3`
- `Jido.Integration.V2.connectors/0`
- `Jido.Integration.V2.fetch_connector/1`
- `Jido.Integration.V2.fetch_capability/1`
- `Jido.Integration.V2.capabilities/0`

Dependency posture:

- runtime dependencies stay in `core/*`
- connectors remain opt-in and are pulled into this package only for tests
- `core/store_postgres` is used to validate the facade contract in tests, not as
  a mandatory runtime dependency for consumers

## Installation

Inside this monorepo, depend on `core/platform` when a project wants the public
facade:

```elixir
def deps do
  [
    {:jido_integration_v2, path: "../core/platform"}
  ]
end
```

Projects should still declare explicit dependencies on any child packages whose
modules they reference directly.
