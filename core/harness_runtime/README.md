# Jido Integration V2 Harness Runtime

Harness-backed session and stream runtime adapter for the control plane.

## Owns

- authored non-direct runtime routing through `Jido.Integration.V2.HarnessRuntime`
- session reuse and shutdown through `HarnessRuntime.SessionStore`
- the built-in `asm` and `jido_session` driver ids
- translation between authored runtime metadata and `Jido.Harness` requests

The current harness-backed runtime graph is intentionally simple: `asm` and
`jido_session` are the two non-direct runtime lanes, and lower-boundary
experiments are not part of this package's active dependency path.

## Publication Boundary

This package remains source-repo runtime support for non-direct capabilities.
The default welded `jido_integration` Hex artifact excludes it because it still
depends on unpublished external runtime packages.

## Related Guides

- [Architecture](../../guides/architecture.md)
- [Runtime Model](../../guides/runtime_model.md)
- [Publishing](../../guides/publishing.md)
