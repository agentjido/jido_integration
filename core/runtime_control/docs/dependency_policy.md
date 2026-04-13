# Jido Runtime Control Dependency Policy

This policy governs `jido_runtime_control` in `core/runtime_control`.

## Boundary Direction

For the Session Control surface, the dependency direction is:

- integration/composition packages may depend on `jido_runtime_control`
- runtime kernels may implement `Jido.RuntimeControl.RuntimeDriver`
- bridge packages may project lower-boundary systems into that driver contract

In practice that means:

- `core/runtime_control` owns the shared IR and runtime-driver behaviour
- concrete runtime packages register under `:runtime_drivers`
- kernel-private refs such as pids and monitor refs must stay out of the public
  IR

## Baseline Versions

- Elixir: `~> 1.19`
- Jido core line: `~> 2.0.0-rc.5`
- Zoi: `~> 0.17`
- Splode: `~> 0.3.0`

## Monorepo Posture

Inside `jido_integration`, keep `core/runtime_control` aligned with the root
monorepo workflow:

- validate from the repo root
- prefer internal child-package dependencies over ad hoc local path workflows
- keep package boundaries explicit for runtime drivers and runtime bridges

## External Dependencies

Use direct external dependencies only when they materially support the retained
runtime-driver seam.

When temporary git or override dependencies are required:

- document why in the commit or PR
- prefer the narrowest affected package set
- remove them as soon as a compatible Hex release exists
- verify removal with compile, test, and the root quality gates

## Removal Criteria

A temporary dependency exception should be removed once:

1. A compatible Hex release is available.
2. All dependent repos compile and test against the released version.
3. No regressions appear in runtime-driver contract tests or root `mix ci`.
