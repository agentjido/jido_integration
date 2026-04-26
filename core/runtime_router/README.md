# Jido Integration V2 Runtime Router

runtime-control-backed session and stream runtime adapter for the control plane.

## Owns

- authored non-direct runtime routing through `Jido.Integration.V2.RuntimeRouter`
- session reuse and shutdown through `RuntimeRouter.SessionStore`
- the built-in `asm` and `jido_session` driver ids
- translation between authored runtime metadata and `Jido.RuntimeControl` requests
- session-control dispatch from `metadata.session_control.operation` to
  lifecycle/status/cancel/approval Runtime Control callbacks
- translation from accepted governance projections into
  `ExecutionPlane.Admission.Request` values
- fallback ladders over an injected `ExecutionPlane.Runtime.Client`, issuing one
  execution call per acceptable-attestation rung

The current runtime-control-backed runtime graph is intentionally simple: `asm` and
`jido_session` are the two non-direct runtime lanes, and lower-boundary
experiments are carried through the root Execution Plane boundary contracts
rather than raw lane packages.

This package does not host live Execution Plane lanes. The node or remote
runtime-client implementation validates authority, target attestations, and
lane availability. The router owns the policy ladder above that boundary so
the node never silently downgrades within one `execute/2` call.

This package is not the path for CLI-backed inference endpoints. That route is
published by ASM and consumed by the control plane as an inference target
instead of a Runtime Control session/stream capability.

## Session Control Routing

Non-direct capabilities may declare generic session-control intent in authored
metadata:

```elixir
metadata: %{
  session_control: %{operation: :turn | :stream | :start | :status | :cancel | :approve}
}
```

`:turn` and `:stream` keep using the existing Runtime Control run path.
`:start`, `:status`, `:cancel`, and `:approve` are pure control operations and
do not synthesize prompt text. Out-of-band control operations require an
explicit `session_id`; `:cancel` also requires `run_id`, and `:approve` requires
`approval_id` plus `decision`.

## Publication Boundary

This package remains source-repo runtime support for non-direct capabilities.
The default welded `jido_integration` Hex artifact excludes it because it still
depends on unpublished external runtime packages.

## Related Guides

- [Architecture](../../guides/architecture.md)
- [Runtime Model](../../guides/runtime_model.md)
- [Publishing](../../guides/publishing.md)
