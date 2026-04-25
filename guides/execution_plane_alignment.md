# Execution Plane Alignment

This guide freezes the lower-boundary packet vocabulary and the Wave 5 durable
session-carriage vocabulary between the Brain-side packet snapshot, the lower
acceptance gateway, the Execution Plane workspace, and the facade/session
layers.

## Ownership

- the Brain-side authority layer authors `AuthorityDecision.v1`
- `mezzanine` owns substrate truth, orchestration state, and recovery posture
- `jido_integration` remains the lower acceptance gateway and lower-boundary
  contract carrier
- `execution_plane` owns lower runtime mechanics and raw execution facts

Northbound operator products such as Switchyard must sit above both:

- `jido_integration` for durable runs, boundary sessions, attach grants,
  review, retry, and auth or target truth
- `execution_plane` for live terminal, PTY, attach, and transport mechanics

That means this repo may carry lower-boundary contracts, but it must not
become a thin re-export of `execution_plane/*` packages.

## Frozen Packet Vocabulary

The canonical carried contract names are:

- `AuthorityDecision.v1`
- `BoundarySessionDescriptor.v1`
- `ExecutionIntentEnvelope.v1`
- `ExecutionRoute.v1`
- `AttachGrant.v1`
- `CredentialHandleRef.v1`
- `ExecutionEvent.v1`
- `ExecutionOutcome.v1`

The same names must appear in docs and examples across:

- the packet-local Brain contract snapshot
- `execution_plane`
- `jido_integration`
- `jido_runtime_control`
- `agent_session_manager`

## What The Lower Acceptance Gateway Owns

In this repo specifically:

- `BoundarySessionDescriptor.v1` is the durable lower-gateway session
  descriptor record
- `ExecutionRoute.v1` is the durable lower-gateway route, replay-input, and
  reconciliation-input record
- durable service descriptors, lease lineage, and attachability remain
  lower-gateway or family-kit records above lower process state
- governance projections require `sandbox.acceptable_attestation`; the list is
  carried into gateway/runtime shadows and then into Execution Plane admission
  requests
- attach grants, approval lineage, callback truth, and credential-handle
  carriage remain lower-gateway concerns
- `ExecutionEvent.v1` and `ExecutionOutcome.v1` are consumed as raw lower
  facts, not as durable business meaning on their own
- boundary-backed metadata now keeps those Wave 5 semantics explicit under:
  `descriptor`, `route`, `attach_grant`, `replay`, `approval`, `callback`,
  and `identity`

## Public-Surface Rule

The stable northbound surface remains:

- `Jido.Integration.V2`
- the current `core/contracts` public IR for platform semantics

That northbound surface now explicitly includes durable operator reads and
attachability helpers such as `runs/1`, `boundary_sessions/1`,
`attach_grants/1`, and `issue_attach_grant/2`.

This repo may map or carry lower-boundary packet shapes, but it must not turn
raw `execution_plane` package names into the public platform API.

That rule also applies to self-hosted service runtime work: higher layers may
carry durable service descriptors and attach grants, but they must not expose
raw `ExecutionPlane.Process.Transport` state as the product boundary.

`core/runtime_router` may depend on the root `execution_plane` contracts to
build `ExecutionPlane.Admission.Request` values and to call an injected
`ExecutionPlane.Runtime.Client`. It must not expose lane packages as the
public `Jido.Integration.V2` API.

Fallback ladders are owned here, not inside the node. A multi-attestation
policy is executed as separate runtime-client calls, one acceptable-attestation
rung at a time, so each rejection and final success remains durable and
auditable.

## Provisional Minimal-Lane Shapes

The family-specific lower intent names are already frozen:

- `HttpExecutionIntent.v1`
- `ProcessExecutionIntent.v1`
- `JsonRpcExecutionIntent.v1`

Their payload interiors remain provisional until Wave 3 prove-out. Wave 1 only
freezes:

- the names
- lineage carriage
- ownership rules
- surface-exposure rules
