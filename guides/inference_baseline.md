# Inference Baseline

Phase 0 lands the inference contract set, the minimum durable inference event
model, and package-local proof scaffolding without requiring live runtime
integration.

## What Landed

Shared contracts now live in `core/contracts`:

- `InferenceRequest`
- `InferenceExecutionContext`
- `EndpointDescriptor`
- `BackendManifest`
- `ConsumerManifest`
- `CompatibilityResult`
- `InferenceResult`
- `LeaseRef`

`TargetDescriptor` remains the shared durable target advertisement contract.
Inference reuses it directly instead of introducing a parallel durable target
shape.

## Durable Control-Plane Truth

`core/control_plane` now records the minimum inference attempt truth:

- admitted request identity
- compatibility outcome
- resolved endpoint summary
- optional stream lifecycle summaries
- terminal result
- usage and finish metadata when available

The minimum durable event set is:

- `inference.request_admitted`
- `inference.attempt_started`
- `inference.compatibility_evaluated`
- `inference.target_resolved`
- `inference.stream_opened`
- `inference.stream_checkpoint`
- `inference.stream_closed`
- one of `inference.attempt_completed`, `inference.attempt_failed`, or
  `inference.attempt_cancelled`

## Review Behavior

`core/platform` now projects inference runs through `review_packet/2` even
when no connector manifest has been registered for the inference baseline.
The projection synthesizes an inference connector and capability summary from
durable run and attempt truth.

Phase 0 keeps `Run.runtime_class` and `Attempt.runtime_class` on the existing
`[:direct, :session, :stream]` contract spine for compatibility with the rest
of the repo. The inference-specific classification is exposed through the
projected review metadata as `runtime.family: :inference`.

## Deliberate Non-Goals

Phase 0 does not require:

- a live `jido_os` dependency
- live `req_llm` execution
- live CLI endpoint publication
- live self-hosted endpoint publication

`ReqLLMCallSpec` stays local to `jido_integration` adapter code. It is not a
durable shared cross-repo contract.

## Proof Surface

The landed proof baseline is package-local:

- `core/contracts/test/jido/integration/v2/inference_contracts_test.exs`
- `core/contracts/examples/inference_contract_round_trip.exs`
- `core/control_plane/test/jido/integration/v2/control_plane_inference_test.exs`
- `core/control_plane/examples/inference_event_baseline.exs`
- `core/platform/test/jido/integration/v2_inference_review_packet_test.exs`
- `core/platform/examples/inference_review_packet.exs`

These proofs exercise cloud, self-hosted, CLI-backed, and failure/cancellation
shapes without introducing live runtime dependencies before the control-plane
baseline is stable.
