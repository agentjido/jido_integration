# Jido Integration V2 Harness Runtime

Harness-backed session and stream runtime adapter for the control plane.

## Owns

- authored non-direct runtime routing through `Jido.Integration.V2.HarnessRuntime`
- session reuse and shutdown through `HarnessRuntime.SessionStore`
- the built-in `asm` and `jido_session` driver ids
- translation between authored runtime metadata and `Jido.Harness` requests

Target descriptors publish `extensions["boundary"]` as the authored baseline
boundary capability advertisement. Runtime code may combine worker-local facts
with that baseline to build a runtime-merged live capability view before
invoking boundary-backed `asm` or boundary-backed `jido_session`.

## Publication Boundary

This package remains source-repo runtime support for non-direct capabilities.
The default welded `jido_integration` Hex artifact excludes it because it still
depends on unpublished external runtime packages.

## Related Guides

- [Architecture](../../guides/architecture.md)
- [Runtime Model](../../guides/runtime_model.md)
- [Publishing](../../guides/publishing.md)
