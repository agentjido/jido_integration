# Jido Integration V2 Session Kernel

Compatibility bridge for sessioned capabilities that still expose the legacy
provider contract.

Current responsibilities:

- publish a Harness runtime driver for legacy session providers
- preserve session reuse keyed by capability-specific provider logic
- keep `runtime_ref_id` and `session_id` durable at the control-plane boundary
- act as a temporary shim while permanent session mechanics live behind Harness

This package is compatibility-only in Phase 0. The workspace scaffold no longer
generates new packages against this bridge.

New session connectors should not treat this package as the final architecture.
Compose them manually against the real Harness target kernels (`asm` or
`jido_session`) instead of deepening this shim.

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
