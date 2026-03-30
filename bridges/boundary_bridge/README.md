# Jido Integration V2 Boundary Bridge

Lower-boundary sandbox bridge package for runtime kernels that live outside the
core `jido_integration` control-plane packages.

This package lives under `bridges/` intentionally:

- it is not a `core/` package
- it is not an `apps/` proof package
- it is the clean monorepo home for the lower sandbox-boundary seam

## Owns

- the `Jido.BoundaryBridge` public package root
- the package boundary where lower sandbox bridge IO types and normalization
  logic will land
- package-local docs, tests, and quality gates for that bridge seam

## Boundary

This package does not own:

- control-plane truth
- auth truth
- durable policy truth
- app-local workflow composition

Those stay in the existing `core/` and `apps/` packages.

## Publication Boundary

This package is a monorepo child package first. It should be treated as
source-repo runtime support until its external dependency boundary is stable
enough to publish independently.

## Related Guides

- [Architecture](../../guides/architecture.md)
- [Runtime Model](../../guides/runtime_model.md)
- [Publishing](../../guides/publishing.md)
