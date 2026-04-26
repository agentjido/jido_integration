# Jido Integration V2 Runtime ASM Bridge

Integration-owned `Jido.RuntimeControl.RuntimeDriver` projection for the authored
`asm` driver.

This package is the permanent home for the external ASM-to-Runtime Control bridge. It
keeps ASM's pid-based session references inside a private store keyed by
`session_id`, so public Session Control handles stay stable and transport-safe
while `jido_integration` itself stays at the Runtime Control seam.

## Responsibilities

- publish the `asm` Runtime Control driver used by the control plane
- normalize ASM events and results into Runtime Control IR structs
- preserve external-runtime session reuse without leaking kernel-private refs
- pass Codex app-server host-tool specs and provider continuations into ASM
- author generic execution-surface input from runtime, target, policy, and
  lease context without exposing adapter-module identity
- localize the `agent_session_manager` dependency so
  connector packages can keep their shared dependency surface at
  `jido_runtime_control`

## Carriage

The bridge authors `execution_surface` and `execution_environment`
independently.

`execution_surface` carries only attach and transport placement data:

- `surface_kind`
- `transport_options`
- `lease_ref`
- `surface_ref`
- `target_id`
- `boundary_class`
- `observability`

`execution_environment` carries runtime workspace and policy context:

- `workspace_root`
- `allowed_tools`
- `approval_posture`
- `permission_mode`

It does not emit public `transport_module` selection. For ephemeral surfaces,
session reuse identity now widens with `surface_kind`, `lease_ref`, and
`surface_ref` so leased or short-lived placements do not reuse stale sessions.

Request `cwd` remains a generic launch option. The bridge does not project it
into `execution_environment.workspace_root`.

This means future core-owned surfaces continue to flow through the same bridge
shape. `asm_runtime_bridge` authors placement and environment separately but
does not branch on transport-family internals. Session handles and status
details now also carry the Wave 5 boundary packet groups under
`metadata["boundary"]` / `details["boundary"]` so downstream session-bearing
lanes receive attach and descriptor carriage without rebuilding it locally.

## Codex App-Server Lane

The bridge promotes Codex app-server execution through the normal Runtime
Control seam:

- callers request the SDK lane with `provider: :codex`, `lane: :sdk`, and
  `app_server: true`
- `RunRequest.host_tools` is forwarded to ASM as Codex app-server dynamic tools
- `RunRequest.continuation` is forwarded as provider-native resume intent
- run-level `tools` executors are passed through for automatic host-tool
  responses
- non-Codex providers receive explicit validation errors for `host_tools` or
  `app_server` requests rather than silently falling back

ASM host-tool events are projected into `ExecutionEvent` values with
`provider_session_id`, `provider_turn_id`, `provider_request_id`,
`provider_item_id`, `provider_tool_call_id`, `provider_message_id`,
`tool_name`, and `approval_id` where available. Raw provider payloads are
reduced to redacted evidence envelopes before crossing into Runtime Control.

Live acceptance:

```bash
cd core/asm_runtime_bridge
JIDO_INTEGRATION_WORKSPACE="${JIDO_INTEGRATION_WORKSPACE:-$PWD/../..}"
/home/home/scripts/with_bash_secrets mix run examples/live_codex_app_server_acceptance.exs -- --cwd "$JIDO_INTEGRATION_WORKSPACE"
```

Expected output includes `jido_codex_app_server_live=ok`,
`session_control_status=ready`, host-tool request/completion evidence, and the
deterministic final marker text.

## Runtime Scope

This package is now direct about its scope:

- `RuntimeControlDriver` carries authored execution-surface and execution-environment
  input into ASM without exposing adapter modules
- streamed runs, interruption, terminal failures, and session shutdown stay on
  the existing ASM session surface
- lower-boundary lifecycle work is not part of this package's dependency graph
  or public behavior

## Boundary

This package does not own control-plane truth, provider SDK logic, durable
artifact policy, or lower-boundary lifecycle truth. It only projects ASM into
the shared Runtime Control contract above `cli_subprocess_core`.

## Related Guides

- [Runtime Model](../../guides/runtime_model.md)
- [Architecture](../../guides/architecture.md)
