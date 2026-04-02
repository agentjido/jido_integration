Application.ensure_all_started(:inets)
Application.ensure_all_started(:ssl)

alias Jido.Integration.V2.ControlPlane

defmodule CloudHTTP do
end

{:ok, _} = Jido.Integration.V2.Auth.Application.start(:normal, [])
{:ok, _} = Jido.Integration.V2.ControlPlane.Application.start(:normal, [])

ControlPlane.reset!()

Req.Test.stub(CloudHTTP, fn conn ->
  Req.Test.json(conn, %{
    "id" => "cmpl_control_plane_example_123",
    "model" => "gpt-4o-mini",
    "choices" => [
      %{
        "finish_reason" => "stop",
        "message" => %{
          "role" => "assistant",
          "content" => "The control-plane proof is live."
        }
      }
    ],
    "usage" => %{
      "prompt_tokens" => 11,
      "completion_tokens" => 7,
      "total_tokens" => 18
    }
  })
end)

{:ok, result} =
  ControlPlane.invoke_inference(
    %{
      request_id: "req-control-plane-example-1",
      operation: :generate_text,
      messages: [%{role: "user", content: "Summarize the control-plane proof"}],
      model_preference: %{provider: "openai", id: "gpt-4o-mini"},
      target_preference: %{target_class: "cloud_provider"},
      stream?: false,
      tool_policy: %{},
      output_constraints: %{format: "text"},
      metadata: %{tenant_id: "tenant-control-plane-example-1"}
    },
    api_key: "fixture-token",
    req_http_options: [plug: {Req.Test, CloudHTTP}],
    run_id: "run-control-plane-example-1",
    decision_ref: "decision-control-plane-example-1",
    trace_id: "trace-control-plane-example-1"
  )

IO.inspect(
  %{
    run_id: result.run.run_id,
    attempt_id: result.attempt.attempt_id,
    response_text: result.response_text,
    event_types: Enum.map(ControlPlane.events(result.run.run_id), & &1.type)
  },
  label: "inference_event_baseline"
)
