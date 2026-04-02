defmodule Jido.Integration.V2InferenceInvokeTest do
  use ExUnit.Case

  alias Jido.Integration.V2
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.InferenceRequest

  defmodule CloudHTTP do
  end

  setup do
    ControlPlane.reset!()

    Req.Test.stub(CloudHTTP, fn conn ->
      Req.Test.json(conn, %{
        "id" => "cmpl_platform_inference_cloud_123",
        "model" => "gpt-4o-mini",
        "choices" => [
          %{
            "finish_reason" => "stop",
            "message" => %{
              "role" => "assistant",
              "content" => "Platform facade cloud proof is alive."
            }
          }
        ],
        "usage" => %{
          "prompt_tokens" => 10,
          "completion_tokens" => 6,
          "total_tokens" => 16
        }
      })
    end)

    :ok
  end

  test "invoke_inference/2 executes through the public facade and remains reviewable" do
    request =
      InferenceRequest.new!(%{
        request_id: "req-platform-live-cloud-1",
        operation: :generate_text,
        messages: [%{role: "user", content: "Summarize the facade path"}],
        prompt: nil,
        model_preference: %{provider: "openai", id: "gpt-4o-mini"},
        target_preference: %{target_class: "cloud_provider"},
        stream?: false,
        tool_policy: %{},
        output_constraints: %{},
        metadata: %{tenant_id: "tenant-platform-live-cloud-1"}
      })

    assert {:ok, result} =
             V2.invoke_inference(
               request,
               api_key: "cloud-fixture-token",
               req_http_options: [plug: {Req.Test, CloudHTTP}],
               run_id: "run-platform-live-cloud-1",
               decision_ref: "decision-platform-live-cloud-1",
               trace_id: "trace-platform-live-cloud-1"
             )

    assert result.inference_result.status == :ok
    assert result.compatibility_result.metadata.route == :cloud

    assert {:ok, packet} =
             V2.review_packet(result.run.run_id, %{attempt_id: result.attempt.attempt_id})

    assert packet.connector.connector_id == "inference"
    assert packet.connector.runtime_families == [:inference]
    assert packet.capability.capability_id == "inference.execute"
    assert packet.attempt.output["compatibility_result"]["metadata"]["route"] == "cloud"
  end
end
