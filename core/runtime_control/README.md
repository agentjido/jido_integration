# Jido.RuntimeControl

Normalized Elixir contract layer for CLI AI coding agents and Session Control
runtimes.

`Jido.RuntimeControl` now supports two explicit surfaces:

- legacy provider adapters registered under `:providers`
- Session Control runtime drivers registered under `:runtime_drivers`

It also now aligns its lower-boundary vocabulary with the frozen packet and the
Wave 5 durable session-carriage vocabulary:

- `BoundarySessionDescriptor.v1`
- `ExecutionRoute.v1`
- `AttachGrant.v1`
- `CredentialHandleRef.v1`
- `ExecutionEvent.v1`
- `ExecutionOutcome.v1`
- `ProcessExecutionIntent.v1`
- `JsonRpcExecutionIntent.v1`

Runtime Control maps or carries those contracts. It does not re-export raw
`execution_plane/*` packages as its public API.

## Installation

Inside this monorepo, `Jido.RuntimeControl` lives at `core/runtime_control`
and should be validated through the root workspace commands.

For external consumers, add `jido_runtime_control` to your list of dependencies
in `mix.exs`:

```elixir
def deps do
  [
    {:jido_runtime_control, "~> 0.1.0"}
  ]
end
```

Its runtime dependencies now follow one stable policy:

- keep `core/runtime_control` itself workspace-local inside this monorepo
- prefer a sibling-relative path for external repos such as `jido_shell` when
  that checkout exists
- otherwise fall back to pinned git refs
- use a pinned git ref for `sprites`, with an optional sibling checkout if one
  exists locally

Floating branch dependencies are no longer the default.

## Usage

### Legacy Adapter World

```elixir
# Optional: configure provider adapter modules explicitly
config :jido_runtime_control, :providers, %{
  codex: Jido.Codex.Adapter,
  gemini: Jido.Gemini.Adapter
}

# Optional: set a default provider adapter
config :jido_runtime_control, :default_provider, :codex

# Run with explicit provider
{:ok, events} = Jido.RuntimeControl.run(:codex, "fix the bug", cwd: "/my/project")

# Or run through the default provider
{:ok, events} = Jido.RuntimeControl.run("fix the bug", cwd: "/my/project")
```

### Session Control Runtime-Driver World

```elixir
config :jido_runtime_control, :runtime_drivers, %{
  jido_session: Jido.Session.RuntimeControlDriver,
  asm: Jido.Integration.V2.AsmRuntimeBridge.RuntimeControlDriver
}

config :jido_runtime_control, :default_runtime_driver, :jido_session

request = Jido.RuntimeControl.RunRequest.new!(%{prompt: "fix the bug", metadata: %{}})

{:ok, session} =
  Jido.RuntimeControl.start_session(
    :jido_session,
    session_id: "session-1",
    provider: :jido_session
  )

{:ok, run, events} = Jido.RuntimeControl.stream_run(session, request, run_id: "run-1")
{:ok, result} = Jido.RuntimeControl.run_result(session, request, run_id: "run-2")
```

## What It Wraps

Legacy adapter resolution can resolve providers from:
- explicit app config (`config :jido_runtime_control, :providers, %{...}`)
- runtime auto-discovery of known module candidates for:
  - `:codex`
  - `:amp`
  - `:claude`
  - `:gemini`
  - `:opencode`

Auto-discovery is non-invasive: modules are used only if they are loaded and expose a supported run API.

## Public Facade

Legacy adapter functions:

```elixir
Jido.RuntimeControl.providers()
Jido.RuntimeControl.default_provider()

Jido.RuntimeControl.run(:codex, "prompt", cwd: "/repo")
Jido.RuntimeControl.run("prompt", cwd: "/repo")

request = Jido.RuntimeControl.RunRequest.new!(%{prompt: "prompt"})
Jido.RuntimeControl.run_request(:codex, request, transport: :exec)
Jido.RuntimeControl.run_request(request)

Jido.RuntimeControl.capabilities(:codex)
Jido.RuntimeControl.cancel(:codex, "session_id")
```

Session Control runtime-driver functions:

```elixir
Jido.RuntimeControl.runtime_drivers()
Jido.RuntimeControl.default_runtime_driver()
Jido.RuntimeControl.runtime_descriptor(:jido_session)

{:ok, session} = Jido.RuntimeControl.start_session(:jido_session, provider: :jido_session)
{:ok, run, events} = Jido.RuntimeControl.stream_run(session, request)
{:ok, result} = Jido.RuntimeControl.run_result(session, request)
{:ok, status} = Jido.RuntimeControl.session_status(session)
:ok = Jido.RuntimeControl.approve(session, "approval-1", :allow)
{:ok, cost} = Jido.RuntimeControl.cost(session)
:ok = Jido.RuntimeControl.cancel_run(session, run)
:ok = Jido.RuntimeControl.stop_session(session)
```

`Jido.RuntimeControl.run_result/3` is the public facade for a runtime driver's
optional `run/3` callback. `Jido.RuntimeControl.RuntimeDriver` also defines optional
`subscribe/2` and `resume/3` callbacks; drivers advertise those capabilities
through `RuntimeDescriptor.subscribe?` and `RuntimeDescriptor.resume?`.

For boundary-backed execution, runtimes carry live boundary descriptors or
attach metadata under `metadata["boundary"]`. The named Wave 5 subcontracts
inside that namespace are `descriptor`, `route`, `attach_grant`, `replay`,
`approval`, `callback`, and `identity`. Runtime Control keeps that carriage
runtime-neutral and does not own sandbox policy, target selection, or boundary
backend semantics.

The current family-facing carrier details for `ProcessExecutionIntent.v1` and
`JsonRpcExecutionIntent.v1` remain provisional until Wave 3 prove-out. Wave 1
freezes the names, ownership, and carriage rules only.

## Documentation Menu

- `README.md` - install, public facade, and runtime-driver framing
- `docs/execution_plane_alignment.md` - frozen lower-boundary packet and
  carriage rules
- `docs/telemetry.md` - signal and telemetry conventions
- `docs/dependency_policy.md` - dependency posture and update rules

## Documentation

Full documentation is available at [https://hexdocs.pm/jido_runtime_control](https://hexdocs.pm/jido_runtime_control).

## Package Purpose

`jido_runtime_control` is the provider-neutral contract layer shared by legacy CLI
adapters and Session Control runtime drivers. It owns the public IR, runtime
driver behaviour, and generic runtime bootstrap/preflight helpers.

It is intentionally not a transport registry. Runtime drivers may carry
`execution_surface` and `execution_environment` through to deeper layers, but
`jido_runtime_control` itself does not enumerate or normalize transport families.

The canonical lower-boundary packet vocabulary is exposed as metadata and
mapped IR through `Jido.RuntimeControl.SessionControl.mapped_execution_contracts/0`,
not as a wholesale re-export of raw lower packages.

## Testing Paths

- Unit/runtime tests: `mix test`
- Full monorepo quality gate: run `mix ci` from the repo root
- Registry/runtime diagnostics: `Jido.RuntimeControl.Registry.diagnostics/0` in `iex -S mix`
