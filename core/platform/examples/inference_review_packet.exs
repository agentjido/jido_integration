Application.ensure_all_started(:inets)
Application.ensure_all_started(:ssl)

alias Jido.Integration.V2, as: V2
alias Jido.Integration.V2.ControlPlane

defmodule CloudHTTP do
end

{:ok, _} = Jido.Integration.V2.Auth.Application.start(:normal, [])
{:ok, _} = Jido.Integration.V2.ControlPlane.Application.start(:normal, [])

ControlPlane.reset!()

Req.Test.stub(CloudHTTP, fn conn ->
  Req.Test.json(conn, %{
    "id" => "cmpl_platform_example_123",
    "model" => "gpt-4o-mini",
    "choices" => [
      %{
        "finish_reason" => "stop",
        "message" => %{
          "role" => "assistant",
          "content" => "The platform review proof is live."
        }
      }
    ],
    "usage" => %{
      "prompt_tokens" => 10,
      "completion_tokens" => 8,
      "total_tokens" => 18
    }
  })
end)

{:ok, result} =
  V2.invoke_inference(
    %{
      request_id: "req-platform-example-1",
      operation: :generate_text,
      messages: [%{role: "user", content: "Summarize the platform review proof"}],
      model_preference: %{provider: "openai", id: "gpt-4o-mini"},
      target_preference: %{target_class: "cloud_provider"},
      stream?: false,
      tool_policy: %{},
      output_constraints: %{format: "text"},
      metadata: %{tenant_id: "tenant-platform-example-1"}
    },
    api_key: "fixture-token",
    req_http_options: [plug: {Req.Test, CloudHTTP}],
    run_id: "run-platform-example-1",
    decision_ref: "decision-platform-example-1",
    trace_id: "trace-platform-example-1"
  )

{:ok, packet} = V2.review_packet(result.run.run_id, %{attempt_id: result.attempt.attempt_id})

IO.inspect(
  %{
    connector_id: packet.connector.connector_id,
    capability_id: packet.capability.capability_id,
    runtime: packet.capability.runtime,
    event_types: Enum.map(packet.events, & &1.type)
  },
  label: "inference_review_packet"
)
