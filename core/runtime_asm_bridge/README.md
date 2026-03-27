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

## Phase C Carriage

The bridge now authors only generic execution-surface data:

- `surface_kind`
- `transport_options`
- `workspace_root`
- `allowed_tools`
- `approval_posture`
- `permission_mode`
- `lease_ref`
- `surface_ref`
- `target_id`
- `boundary_class`
- `observability`

It does not emit public `transport_module` selection. For ephemeral surfaces,
session reuse identity now widens with `surface_kind`, `lease_ref`, and
`surface_ref` so leased or short-lived placements do not reuse stale sessions.

## Boundary

This package does not own control-plane truth, provider SDK logic, or durable
artifact policy. It only projects ASM into the shared Harness contract above
`/home/home/p/g/n/cli_subprocess_core`.

## Related Guides

- [Runtime Model](../../guides/runtime_model.md)
- [Architecture](../../guides/architecture.md)
