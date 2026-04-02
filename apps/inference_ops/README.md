# Jido Integration V2 Inference Ops

Reference proof app for the first live `:inference` runtime family.

This app stays thin on purpose. It does not own provider execution, endpoint
publication, or durable review logic. It composes the public
`Jido.Integration.V2.invoke_inference/2` facade into two permanent proof flows:

- cloud provider execution through `req_llm`
- self-hosted `llama_cpp_ex` endpoint execution through `req_llm`

## Public Entry Points

- `run_cloud_proof/1`
- `run_self_hosted_proof/1`
- `register_self_hosted_backend/0`
- `review_packet/2`

`run_cloud_proof/1` builds a cloud `InferenceRequest` and executes it through
the public facade. `run_self_hosted_proof/1` requires a `:boot_spec` and then
drives the self-hosted route through `self_hosted_inference_core`,
`llama_cpp_ex`, and `req_llm` without reclaiming runtime ownership inside the
app layer.

## Proof Surface

- `test/jido/integration/v2/apps/inference_ops_test.exs`
- `examples/inference_proof.exs`

The package tests keep the cloud lane offline with `Req.Test` while the
self-hosted lane uses the shared fake `llama-server` fixture script published by
`llama_cpp_ex`.
