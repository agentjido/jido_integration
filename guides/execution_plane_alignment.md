# Execution Plane Alignment

This guide freezes the lower-boundary packet vocabulary and the Wave 5 durable
session-carriage vocabulary between the Brain-side packet snapshot, the Spine,
the Execution Plane workspace, and the facade/session layers.

## Ownership

- `jido_os` remains the Brain and authors `AuthorityDecision.v1`
- `jido_integration` remains the Spine and owns durable meaning
- `execution_plane` owns lower runtime mechanics and raw execution facts

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
- `jido_harness`
- `agent_session_manager`

## What The Spine Owns

In this repo specifically:

- `BoundarySessionDescriptor.v1` is durable Spine truth
- `ExecutionRoute.v1` is durable route choice, replay input, and reconciliation state
- durable service descriptors, lease lineage, and attachability remain Spine or
  family-kit truth above lower process state
- attach grants, approval lineage, callback truth, and credential-handle
  carriage remain Spine concerns
- `ExecutionEvent.v1` and `ExecutionOutcome.v1` are consumed as raw lower
  facts, not as durable business meaning on their own
- boundary-backed metadata now keeps those Wave 5 semantics explicit under:
  `descriptor`, `route`, `attach_grant`, `replay`, `approval`, `callback`,
  and `identity`

## Public-Surface Rule

The stable northbound surface remains:

- `Jido.Integration.V2`
- the current `core/contracts` public IR for platform semantics

This repo may map or carry lower-boundary packet shapes, but it must not turn
raw `execution_plane` package names into the public platform API.

That rule also applies to self-hosted service runtime work: higher layers may
carry durable service descriptors and attach grants, but they must not expose
raw `ExecutionPlane.Process.Transport` state as the product boundary.

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
