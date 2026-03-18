# Jido Integration V2 Codex CLI Connector

Session baseline connector package.

This package still targets the `integration_session_bridge` compatibility shim.
That is deliberate for deterministic fixture coverage, but it is not the final
runtime model. Treat this package as a migration fixture, not as a template for
new connector work. New runtime-boundary work must target Harness through
`asm` or `jido_session` instead of extending this shim.

Proves:

- session-class capability publishing against the shared `RuntimeResult` substrate
- strict session policy posture for environment, approvals, workspace scope, and tool allowlists
- lease-bound auth and connector-specific review artifacts/events
- session reuse keyed by credential ref instead of only subject
- scope-gated admission (`session:execute`)

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `jido_integration_v2_codex_cli` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_integration_v2_codex_cli, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/jido_integration_v2_codex_cli>.
