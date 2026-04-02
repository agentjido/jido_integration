# Inference Baseline

Phase 1 turns the inference baseline into the first live `:inference` runtime
family.

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

Each inference contract `dump/1` now emits a string-keyed JSON-safe map so the
cross-repo durable form is explicit instead of inferred from Elixir structs.

## Live Execution Path

`core/control_plane` now owns the first end-to-end inference adapter.

It:

- builds `InferenceExecutionContext` and `ConsumerManifest`
- builds a local `ReqLLMCallSpec` from `InferenceRequest`,
  `InferenceExecutionContext`, and either cloud route data or an
  `EndpointDescriptor`
- executes cloud provider calls through `req_llm`
- resolves self-hosted endpoints through `self_hosted_inference_core`
- executes those self-hosted OpenAI-compatible endpoints through `req_llm`

This keeps the client layer singular while keeping service-runtime ownership
below the control plane.

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

For streaming attempts, `checkpoint_policy` is admitted through
`InferenceExecutionContext.streaming_policy` and enforced when the durable
stream lifecycle summary is recorded.

## Review Behavior

`core/platform` now projects live inference runs through `review_packet/2` even
when no connector manifest has been registered for the inference surface.
The projection synthesizes an inference connector and capability summary from
durable run and attempt truth.

The repo still keeps `Run.runtime_class` and `Attempt.runtime_class` on the
existing
`[:direct, :session, :stream]` contract spine for compatibility with the rest
of the repo. The inference-specific classification is exposed through the
projected review metadata as `runtime.family: :inference`.

## Proof Surface

The landed proof surface is now split between package-local examples and an
app-level proof harness:

- `core/contracts/test/jido/integration/v2/inference_contracts_test.exs`
- `core/contracts/examples/inference_contract_round_trip.exs`
- `core/control_plane/test/jido/integration/v2/control_plane_inference_test.exs`
- `core/control_plane/test/jido/integration/v2/control_plane_inference_execution_test.exs`
- `core/control_plane/examples/inference_event_baseline.exs`
- `core/platform/test/jido/integration/v2_inference_review_packet_test.exs`
- `core/platform/test/jido/integration/v2_inference_invoke_test.exs`
- `core/platform/examples/inference_review_packet.exs`
- `apps/inference_ops`

The cloud lane stays offline with `Req.Test` fixtures. The self-hosted lane
uses `llama_cpp_ex` and the shared fake `llama-server` fixture so the northbound
endpoint contract remains honest without requiring a real model download.

## Deliberate Non-Goals

This phase still does not require:

- a live `jido_os` dependency
- live CLI endpoint publication
- a separate shared `ReqLLMCallSpec` contract repo
- turning `req_llm` into a runtime manager or policy engine

`ReqLLMCallSpec` stays local to `jido_integration` adapter code. It is not a
durable shared cross-repo contract.
