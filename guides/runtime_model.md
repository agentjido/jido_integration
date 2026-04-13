# Runtime Model

Jido Integration now proves four execution runtime families: direct, session,
stream, and inference.

## Direct Runtime

Direct capabilities execute through `core/direct_runtime` and a connector's
provider SDK. This path is for request/response work that does not need a
runtime-control-managed session or streaming state.

Use it when:

- one request maps to one bounded execution
- the connector can finish cleanly without preserving runtime state
- you want the simplest dependency and review story

## Runtime-Control-Backed Runtime

Sessioned and streamed capabilities go through `Jido.RuntimeControl`.

- `core/runtime_router` is the authored adapter layer used by the control
  plane for all non-direct capability execution.
- `asm` is projected by `core/asm_runtime_bridge` into the
  `agent_session_manager` and `cli_subprocess_core` lane.
- `jido_session` is projected by `core/session_runtime` via
  `Jido.Session.RuntimeControlDriver`.

This is the stable non-direct seam for long-running or stateful execution.

Use it when:

- work must reuse a runtime-managed session
- a target needs explicit runtime-driver compatibility
- the capability publishes session or stream behavior honestly rather than
  pretending to be direct

The current runtime-control-backed model stops at those two lanes. Lower-boundary
experiments are intentionally outside the active core runtime path.

Important distinction:

- CLI-backed inference does not require `core/runtime_router` or
  `core/session_runtime`; it flows through `ASM.InferenceEndpoint` and then
  through the ordinary inference endpoint path in the control plane.
- `core/runtime_router` and `core/session_runtime` matter when a capability is
  honestly sessioned or streamed and must execute on the Runtime Control seam.

## Hosted Async And Webhooks

Hosted webhook registration and async replay are separate package surfaces.
They live in `core/webhook_router` and `core/dispatch_runtime`, not in the
facade package and not in the direct runtime path.

## Inference Runtime

Inference is now a first-class runtime family on the public facade.

- cloud routes execute as `runtime_kind: :client` against provider-managed
  endpoints
- self-hosted routes execute as `runtime_kind: :service` after endpoint
  resolution through `self_hosted_inference_core`
- both routes execute the data-plane call through `req_llm`
- `core/control_plane` records the durable inference event minimum
- `core/platform` exposes both `invoke_inference/2` and `review_packet/2`
- CLI-backed inference endpoints are published by ASM and consumed here as
  inference targets, not as Runtime Control session connectors
- lower spawned-service mechanics sit on `execution_plane`, but lease lineage,
  attachability, and service publication remain above that substrate

For compatibility with the existing repo, `Run.runtime_class` and
`Attempt.runtime_class` stay on `:direct | :session | :stream`.
Inference-specific route truth is exposed separately through:

- `runtime.family`
- `runtime_kind`
- `management_mode`
- `target_class`

## Design Rule

If a capability can finish cleanly without preserving runtime state, keep it
direct.
If it needs session continuity, replay, or host-visible recovery, route it
through Runtime Control or the async packages explicitly.
If it is an inference request, keep request execution in `req_llm` and keep
runtime publication below the control plane.

## Wave 1 Lower-Boundary Freeze

Wave 1 also freezes the lower-boundary contract vocabulary used around these
runtime families:

- `ExecutionIntentEnvelope.v1`
- `HttpExecutionIntent.v1`
- `ProcessExecutionIntent.v1`
- `JsonRpcExecutionIntent.v1`
- `ExecutionRoute.v1`
- `AttachGrant.v1`
- `ExecutionEvent.v1`
- `ExecutionOutcome.v1`

In this repo, those contracts are carried and interpreted through durable
Spine ownership. They are not exposed as raw lower-package APIs.

The detailed family-facing minimal-lane payload interiors are still
provisional until Wave 3 prove-out. The ownership split is already frozen:

- Brain decides policy and topology direction
- Spine persists durable meaning
- Execution Plane emits raw execution facts
