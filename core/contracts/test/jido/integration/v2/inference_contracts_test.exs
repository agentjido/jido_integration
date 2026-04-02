defmodule Jido.Integration.V2.InferenceContractsTest do
  use ExUnit.Case, async: true

  alias Jido.Integration.V2.BackendManifest
  alias Jido.Integration.V2.CompatibilityResult
  alias Jido.Integration.V2.ConsumerManifest
  alias Jido.Integration.V2.EndpointDescriptor
  alias Jido.Integration.V2.InferenceExecutionContext
  alias Jido.Integration.V2.InferenceRequest
  alias Jido.Integration.V2.InferenceResult
  alias Jido.Integration.V2.LeaseRef

  test "inference request round-trips through its durable dump map" do
    request =
      InferenceRequest.new!(%{
        request_id: "req-inference-1",
        operation: "stream_text",
        messages: [%{"role" => "user", "content" => "Summarize the packet"}],
        prompt: nil,
        model_preference: %{"provider" => "openai", "id" => "gpt-4o-mini"},
        target_preference: %{"target_class" => "cloud_provider"},
        stream?: true,
        tool_policy: %{"mode" => "none"},
        output_constraints: %{"format" => "markdown"},
        metadata: %{"tenant_id" => "tenant-1"}
      })

    assert request.contract_version == "inference.v1"
    assert request.operation == :stream_text
    assert request.stream? == true
    assert InferenceRequest.new!(InferenceRequest.dump(request)) == request
  end

  test "inference execution context round-trips through its durable dump map" do
    context =
      InferenceExecutionContext.new!(%{
        run_id: "run-inference-1",
        attempt_id: "run-inference-1:1",
        authority_source: "jido_integration",
        decision_ref: "decision-1",
        authority_ref: "authority-1",
        boundary_ref: "boundary-1",
        credential_scope: %{"scopes" => ["model:invoke"]},
        network_policy: %{"egress" => "restricted"},
        observability: %{"trace_id" => "trace-inference-1"},
        streaming_policy: %{"checkpoint_policy" => "summary"},
        replay: %{"replayable?" => true, "recovery_class" => "checkpoint_resume"},
        metadata: %{"phase" => "phase_0"}
      })

    assert context.contract_version == "inference.v1"
    assert context.authority_source == :jido_integration
    assert context.streaming_policy == %{checkpoint_policy: :summary}
    assert InferenceExecutionContext.new!(InferenceExecutionContext.dump(context)) == context
  end

  test "endpoint, backend, and consumer manifests round-trip through their dump maps" do
    endpoint =
      EndpointDescriptor.new!(%{
        endpoint_id: "endpoint-llama-1",
        runtime_kind: "service",
        management_mode: "jido_managed",
        target_class: "self_hosted_endpoint",
        protocol: "openai_chat_completions",
        base_url: "http://127.0.0.1:8080/v1",
        headers: %{"authorization" => "Bearer local"},
        provider_identity: "llama_cpp",
        model_identity: "llama-3.2-3b-instruct",
        source_runtime: "llama_cpp_ex",
        source_runtime_ref: "llama-runtime-1",
        lease_ref: "lease-inference-1",
        health_ref: "health-1",
        boundary_ref: "boundary-1",
        capabilities: %{"streaming?" => true, "tool_calling?" => false},
        metadata: %{"publisher" => "phase_0"}
      })

    backend =
      BackendManifest.new!(%{
        backend: "llama_cpp",
        runtime_kind: "service",
        management_modes: ["jido_managed", "externally_managed"],
        startup_kind: "spawned",
        protocols: ["openai_chat_completions"],
        capabilities: %{
          "streaming?" => true,
          "tool_calling?" => false,
          "embeddings?" => :unknown
        },
        supported_surfaces: ["local_subprocess"],
        resource_profile: %{"profile" => "gpu_single_tenant"},
        metadata: %{"family" => "llama_cpp"}
      })

    consumer =
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

    assert endpoint.protocol == :openai_chat_completions
    assert backend.supported_surfaces == [:local_subprocess]
    assert consumer.accepted_runtime_kinds == [:client, :task, :service]
    assert EndpointDescriptor.new!(EndpointDescriptor.dump(endpoint)) == endpoint
    assert BackendManifest.new!(BackendManifest.dump(backend)) == backend
    assert ConsumerManifest.new!(ConsumerManifest.dump(consumer)) == consumer
  end

  test "compatibility result, inference result, and lease ref round-trip through durable dump maps" do
    compatibility =
      CompatibilityResult.new!(%{
        compatible?: true,
        reason: "protocol_match",
        resolved_runtime_kind: "service",
        resolved_management_mode: "jido_managed",
        resolved_protocol: "openai_chat_completions",
        warnings: ["warmup_pending"],
        missing_requirements: [],
        metadata: %{"backend" => "llama_cpp"}
      })

    result =
      InferenceResult.new!(%{
        run_id: "run-inference-1",
        attempt_id: "run-inference-1:1",
        status: "ok",
        streaming?: true,
        endpoint_id: "endpoint-llama-1",
        stream_id: "stream-inference-1",
        finish_reason: "stop",
        usage: %{"input_tokens" => 12, "output_tokens" => 34},
        error: nil,
        metadata: %{"route" => "self_hosted"}
      })

    lease_ref =
      LeaseRef.new!(%{
        lease_ref: "lease-inference-1",
        owner_ref: "llama-runtime-1",
        ttl_ms: 60_000,
        renewable?: true,
        metadata: %{"surface_kind" => "local_subprocess"}
      })

    assert compatibility.reason == :protocol_match
    assert result.status == :ok
    assert lease_ref.renewable? == true
    assert CompatibilityResult.new!(CompatibilityResult.dump(compatibility)) == compatibility
    assert InferenceResult.new!(InferenceResult.dump(result)) == result
    assert LeaseRef.new!(LeaseRef.dump(lease_ref)) == lease_ref
  end
end
