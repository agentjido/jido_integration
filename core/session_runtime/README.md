# Jido Session Runtime

`core/session_runtime` is the monorepo home for the internal `jido_session`
runtime.

It keeps the public module surface as `Jido.Session` and the runtime id as
`jido_session`, but the ownership now lives inside `jido_integration` rather
than a sibling repo. The package owns the in-memory session kernel, the
deterministic first session type, and the `Jido.Harness.RuntimeDriver`
projection used by `core/harness_runtime`.

## Responsibilities

- own the internal `jido_session` session and run lifecycle
- project session state into `Jido.Harness` Session Control IR structs
- provide the authored `runtime.driver: "jido_session"` basis for session work
- keep richer runtime-local state behind the shared Harness handle floor

## Boundary

This package is intentionally narrow.

- It does own the internal session kernel and the Harness driver.
- It does not own control-plane run truth, policy, auth lease issuance, or
  durable store selection.
- It does not replace `core/runtime_asm_bridge`; that package remains the
  separate projection for the authored `asm` driver.

The richer internal state stays in `Jido.Session.Runtime.*`, while the shared
projection surface lives in `Jido.Session.HarnessProjection`.

Boundary readiness keeps this package on the same Harness seam as `asm`.
Target descriptors publish `extensions["boundary"]` as the authored baseline
boundary capability advertisement, and runtime code may combine worker-local
facts with that baseline to build a runtime-merged live capability view for
boundary-backed `jido_session` just as it does for boundary-backed `asm`.

As built for Stage 4, the in-repo `jido_session` lane now consumes the shared
`Jido.BoundaryBridge` seam directly:

- `start_session/1` can allocate or reopen through the bridge
- consumer entrypoints fail closed on unsupported `descriptor_version`
- `jido_session` claims the ready boundary before exposing the session handle
- the normalized boundary descriptor is carried on the public session handle and
  projected terminal results
- `policy_intent_echo` stays evidence-only; runtime policy still comes from the
  authored request and target context above the descriptor seam

## Usage

Direct runtime use:

```elixir
request =
  Jido.Harness.RunRequest.new!(%{
    prompt: "fix login bug",
    cwd: "/tmp/project",
    metadata: %{"ticket" => "AUTH-12"}
  })

{:ok, session} =
  Jido.Session.start_session(
    provider: :jido_session,
    cwd: "/tmp/project",
    metadata: %{"session_type" => "local_echo"}
  )

{:ok, run, events} = Jido.Session.stream_run(session, request, run_id: "run-1")
{:ok, result} = Jido.Session.run(session, request, run_id: "run-2")

events |> Enum.map(& &1.type)
#=> [:run_started, :assistant_message, :result]

result.text
#=> "handled: fix login bug"
```

Via Harness:

```elixir
Application.put_env(:jido_harness, :runtime_drivers, %{jido_session: Jido.Session.HarnessDriver})
Application.put_env(:jido_harness, :default_runtime_driver, :jido_session)

request = Jido.Harness.RunRequest.new!(%{prompt: "through harness", metadata: %{}})
{:ok, session} = Jido.Harness.start_session(session_id: "session-1", provider: :jido_session)
{:ok, _run, events} = Jido.Harness.stream_run(session, request)
```

Boundary-backed internal session:

```elixir
{:ok, session} =
  Jido.Session.start_session(
    session_id: "session-boundary-1",
    provider: :jido_session,
    boundary_request: %{
      boundary_session_id: "bnd-session-1",
      backend_kind: :microvm,
      boundary_class: :leased_cell,
      attach: %{mode: :not_applicable, working_directory: "/srv/jido_session"},
      policy_intent: %{sandbox_level: :strict},
      refs: %{target_id: "target-session-1", runtime_ref: "runtime-session-1"},
      allocation_ttl_ms: 250
    },
    boundary_adapter: Jido.BoundaryBridge.Adapters.JidoOs,
    boundary_adapter_opts: [instance_id: "instance-local", actor_id: "system:jido_session"]
  )

session.metadata["boundary"]["descriptor"]["boundary_session_id"]
#=> "bnd-session-1"
```

## Public Modules

- `Jido.Session`
- `Jido.Session.HarnessDriver`
- `Jido.Session.HarnessProjection`
- `Jido.Session.Runtime.Session`
- `Jido.Session.Runtime.Run`
- `Jido.Session.Runtime.LocalEcho`

## Validation

Package-local loop:

```bash
cd /home/home/p/g/n/jido_integration/core/session_runtime
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test
mix docs
```

Canonical root gate:

```bash
cd /home/home/p/g/n/jido_integration
mix ci
```

## Related Guides

- [Runtime Model](../../guides/runtime_model.md)
- [Architecture](../../guides/architecture.md)
- [Request Lifecycle](../../guides/developer/request_lifecycle.md)
