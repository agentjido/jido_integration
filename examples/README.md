# Repository Examples

The repo-level examples for the landed CLI inference seam are package-local on
purpose. The root wrapper script just runs those package examples in order.

## Files

- `run_inference_cli_proofs.sh`
  - runs the control-plane CLI endpoint proof example
  - runs the public `apps/inference_ops` proof example
  - keeps the repo-level entrypoint honest without creating a second runtime
    owner at the workspace root
  - the attached-local Ollama proof stays separate because it expects a real
    external daemon

## Related Package Examples

- `core/control_plane/examples/inference_cli_endpoint_baseline.exs`
- `core/asm_runtime_bridge/examples/live_codex_app_server_acceptance.exs`
- `apps/inference_ops/examples/inference_proof.exs`
- `apps/inference_ops/examples/ollama_attach_proof.exs`
