# Inference Contracts

This package owns the phase-0 shared inference contract seam.

## Contract Set

The landed modules are:

- `Jido.Integration.V2.InferenceRequest`
- `Jido.Integration.V2.InferenceExecutionContext`
- `Jido.Integration.V2.EndpointDescriptor`
- `Jido.Integration.V2.BackendManifest`
- `Jido.Integration.V2.ConsumerManifest`
- `Jido.Integration.V2.CompatibilityResult`
- `Jido.Integration.V2.InferenceResult`
- `Jido.Integration.V2.LeaseRef`

All of them follow the existing contracts-package rules:

- `contract_version` is `"inference.v1"`
- the durable cross-repo form is a JSON-safe map
- Elixir structs are wrappers around that durable map form
- `new!/1` validates authored input
- `dump/1` emits the durable map form

## Descriptor Rule

`TargetDescriptor` is reused as the durable target advertisement contract.
`EndpointDescriptor` is the execution-ready resolved endpoint for one admitted
attempt.

This split matters:

- `TargetDescriptor` stays durable, reusable, and capability-oriented
- `EndpointDescriptor` is the per-attempt execution shape returned by a route
  or runtime adapter

## Runtime Classification

The inference contracts add:

- `runtime_kind`
- `management_mode`
- `target_class`
- `protocol`
- `checkpoint_policy`
- `authority_source`

These classify how the attempt executes without changing the older
`Run.runtime_class` and `Attempt.runtime_class` enums yet.

## Local Adapter Boundary

`ReqLLMCallSpec` is intentionally absent from this package.
It is a local `jido_integration` adapter shape and not shared durable truth.

## Proof Surface

Primary coverage lives in:

- `test/jido/integration/v2/inference_contracts_test.exs`
- `test/jido/integration/v2/redaction_test.exs`
- `examples/inference_contract_round_trip.exs`
