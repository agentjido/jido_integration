# Jido.RuntimeControl

Shared Session Control facade, IR, and runtime-driver contract layer.

`Jido.RuntimeControl` is the common seam used by the integration runtime path:

- `core/runtime_router` routes authored runtime selections into this facade
- `core/session_runtime` provides the native `jido_session` runtime driver
- `core/asm_runtime_bridge` adapts ASM into the same runtime-driver contract

This package no longer carries the old provider-adapter compatibility lane. Its
public surface is the runtime-driver seam only.

## Installation

Inside this monorepo, `Jido.RuntimeControl` lives at `core/runtime_control` and
should be validated through the root workspace commands.

For external consumers, add `jido_runtime_control` to your list of dependencies
in `mix.exs`:

```elixir
def deps do
  [
    {:jido_runtime_control, "~> 0.1.0"}
  ]
end
```

## Runtime Driver Configuration

```elixir
config :jido_runtime_control, :runtime_drivers, %{
  jido_session: Jido.Session.RuntimeControlDriver,
  asm: Jido.Integration.V2.AsmRuntimeBridge.RuntimeControlDriver
}

config :jido_runtime_control, :default_runtime_driver, :jido_session
```

## Usage

```elixir
request =
  Jido.RuntimeControl.RunRequest.new!(%{
    prompt: "fix the bug",
    host_tools: [],
    continuation: nil,
    provider_metadata: %{},
    metadata: %{}
  })

{:ok, session} =
  Jido.RuntimeControl.start_session(
    :jido_session,
    session_id: "session-1",
    provider: :jido_session
  )

{:ok, run, events} = Jido.RuntimeControl.stream_run(session, request, run_id: "run-1")
{:ok, result} = Jido.RuntimeControl.run_result(session, request, run_id: "run-2")
{:ok, status} = Jido.RuntimeControl.session_status(session)
:ok = Jido.RuntimeControl.approve(session, "approval-1", :allow)
{:ok, cost} = Jido.RuntimeControl.cost(session)
:ok = Jido.RuntimeControl.cancel_run(session, run)
:ok = Jido.RuntimeControl.stop_session(session)
```

## Public Facade

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
optional `run/3` callback. `Jido.RuntimeControl.RuntimeDriver` also defines
optional `subscribe/2` and `resume/3` callbacks; drivers advertise those
capabilities through `RuntimeDescriptor.subscribe?` and
`RuntimeDescriptor.resume?`.

## Provider-Native Session Fields

`RunRequest` carries provider-neutral execution input plus optional
provider-native session controls:

- `host_tools` publishes host-provided tool specs to runtimes that support
  native host tools. The ASM bridge accepts this for the Codex app-server SDK
  lane and rejects unsupported providers with a Runtime Control validation
  error.
- `continuation` carries provider session resume intent, for example
  `%{strategy: :exact, provider_session_id: "thread-id"}`.
- `provider_metadata` carries whitelisted provider option intent such as
  `%{app_server: true}` without widening the common Runtime Control schema for
  every provider-specific switch.

`ExecutionEvent` and `ExecutionResult` include `provider_session_id`; streamed
events can also carry `provider_turn_id`, `tool_name`, and `approval_id`.
Drivers should redact raw provider evidence before storing it under event
metadata or `raw`.

## Boundary Metadata Carriage

For boundary-backed execution, runtimes carry live boundary descriptors or
attach metadata under `metadata["boundary"]`. The named Wave 5 subcontracts
inside that namespace are `descriptor`, `route`, `attach_grant`, `replay`,
`approval`, `callback`, and `identity`.

Runtime Control keeps that carriage runtime-neutral and does not own sandbox
policy, target selection, or boundary backend semantics.

The current family-facing carrier details for `ProcessExecutionIntent.v1` and
`JsonRpcExecutionIntent.v1` remain provisional until Wave 3 prove-out. Wave 1
freezes the names, ownership, and carriage rules only.

## Documentation Menu

- `README.md` - package purpose and public runtime-driver facade
- `docs/execution_plane_alignment.md` - frozen lower-boundary packet and
  carriage rules
- `docs/dependency_policy.md` - dependency posture and update rules

## Documentation

Full documentation is available at
[https://hexdocs.pm/jido_runtime_control](https://hexdocs.pm/jido_runtime_control).

## Testing Paths

- Unit/runtime tests: `mix test`
- Full monorepo quality gate: run `mix ci` from the repo root
- Runtime-driver diagnostics:
  `Jido.RuntimeControl.RuntimeRegistry.diagnostics/0` in `iex -S mix`
