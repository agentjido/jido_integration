# Inference Durability

This package owns the durable truth for the first live inference runtime
family.

## Recording API

Use `Jido.Integration.V2.ControlPlane.invoke_inference/2` when you want the
control plane to resolve, execute, and record an inference attempt end to end.

Use `Jido.Integration.V2.ControlPlane.record_inference_attempt/1` only when
you already have a validated inference attempt summary and need to persist it
directly.

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

The repo still keeps `Run.runtime_class` and `Attempt.runtime_class` on the existing
contract spine for compatibility. The richer inference route classification is
stored in durable output maps and projected later through review metadata.

For live execution, those durable envelopes now also carry:

- the resolved CLI endpoint descriptor when the ASM endpoint route is used
- the resolved endpoint descriptor when one exists
- the backend manifest when a self-hosted backend is involved
- the synthesized lease ref used by the control plane review path
- stream lifecycle summaries derived from the real `req_llm` response

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

The live phase keeps boundaries explicit:

- `req_llm` is the only client layer
- `ASM.InferenceEndpoint` owns CLI endpoint publication
- `self_hosted_inference_core` owns endpoint publication
- `llama_cpp_sdk` owns the first self-hosted backend package
- external authority-loop ownership still stays outside ordinary completion routes

## Proof Surface

Primary coverage lives in:

- `test/jido/integration/v2/control_plane_inference_test.exs`
- `test/jido/integration/v2/control_plane_inference_execution_test.exs`
- `examples/inference_event_baseline.exs`
- `examples/inference_cli_endpoint_baseline.exs`
