# Jido Integration V2 Inference Ops

Reference proof app for the first live `:inference` runtime family.

This app stays thin on purpose. It does not own provider execution, endpoint
publication, or durable review logic. It composes the public
`Jido.Integration.V2.invoke_inference/2` facade into four proof
flows:

- cloud provider execution through `req_llm`
- CLI endpoint execution through `ASM.InferenceEndpoint` plus `req_llm`
- self-hosted spawned `llama_cpp_ex` endpoint execution through `req_llm`
- self-hosted attached `ollama` endpoint execution through `req_llm`

## Public Entry Points

- `run_cloud_proof/1`
- `run_cli_proof/1`
- `run_self_hosted_proof/1`
- `run_ollama_attach_proof/1`
- `register_self_hosted_backend/0`
- `register_ollama_backend/0`
- `review_packet/2`

`run_cloud_proof/1` builds a cloud `InferenceRequest` and executes it through
the public facade. `run_cli_proof/1` builds a `target_class: "cli_endpoint"`
request and drives it through `ASM.InferenceEndpoint` plus `req_llm`.
`run_self_hosted_proof/1` requires a `:boot_spec` and then drives the
self-hosted spawned route through `self_hosted_inference_core`,
`llama_cpp_ex`, and `req_llm` without reclaiming runtime ownership inside the
app layer. `run_ollama_attach_proof/1` requires a `:root_url` and drives the
attached-local route through `self_hosted_inference_core`, the built-in
`ollama` adapter, and `req_llm`.

## Proof Surface

- `test/jido/integration/v2/apps/inference_ops_test.exs`
- `examples/inference_proof.exs`
- `examples/ollama_attach_proof.exs`

The package tests keep the cloud lane offline with `Req.Test` while the
self-hosted spawned lane uses the shared fake `llama-server` fixture script
published by `llama_cpp_ex`. The attached-local lane stays offline in tests by
stubbing the Ollama readiness/health seam and the `req_llm` client call
separately. The CLI lane uses a fake ASM backend under the real
endpoint-publication seam and prefers Gemini as the first common-surface proof
provider. Use `examples/ollama_attach_proof.exs` when you want the honest
externally managed attach path against an already running Ollama daemon.
