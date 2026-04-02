# Inference Review Packets

`Jido.Integration.V2.review_packet/2` reconstructs the live inference runtime
surface from durable control-plane truth.

## End-To-End Flow

The public path is:

1. call `Jido.Integration.V2.invoke_inference/2`
2. let `core/control_plane` execute the request through `req_llm`
3. let `core/control_plane` persist the minimum durable inference event set
4. read the resulting packet back through `Jido.Integration.V2.review_packet/2`

## What Is Projected

When the run and attempt carry the inference contract version in their durable
payloads, the platform synthesizes:

- an inference connector summary
- an inference capability summary
- review metadata derived only from stored run, attempt, and event truth

No registered connector manifest is required for this projection.
The underlying durable inference envelopes remain string-keyed JSON-safe maps;
the review projection normalizes the runtime summary back into the typed
operator-facing packet.

## Classification Rule

The current contracts still constrain `Run.runtime_class` and
`Attempt.runtime_class` to `:direct | :session | :stream`.
Inference review packets keep those compatible values and expose the richer
route classification inside `packet.capability.runtime`:

- `family`
- `runtime_kind`
- `management_mode`
- `target_class`

## Boundary Rule

The inference review path depends only on durable truth. It does not need a
live cloud session, a live self-hosted runtime, or a registered connector
manifest at read time.

## Proof Surface

Primary coverage lives in:

- `test/jido/integration/v2_inference_review_packet_test.exs`
- `test/jido/integration/v2_inference_invoke_test.exs`
- `examples/inference_review_packet.exs`
