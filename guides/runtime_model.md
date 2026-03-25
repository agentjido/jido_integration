# Runtime Model

The runtime model is intentionally narrow.

## Direct Runtime

Direct capabilities execute through `core/direct_runtime` and a connector's
provider SDK. This path is for request/response work that does not need a
Harness-managed session or streaming state.

## Harness-Backed Runtime

Sessioned and streamed capabilities go through `Jido.Harness`.

- `asm` is projected by `core/runtime_asm_bridge` into the
  `agent_session_manager` and `cli_subprocess_core` lane.
- `jido_session` routes through `jido_session` via
  `Jido.Session.HarnessDriver`.

This is the stable non-direct seam for long-running or stateful execution.

## Hosted Async And Webhooks

Hosted webhook registration and async replay are separate package surfaces.
They live in `core/webhook_router` and `core/dispatch_runtime`, not in the
facade package and not in the direct runtime path.

## Design Rule

If a capability can finish cleanly without preserving runtime state, keep it
direct.
If it needs session continuity, replay, or host-visible recovery, route it
through Harness or the async packages explicitly.
