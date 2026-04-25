# Jido Integration V2 Codex CLI Connector

Example external session connector package using the authored
`Jido.RuntimeControl` `asm` driver and the Codex app-server SDK lane.

This package publishes the canonical session-family authored shape on the
shared common consumer-surface spine.

## Runtime And Auth Posture

- runtime families: `:session`, `:stream`
- stable runtime contract seam: `jido_runtime_control` via `Jido.RuntimeControl`
- public auth binding is `connection_id`
- the authored session routing contract is explicit:
  `runtime.driver: "asm"`, `runtime.provider: :codex`, and
  `runtime.options: %{app_server: true}`
- the `asm` driver resolves through
  `Jido.Integration.V2.AsmRuntimeBridge.RuntimeControlDriver` into
  `agent_session_manager`, with `codex_sdk` owning app-server protocol details
- this connector package depends on `jido_runtime_control` for the
  shared seam; it does not take direct
  `agent_session_manager` or `cli_subprocess_core` package deps
- the package mints short-lived credential leases with `access_token` payloads
  for deterministic session execution
- scope-gated admission is explicit through `session:execute`,
  `session:control`, and `session:tools`

## Capability Surface

The package publishes the promoted Codex app-server session family:

- `codex.session.start`
- `codex.session.turn`
- `codex.session.stream`
- `codex.session.cancel`
- `codex.session.status`
- `codex.session.approve`
- `codex.session.tool.respond`

The primary executable turn is `codex.session.turn`:

- `consumer_surface.mode: :common`
- `consumer_surface.normalized_id: "codex.session.turn"`
- `consumer_surface.action_name: "codex_session_turn"`
- `metadata.codex_app_server.primary?: true`
- `metadata.codex_app_server.host_tools: :native`
- canonical `metadata.runtime_family` for connection affinity, resumability,
  approval posture, stream capability, lifecycle ownership, and the stable
  Runtime Control runtime reference

The old `codex.exec.session` shape is removed from this connector. It was the
pre-promotion stdio placeholder and is no longer the primary contract.

For this package, `metadata.runtime_family.runtime_ref: :session` names the
public Runtime Control handle shape. It does not claim ownership of ASM's internal
process state.

The generated consumer surface stays stateless. Session lifecycle, parser
state, and transport state remain outside the connector package on the
accepted Runtime Control seam.

Proves:

- session-class capability publishing against the shared `RuntimeResult`
  substrate
- shared common-surface projection through generated `Jido.Action` and
  `Jido.Plugin` modules
- strict session policy posture for environment, approvals, workspace scope,
  and tool allowlists
- lease-bound auth and connector-specific review artifacts/events
- session reuse keyed by the stable Runtime Control session handle returned by the
  authored `asm` driver while durable review truth keeps only the runtime
  reference id
- Codex app-server host tools and provider session ids carried by Runtime
  Control events/results

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
mix jido.conformance Jido.Integration.V2.Connectors.CodexCli
mix ci
```

## Live Proof Status

No package-local live proof exists yet.

The live app-server acceptance lives at the ASM bridge boundary because that is
where `agent_session_manager` and `codex_sdk` are both present:

```bash
cd core/asm_runtime_bridge
JIDO_INTEGRATION_WORKSPACE="${JIDO_INTEGRATION_WORKSPACE:-$PWD/../..}"
/home/home/scripts/with_bash_secrets mix run examples/live_codex_app_server_acceptance.exs -- --cwd "$JIDO_INTEGRATION_WORKSPACE"
```

Default package tests and conformance stay credential-free.

## Package Boundary

This package owns the authored session contract, generated common consumer
surface, deterministic runtime-control conformance publication, and review events.

It does not own the provider-neutral session lane in
`agent_session_manager`, the CLI subprocess foundation in `cli_subprocess_core`,
hosted routing, or app-level operator composition above the connector boundary.

It is also not the same thing as CLI-backed inference endpoint publication.
That inference path stays on `ASM.InferenceEndpoint` and the control-plane
inference route rather than this session connector seam.

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
