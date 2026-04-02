# CLI Inference Endpoints

`core/control_plane` now consumes CLI-backed endpoint publication through
`ASM.InferenceEndpoint`.

## Route Shape

The control plane treats the returned descriptor as an ordinary
endpoint-shaped inference target:

- `target_class: :cli_endpoint`
- `protocol: :openai_chat_completions`
- `runtime_kind: :task`
- `management_mode: :jido_managed`

`ReqLLMCallSpec.from_endpoint/3` then turns that descriptor into the single
client call shape used by the live inference path.

## Ownership Split

The control plane does not invent CLI runtime facts itself.

It consumes:

- `EndpointDescriptor`
- `CompatibilityResult`
- backend-manifest metadata published by ASM

ASM remains the owner of:

- built-in CLI provider publication
- lease-backed endpoint lifecycle
- completion versus streaming compatibility
- rejection of tool-bearing or agent-loop-shaped requests on the endpoint seam

## Durable Truth

When the CLI route is selected, the durable attempt output records:

- the endpoint descriptor returned by ASM
- the synthesized `LeaseRef`
- the backend manifest reconstructed from ASM metadata
- `compatibility_result.metadata.route == :cli`

That keeps review and replay consumers honest about the fact that the control
plane executed through a published CLI endpoint rather than a cloud model or a
self-hosted service lease.

## Capability Boundary

ASM publishes:

- `cli_completion_v1`
- `cli_streaming_v1`
- `cli_agent_v2`

The control-plane endpoint route consumes only the first two. Agent-loop
capability publication can still be visible in metadata without leaking tool
execution into ordinary completion requests.

Gemini and Amp remain common-surface-only providers on this path unless ASM
gains an intentional provider-native extension seam later.

## Proof Surface

- `test/jido/integration/v2/control_plane_inference_execution_test.exs`
- `examples/inference_cli_endpoint_baseline.exs`
