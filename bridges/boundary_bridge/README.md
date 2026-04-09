# Jido Integration V2 Boundary Bridge

Deprecated package. `boundary_bridge` is no longer part of the default core
runtime path or workspace CI. It remains in-repo only as legacy reference code
while the replacement lower-boundary runtime is designed separately.

Lower-boundary sandbox bridge package for runtime kernels that live outside the
core `jido_integration` control-plane packages.

This package lives under `bridges/` intentionally:

- it is not a `core/` package
- it is not an `apps/` proof package
- it is the clean monorepo home for the lower sandbox-boundary seam

## Owns

- the `Jido.BoundaryBridge` public package root
- typed lower-boundary IO:
  `Jido.BoundaryBridge.AllocateBoundaryRequest`,
  `Jido.BoundaryBridge.ReopenBoundaryRequest`, and
  `Jido.BoundaryBridge.BoundarySessionDescriptor`
- the narrow public bridge API for allocate, reopen, readiness waiting, and
  attach-metadata plus durable boundary-metadata projection
- request translation, descriptor normalization, typed extension accessors, and
  bridge-facing error normalization
- package-local docs, tests, and quality gates for that bridge seam

## Boundary

This package does not own:

- control-plane truth
- auth truth
- durable policy truth
- app-local workflow composition

Those stay in the existing `core/` and `apps/` packages.

## Contract Notes

- `AllocateBoundaryRequest` carries `allocation_ttl_ms` so startup-orphan
  reaping stays below the public bridge seam
- `BoundarySessionDescriptor` emits `descriptor_version: 1` in this packet's
  rollout
- consumers fail closed on unsupported `descriptor_version` values rather than
  assuming future shapes
- descriptors keep Wave 5 route, replay, callback, approval, attach-grant, and
  identity carriage explicit instead of burying them in transport-local maps
- `attach.mode == :not_applicable` is valid and keeps the bridge kernel-neutral
- `policy_intent_echo` is a lossy bridge-local projection, not governance truth
- readiness waiting currently polls by `boundary_session_id` through the lower
  boundary's public status seam
- the attachable readiness wait is non-blocking for kernel-facing callers and
  uses `Task.yield/2` plus explicit shutdown-and-cleanup rather than
  `Task.await/2`
- runtime claim and heartbeat stay explicit bridge operations so startup TTL
  handoff remains below the kernel seam
- `project_boundary_metadata/1` publishes the named durable metadata groups
  consumed above the bridge: `descriptor`, `route`, `attach_grant`, `replay`,
  `approval`, `callback`, and `identity`

## Publication Boundary

This package is a monorepo child package first. It should be treated as
source-repo runtime support until its external dependency boundary is stable
enough to publish independently.

## Related Guides

- [Architecture](../../guides/architecture.md)
- [Runtime Model](../../guides/runtime_model.md)
- [Publishing](../../guides/publishing.md)
