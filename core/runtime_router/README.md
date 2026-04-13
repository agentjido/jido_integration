# Jido Integration V2 Runtime Router

runtime-control-backed session and stream runtime adapter for the control plane.

## Owns

- authored non-direct runtime routing through `Jido.Integration.V2.RuntimeRouter`
- session reuse and shutdown through `RuntimeRouter.SessionStore`
- the built-in `asm` and `jido_session` driver ids
- translation between authored runtime metadata and `Jido.RuntimeControl` requests

The current runtime-control-backed runtime graph is intentionally simple: `asm` and
`jido_session` are the two non-direct runtime lanes, and lower-boundary
experiments are not part of this package's active dependency path.

This package is not the path for CLI-backed inference endpoints. That route is
published by ASM and consumed by the control plane as an inference target
instead of a Runtime Control session/stream capability.

## Publication Boundary

This package remains source-repo runtime support for non-direct capabilities.
The default welded `jido_integration` Hex artifact excludes it because it still
depends on unpublished external runtime packages.

## Related Guides

- [Architecture](../../guides/architecture.md)
- [Runtime Model](../../guides/runtime_model.md)
- [Publishing](../../guides/publishing.md)
