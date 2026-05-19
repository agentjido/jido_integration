Application.ensure_all_started(:inets)
Application.ensure_all_started(:ssl)

alias Jido.Integration.V2.Apps.InferenceOps

{opts, _args, invalid} =
  OptionParser.parse(System.argv(),
    strict: [
      root_url: :string,
      model_id: :string
    ]
  )

if invalid != [] do
  raise ArgumentError,
        "invalid options for ollama attach proof: #{inspect(invalid)}"
end

root_url =
  Keyword.get_lazy(opts, :root_url, fn ->
    SelfHostedInferenceCore.Ollama.AttachSpec.default_root_url()
  end)

model_id = Keyword.get(opts, :model_id, "llama3.2")

case InferenceOps.run_ollama_attach_proof(
       root_url: root_url,
       model_id: model_id,
       run_id: "run-inference-ops-ollama-attach-example-1",
       decision_ref: "decision-inference-ops-ollama-attach-example-1",
       trace_id: "trace-inference-ops-ollama-attach-example-1",
       ttl_ms: 30_000
     ) do
  {:ok, result} ->
    {:ok, packet} =
      InferenceOps.review_packet(
        result.run.run_id,
        %{attempt_id: result.attempt.attempt_id}
      )

    IO.inspect(
      %{
        run_id: result.run.run_id,
        route: result.compatibility_result.metadata.route,
        management_mode: result.endpoint_descriptor.management_mode,
        provider_identity: result.endpoint_descriptor.provider_identity,
        endpoint: result.endpoint_descriptor.base_url,
        events: Enum.map(packet.events, & &1.type)
      },
      label: "ollama_attach_proof"
    )

  {:error, reason} ->
    IO.puts("Failed to run the Ollama attach proof: #{inspect(reason)}")

    IO.puts("""
    Ensure an external Ollama daemon is already running and the requested model is pulled.

      mix run examples/ollama_attach_proof.exs -- --root-url #{root_url} --model-id #{model_id}
    """)

    System.halt(1)
end
