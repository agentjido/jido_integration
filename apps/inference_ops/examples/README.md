# Inference Ops Examples

- `inference_proof.exs` runs one offline cloud proof, one offline CLI proof,
  and one offline spawned self-hosted proof through
  `Jido.Integration.V2.Apps.InferenceOps`
- the example also reads the durable packet back through `review_packet/2`
- `ollama_attach_proof.exs` runs the honest attached-local proof against an
  already running Ollama daemon through `run_ollama_attach_proof/1`
