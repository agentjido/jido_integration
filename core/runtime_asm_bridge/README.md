# Jido Integration V2 Runtime ASM Bridge

Integration-owned `Jido.Harness.RuntimeDriver` projection for the authored
`asm` driver.

This package is the permanent home for the external ASM-to-Harness bridge. It
keeps ASM's pid-based session references inside a private store keyed by
`session_id`, so public Session Control handles stay stable and transport-safe
while `jido_integration` itself stays at the Harness seam.

## Responsibilities

- publish the `asm` Harness runtime driver used by the control plane
- normalize ASM events and results into Harness Session Control IR structs
- preserve external-runtime session reuse without leaking kernel-private refs
- author generic execution-surface input from runtime, target, policy, and
  lease context without exposing adapter-module identity
- localize the `/home/home/p/g/n/agent_session_manager` dependency so
  connector packages can keep their shared dependency surface at
  `/home/home/p/g/n/jido_harness`

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
shape. `runtime_asm_bridge` authors placement and environment separately but
does not branch on transport-family internals.

## Phase D SSH Proof

The first alternate execution surface is now proven through this unchanged
bridge seam:

- `HarnessDriver` carries final `:ssh_exec` surface input without exposing
  adapter modules
- streamed runs, interruption, terminal failures, and session shutdown all
  work end to end over the SSH-backed core lane
- execution-event error payloads keep the raw bridge-visible fields and also
  expose `kind` when the upstream payload carries an error `code`
- guest bridge remains explicitly deferred

## Boundary

This package does not own control-plane truth, provider SDK logic, or durable
artifact policy. It only projects ASM into the shared Harness contract above
`/home/home/p/g/n/cli_subprocess_core`.

## Related Guides

- [Runtime Model](../../guides/runtime_model.md)
- [Architecture](../../guides/architecture.md)
