# Jido Integration V2 Codex CLI Connector

Example external session connector package using the authored `Jido.Harness`
`asm` driver.

This package publishes the canonical session-family authored shape on the
shared common consumer-surface spine.

## Runtime And Auth Posture

- runtime family: `:session`
- stable runtime contract seam: `Jido.Harness`
- public auth binding is `connection_id`
- the authored session routing contract is explicit:
  `runtime.driver: "asm"`, `runtime.provider: :codex`, and
  `runtime.options: %{}`
- the `asm` driver resolves through
  `Jido.Integration.V2.RuntimeAsmBridge.HarnessDriver` into
  `agent_session_manager`, with `cli_subprocess_core` below that lane
- this connector package depends on `jido_harness` for the shared seam; it
  does not take direct `agent_session_manager` or `cli_subprocess_core`
  package deps
- the package mints short-lived credential leases with `access_token` payloads
  for deterministic session execution
- scope-gated admission is explicit through `session:execute`

## Capability Surface

The package publishes one authored session capability:

- `codex.exec.session`

Its common-surface projection is also explicit:

- `consumer_surface.mode: :common`
- `consumer_surface.normalized_id: "codex.exec.session"`
- `consumer_surface.action_name: "codex_exec_session"`
- canonical `metadata.runtime_family` for connection affinity, resumability,
  approval posture, stream capability, lifecycle ownership, and the stable
  Harness runtime reference

For this package, `metadata.runtime_family.runtime_ref: :session` names the
public Harness handle shape. It does not claim ownership of ASM's internal
process state.

The generated consumer surface stays stateless. Session lifecycle, parser
state, and transport state remain outside the connector package on the
accepted Harness seam.

Proves:

- session-class capability publishing against the shared `RuntimeResult`
  substrate
- shared common-surface projection through generated `Jido.Action` and
  `Jido.Plugin` modules
- strict session policy posture for environment, approvals, workspace scope,
  and tool allowlists
- lease-bound auth and connector-specific review artifacts/events
- session reuse keyed by the stable Harness session handle returned by the
  authored `asm` driver while durable review truth keeps only the runtime
  reference id

## Package Verification

From the package directory:

```bash
cd connectors/codex_cli
mix deps.get
mix compile --warnings-as-errors
mix test
mix docs
```

From the workspace root:

```bash
cd /home/home/p/g/n/jido_integration
mix jido.conformance Jido.Integration.V2.Connectors.CodexCli
mix ci
```

## Live Proof Status

No package-local live proof exists yet. The accepted baseline for this package
is deterministic package tests plus root conformance.

## Package Boundary

This package owns the authored session contract, generated common consumer
surface, deterministic Harness conformance publication, and review events.

It does not own the provider-neutral session lane in
`agent_session_manager`, the CLI subprocess foundation in
`cli_subprocess_core`, hosted routing, or app-level operator composition above
the connector boundary.

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
