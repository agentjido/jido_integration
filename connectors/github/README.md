# Jido Integration V2 GitHub Connector

Direct baseline connector package.

Proves:

- direct capability publishing against the shared `RuntimeResult` substrate
- `Jido.Action`-backed execution with lease-bound auth (`access_token` only)
- explicit policy posture for environment and sandbox tool allowlists
- connector-specific review events plus a durable artifact ref per run
- scope-gated admission (`repo`)

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `jido_integration_v2_github` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_integration_v2_github, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/jido_integration_v2_github>.
