# Jido Integration V2 Codex CLI Connector

Example external session connector package.

This package publishes the canonical Phase 4 external session-family authored
shape:

- `runtime_class: :session`
- `runtime.driver: "asm"`
- `runtime.provider: :codex`
- `runtime.options: %{}`
- `consumer_surface.mode: :common`
- `consumer_surface.normalized_id: "codex.exec.session"`
- `consumer_surface.action_name: "codex_exec_session"`
- canonical `metadata.runtime_family` for connection affinity, resumability,
  approval posture, stream capability, lifecycle ownership, and durable runtime
  references

The generated consumer surface stays stateless. Session lifecycle, parser
state, and transport state remain outside `jido_integration` on the accepted
Harness seam.

Proves:

- session-class capability publishing against the shared `RuntimeResult`
  substrate
- shared common-surface projection through generated `Jido.Action` and
  `Jido.Plugin` modules
- strict session policy posture for environment, approvals, workspace scope, and tool allowlists
- lease-bound auth and connector-specific review artifacts/events
- session reuse keyed by the ASM-backed Harness session handle while durable
  review truth keeps only the stable runtime reference id
- scope-gated admission (`session:execute`)

## Validation

From the package directory:

```bash
mix test
mix docs
```

From the repo root:

```bash
mix jido.conformance Jido.Integration.V2.Connectors.CodexCli
mix ci
```

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
