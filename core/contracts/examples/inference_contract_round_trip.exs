alias Jido.Integration.V2.ConsumerManifest
alias Jido.Integration.V2.InferenceExecutionContext
alias Jido.Integration.V2.InferenceRequest
alias Jido.Integration.V2.InferenceResult

request =
  InferenceRequest.new!(%{
    request_id: "req-example-1",
    operation: "stream_text",
    messages: [%{"role" => "user", "content" => "Summarize the inference baseline"}],
    prompt: nil,
    model_preference: %{"provider" => "openai", "id" => "gpt-4o-mini"},
    target_preference: %{"target_class" => "cloud_provider"},
    stream?: true,
    tool_policy: %{"mode" => "none"},
    output_constraints: %{"format" => "markdown"},
    metadata: %{"tenant_id" => "tenant-example-1"}
  })

context =
  InferenceExecutionContext.new!(%{
    run_id: "run-example-1",
    attempt_id: "run-example-1:1",
    authority_source: "jido_integration",
    decision_ref: "decision-example-1",
    authority_ref: nil,
    boundary_ref: nil,
    credential_scope: %{"scopes" => ["model:invoke"]},
    network_policy: %{"egress" => "restricted"},
    observability: %{"trace_id" => "trace-example-1"},
    streaming_policy: %{"checkpoint_policy" => "summary"},
    replay: %{"replayable?" => true, "recovery_class" => "checkpoint_resume"},
    metadata: %{"phase" => "phase_0"}
  })

consumer_manifest =
  ConsumerManifest.new!(%{
    consumer: "jido_integration_req_llm",
    accepted_runtime_kinds: ["client", "task", "service"],
    accepted_management_modes: [
      "provider_managed",
      "jido_managed",
      "externally_managed"
    ],
    accepted_protocols: ["openai_chat_completions"],
    required_capabilities: %{"streaming?" => true},
    optional_capabilities: %{"tool_calling?" => false},
    constraints: %{"checkpoint_policy" => "summary"},
    metadata: %{"phase" => "phase_0"}
  })

result =
  InferenceResult.new!(%{
    run_id: "run-example-1",
    attempt_id: "run-example-1:1",
    status: "ok",
    streaming?: true,
    endpoint_id: nil,
    stream_id: "stream-example-1",
    finish_reason: "stop",
    usage: %{"input_tokens" => 9, "output_tokens" => 21},
    error: nil,
    metadata: %{"route" => "cloud"}
  })

IO.inspect(
  %{
    request: InferenceRequest.dump(request),
    context: InferenceExecutionContext.dump(context),
    consumer_manifest: ConsumerManifest.dump(consumer_manifest),
    result: InferenceResult.dump(result)
  },
  label: "inference_contract_round_trip"
)
