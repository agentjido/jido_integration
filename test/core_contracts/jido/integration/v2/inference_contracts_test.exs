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

    dump = InferenceRequest.dump(request)

    assert request.contract_version == "inference.v1"
    assert request.operation == :stream_text
    assert request.stream? == true
    assert dump["operation"] == "stream_text"
    assert_json_safe(dump)
    assert InferenceRequest.new!(dump) == request
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

    dump = InferenceExecutionContext.dump(context)

    assert context.contract_version == "inference.v1"
    assert context.authority_source == :jido_integration
    assert context.streaming_policy == %{checkpoint_policy: :summary}
    assert dump["authority_source"] == "jido_integration"
    assert dump["streaming_policy"]["checkpoint_policy"] == "summary"
    assert_json_safe(dump)
    assert InferenceExecutionContext.new!(dump) == context
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
        provider_identity: "llama_cpp_sdk",
        model_identity: "llama-3.2-3b-instruct",
        source_runtime: "llama_cpp_sdk",
        source_runtime_ref: "llama-runtime-1",
        lease_ref: "lease-inference-1",
        health_ref: "health-1",
        boundary_ref: "boundary-1",
        capabilities: %{"streaming?" => true, "tool_calling?" => false},
        metadata: %{"publisher" => "phase_0"}
      })

    backend =
      BackendManifest.new!(%{
        backend: "llama_cpp_sdk",
        runtime_kind: "service",
        management_modes: ["jido_managed", "externally_managed"],
        startup_kind: "spawned",
        protocols: ["openai_chat_completions"],
        capabilities: %{
          "streaming?" => true,
          "tool_calling?" => false,
          "embeddings?" => "unknown"
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

    endpoint_dump = EndpointDescriptor.dump(endpoint)
    backend_dump = BackendManifest.dump(backend)
    consumer_dump = ConsumerManifest.dump(consumer)

    assert endpoint.protocol == :openai_chat_completions
    assert backend.supported_surfaces == [:local_subprocess]
    assert consumer.accepted_runtime_kinds == [:client, :task, :service]
    assert endpoint_dump["protocol"] == "openai_chat_completions"
    assert backend_dump["backend"] == "llama_cpp_sdk"
    assert consumer_dump["consumer"] == "jido_integration_req_llm"
    assert_json_safe(endpoint_dump)
    assert_json_safe(backend_dump)
    assert_json_safe(consumer_dump)
    assert EndpointDescriptor.new!(endpoint_dump) == endpoint
    assert BackendManifest.new!(backend_dump) == backend
    assert ConsumerManifest.new!(consumer_dump) == consumer
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
        metadata: %{"backend" => "llama_cpp_sdk"}
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

    compatibility_dump = CompatibilityResult.dump(compatibility)
    result_dump = InferenceResult.dump(result)
    lease_dump = LeaseRef.dump(lease_ref)

    assert compatibility.reason == :protocol_match
    assert result.status == :ok
    assert lease_ref.renewable? == true
    assert compatibility_dump["reason"] == "protocol_match"
    assert result_dump["status"] == "ok"
    assert lease_dump["renewable?"] == true
    assert_json_safe(compatibility_dump)
    assert_json_safe(result_dump)
    assert_json_safe(lease_dump)
    assert CompatibilityResult.new!(compatibility_dump) == compatibility
    assert InferenceResult.new!(result_dump) == result
    assert LeaseRef.new!(lease_dump) == lease_ref
  end

  defp assert_json_safe(value) when is_binary(value) or is_boolean(value) or is_nil(value),
    do: :ok

  defp assert_json_safe(value) when is_integer(value) or is_float(value), do: :ok

  defp assert_json_safe(value) when is_list(value) do
    Enum.each(value, &assert_json_safe/1)
  end

  defp assert_json_safe(value) when is_map(value) do
    assert Enum.all?(Map.keys(value), &is_binary/1)
    Enum.each(value, fn {_key, nested} -> assert_json_safe(nested) end)
  end
end
