# Runtime Model

Jido Integration supports three runtime families. Pick the lightest one that
matches the behavior you need.

## Direct Runtime

Direct capabilities execute through `core/direct_runtime` and a connector's
provider SDK. This path is for request/response work that does not need a
Harness-managed session or streaming state.

Use it when:

- one request maps to one bounded execution
- the connector can finish cleanly without preserving runtime state
- you want the simplest dependency and review story

## Harness-Backed Runtime

Sessioned and streamed capabilities go through `Jido.Harness`.

- `core/harness_runtime` is the authored adapter layer used by the control
  plane for all non-direct capability execution.
- `asm` is projected by `core/runtime_asm_bridge` into the
  `agent_session_manager` and `cli_subprocess_core` lane.
- `jido_session` is projected by `core/session_runtime` via
  `Jido.Session.HarnessDriver`.

This is the stable non-direct seam for long-running or stateful execution.

Use it when:

- work must reuse a runtime-managed session
- a target needs explicit runtime-driver compatibility
- the capability publishes session or stream behavior honestly rather than
  pretending to be direct

## Hosted Async And Webhooks

Hosted webhook registration and async replay are separate package surfaces.
They live in `core/webhook_router` and `core/dispatch_runtime`, not in the
facade package and not in the direct runtime path.

## Design Rule

If a capability can finish cleanly without preserving runtime state, keep it
direct.
If it needs session continuity, replay, or host-visible recovery, route it
through Harness or the async packages explicitly.
