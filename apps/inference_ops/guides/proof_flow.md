# Proof Flow

`apps/inference_ops` is the hosted proof home for the first live inference
runtime family.

## What It Proves

- cloud inference stays `runtime_kind: :client`
- CLI endpoint inference stays `runtime_kind: :task`
- self-hosted inference stays `runtime_kind: :service`
- all three routes execute through `req_llm`
- the durable inference event minimum is recorded
- `review_packet/2` reconstructs the run from durable truth

## Boundaries

The app remains above the shared platform seam:

- `core/platform` owns the public facade
- `core/control_plane` owns durable inference truth
- `agent_session_manager` owns CLI endpoint publication
- `self_hosted_inference_core` owns reusable service leases
- `llama_cpp_ex` owns the first self-hosted backend package
- `req_llm` stays the singular client layer

## Recommended Usage

Use the app as a permanent proof harness, not as a second control plane.

- pass `req_http_options: [plug: ...]` when you want an offline cloud proof
- pass the default Gemini request or override `:provider` / `:model_id` when
  you want the common-surface CLI endpoint proof
- pass a real or fixture `:boot_spec` when you want a self-hosted proof
- inspect `review_packet/2` after execution instead of rehydrating state from
  private runtime processes
