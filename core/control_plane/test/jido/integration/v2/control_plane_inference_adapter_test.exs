defmodule Jido.Integration.V2.ControlPlaneInferenceAdapterTest do
  use ExUnit.Case, async: true

  alias Inference.{Client, Request, Response, StreamEvent}
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.ControlPlane.Inference.Adapter
  alias Jido.Integration.V2.InferenceResult

  test "complete/2 maps shared inference requests into governed control-plane invocation" do
    invoke_fun = fn jido_request, invoke_opts ->
      send(self(), {:jido_inference_invoked, jido_request, invoke_opts})

      {:ok,
       %{
         response_text: "governed answer",
         inference_result:
           InferenceResult.new!(%{
             run_id: "run-adapter-1",
             attempt_id: Contracts.attempt_id("run-adapter-1", 1),
             status: :ok,
             streaming?: false,
             finish_reason: :stop,
             usage: %{"input_tokens" => 3, "output_tokens" => 2},
             metadata: %{"route" => "cloud"}
           }),
         compatibility_result: %{metadata: %{route: :cloud}},
         endpoint_descriptor: nil,
         backend_manifest: nil,
         lease_ref: nil,
         run: %{run_id: "run-adapter-1"},
         attempt: %{attempt_id: Contracts.attempt_id("run-adapter-1", 1)}
       }}
    end

    client =
      Client.new!(
        adapter: Adapter,
        provider: :openai,
        model: "gpt-test",
        metadata: %{tenant_id: "tenant-1", caller: "unit"},
        adapter_opts: [
          invoke_fun: invoke_fun,
          invoke_opts: [
            run_id: "run-adapter-1",
            decision_ref: "decision-1",
            trace_id: "trace-1",
            api_key: "test-key"
          ]
        ]
      )

    request =
      Request.from_messages!(
        [%{role: "system", content: "Govern this."}, %{role: "user", content: "hello"}],
        id: "req-adapter-1",
        temperature: 0.2,
        max_tokens: 32,
        metadata: %{route_id: "route-1"},
        options: [target_preference: %{target_class: "cloud_provider"}]
      )

    assert {:ok, %Response{} = response} = Adapter.complete(client, request)
    assert Response.text(response) == "governed answer"
    assert response.provider == :openai
    assert response.model == "gpt-test"
    assert response.usage == %{"input_tokens" => 3, "output_tokens" => 2}
    assert response.metadata.run_id == "run-adapter-1"
    assert response.metadata.attempt_id == Contracts.attempt_id("run-adapter-1", 1)
    assert response.metadata.status == :ok

    assert_receive {:jido_inference_invoked, jido_request, invoke_opts}
    assert jido_request.request_id == "req-adapter-1"
    assert jido_request.operation == :generate_text
    assert jido_request.model_preference == %{provider: :openai, id: "gpt-test"}
    assert jido_request.target_preference == %{target_class: "cloud_provider"}
    assert jido_request.output_constraints.temperature == 0.2
    assert jido_request.output_constraints.max_tokens == 32
    assert jido_request.metadata.tenant_id == "tenant-1"
    assert jido_request.metadata.route_id == "route-1"
    assert invoke_opts[:run_id] == "run-adapter-1"
    assert invoke_opts[:decision_ref] == "decision-1"
    assert invoke_opts[:trace_id] == "trace-1"
    assert invoke_opts[:api_key] == "test-key"
  end

  test "stream/2 records a streaming invocation and returns shared stream events" do
    invoke_fun = fn jido_request, _invoke_opts ->
      send(self(), {:jido_stream_invoked, jido_request})

      {:ok,
       %{
         response_text: "streamed answer",
         inference_result:
           InferenceResult.new!(%{
             run_id: "run-stream-1",
             attempt_id: Contracts.attempt_id("run-stream-1", 1),
             status: :ok,
             streaming?: true,
             finish_reason: :stop,
             metadata: %{}
           }),
         stream: %{closed: %{chunk_count: 1}},
         run: %{run_id: "run-stream-1"},
         attempt: %{attempt_id: Contracts.attempt_id("run-stream-1", 1)}
       }}
    end

    client =
      Client.new!(
        adapter: Adapter,
        provider: :gemini,
        model: "gemini-test",
        adapter_opts: [invoke_fun: invoke_fun]
      )

    request =
      Request.from_prompt!("hello",
        id: "req-stream-1",
        session: "session-1",
        options: [target_preference: %{target_class: "cli_endpoint"}]
      )

    assert {:ok, stream} = Adapter.stream(client, request)
    assert [%StreamEvent{type: :delta, data: "streamed answer"}, %StreamEvent{type: :done}] =
             Enum.to_list(stream)

    assert_receive {:jido_stream_invoked, jido_request}
    assert jido_request.operation == :stream_text
    assert jido_request.stream?
    assert jido_request.target_preference == %{target_class: "cli_endpoint"}
    assert jido_request.metadata.session == "session-1"
  end
end
