# Jido Integration V2 Direct Runtime

Direct execution for stateless, request/response capabilities.

This package is the mandatory coupling to the fixed Jido substrate for
non-sessioned work. It executes capabilities through `Jido.Action` handlers
and keeps the direct provider-SDK lane clean.

## Responsibilities

- execute non-sessioned capabilities through `Jido.Action`
- keep direct connector execution off the Runtime Control seam
- preserve the provider-SDK path for direct connectors
- avoid introducing session, stream, or async ownership here

## Boundary

Use this package when the capability can finish in one direct invocation.
Do not route long-lived session state or replayable async work through it.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be
installed by adding `jido_integration_v2_direct_runtime` to your list of
dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_integration_v2_direct_runtime, "~> 0.1.0"}
  ]
end
```

## Related Guides

- [Runtime Model](../../guides/runtime_model.md)
- [Architecture](../../guides/architecture.md)
- [Connector Lifecycle](../../guides/connector_lifecycle.md)
