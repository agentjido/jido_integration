# Inference Durability

This package owns the phase-0 durable inference attempt baseline.

## Recording API

Use `Jido.Integration.V2.ControlPlane.record_inference_attempt/1` to persist a
validated inference attempt summary.

The spec is built from:

- `InferenceRequest`
- `InferenceExecutionContext`
- `ConsumerManifest`
- `CompatibilityResult`
- `InferenceResult`

Optional inputs are:

- `EndpointDescriptor`
- `BackendManifest`
- `LeaseRef`
- stream lifecycle summaries

## Durable Record Mapping

The recorder writes:

- a `Run`
- an `Attempt`
- the ordered minimum inference event sequence
- string-keyed durable inference envelopes inside `run.input`, `run.result`,
  and `attempt.output`

Phase 0 keeps `Run.runtime_class` and `Attempt.runtime_class` on the existing
contract spine for compatibility. The richer inference route classification is
stored in durable output maps and projected later through review metadata.

## Minimum Event Set

Every inference attempt records:

- `inference.request_admitted`
- `inference.attempt_started`
- `inference.compatibility_evaluated`
- `inference.target_resolved`
- optional stream lifecycle events
- one terminal event

Streaming attempts additionally record:

- `inference.stream_opened`
- zero or more `inference.stream_checkpoint`
- `inference.stream_closed`

`stream_opened.checkpoint_policy` is not caller-invented runtime trivia.
The recorder copies and enforces it from the admitted
`InferenceExecutionContext.streaming_policy`.

## Boundary Rule

This phase does not require live `jido_os`, CLI runtime, or self-hosted
runtime integration. The recorder accepts the normalized durable summaries that
those future paths will emit.

## Proof Surface

Primary coverage lives in:

- `test/jido/integration/v2/control_plane_inference_test.exs`
- `examples/inference_event_baseline.exs`
