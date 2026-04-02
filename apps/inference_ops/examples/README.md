# Inference Ops Examples

- `inference_proof.exs` runs one offline cloud proof, one offline CLI proof,
  and one offline spawned self-hosted proof through
  `Jido.Integration.V2.Apps.InferenceOps`
- the example also reads the durable packet back through `review_packet/2`
- `ollama_attach_proof.exs` runs the honest attached-local proof against an
  already running Ollama daemon through `run_ollama_attach_proof/1`

Run the offline proof with:

```bash
mix run examples/inference_proof.exs
```

Run the attached-local proof with:

```bash
OLLAMA_ROOT_URL=http://127.0.0.1:11434 \
OLLAMA_MODEL=llama3.2 \
mix run examples/ollama_attach_proof.exs
```

The attach example expects an already running Ollama daemon and an available
model. It does not move daemon ownership into the BEAM.
