# Inference Review Packets

`Jido.Integration.V2.review_packet/2` now reconstructs the phase-0 inference
baseline from durable control-plane truth.

## What Is Projected

When the run and attempt carry the inference contract version in their durable
payloads, the platform synthesizes:

- an inference connector summary
- an inference capability summary
- review metadata derived only from stored run, attempt, and event truth

No registered connector manifest is required for this phase-0 projection.

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

The inference review path does not depend on live `jido_os`, live CLI
publishers, or live self-hosted services. It only needs the durable baseline
written by `core/control_plane`.

## Proof Surface

Primary coverage lives in:

- `test/jido/integration/v2_inference_review_packet_test.exs`
- `examples/inference_review_packet.exs`
