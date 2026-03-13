# Jido Integration V2 Session Kernel

Executes sessioned capabilities through reusable provider-managed sessions.

Current proof:

- session reuse keyed by capability plus credential subject
- provider-managed session lifecycle
- generic `runtime_ref_id` recorded at the attempt layer

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `jido_integration_v2_session_kernel` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_integration_v2_session_kernel, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/jido_integration_v2_session_kernel>.
