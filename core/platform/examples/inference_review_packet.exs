alias Jido.Integration.V2, as: V2
alias Jido.Integration.V2.BackendManifest
alias Jido.Integration.V2.CompatibilityResult
alias Jido.Integration.V2.ConsumerManifest
alias Jido.Integration.V2.ControlPlane
alias Jido.Integration.V2.EndpointDescriptor
alias Jido.Integration.V2.InferenceExecutionContext
alias Jido.Integration.V2.InferenceRequest
alias Jido.Integration.V2.InferenceResult
alias Jido.Integration.V2.LeaseRef

{:ok, _} = Jido.Integration.V2.Auth.Application.start(:normal, [])
{:ok, _} = Jido.Integration.V2.ControlPlane.Application.start(:normal, [])

ControlPlane.reset!()

{:ok, recorded} =
  ControlPlane.record_inference_attempt(%{
    request:
      InferenceRequest.new!(%{
        request_id: "req-review-example-1",
        operation: :stream_text,
        messages: [%{role: "user", content: "Review the inference baseline"}],
        prompt: nil,
        model_preference: %{provider: "openai", id: "llama-3.2-3b-instruct"},
        target_preference: %{target_class: "self_hosted_endpoint"},
        stream?: true,
        tool_policy: %{},
        output_constraints: %{format: "text"},
        metadata: %{tenant_id: "tenant-example-1"}
      }),
    context:
      InferenceExecutionContext.new!(%{
        run_id: "run-review-example-1",
        attempt_id: "run-review-example-1:1",
        authority_source: "jido_integration",
        decision_ref: "decision-review-example-1",
        authority_ref: nil,
        boundary_ref: "boundary-review-example-1",
        credential_scope: %{scopes: ["model:invoke"]},
        network_policy: %{egress: "restricted"},
        observability: %{trace_id: "trace-review-example-1"},
        streaming_policy: %{checkpoint_policy: :summary},
        replay: %{replayable?: true, recovery_class: "checkpoint_resume"},
        metadata: %{phase: "phase_0"}
      }),
    consumer_manifest:
      ConsumerManifest.new!(%{
        consumer: "jido_integration_req_llm",
        accepted_runtime_kinds: [:client, :task, :service],
        accepted_management_modes: [
          :provider_managed,
          :jido_managed,
          :externally_managed
        ],
        accepted_protocols: [:openai_chat_completions],
        required_capabilities: %{streaming?: true},
        optional_capabilities: %{tool_calling?: false},
        constraints: %{checkpoint_policy: :summary},
        metadata: %{phase: "phase_0"}
      }),
    backend_manifest:
      BackendManifest.new!(%{
        backend: "llama_cpp",
        runtime_kind: :service,
        management_modes: [:jido_managed, :externally_managed],
        startup_kind: :spawned,
        protocols: [:openai_chat_completions],
        capabilities: %{streaming?: true, tool_calling?: false, embeddings?: "unknown"},
        supported_surfaces: [:local_subprocess],
        resource_profile: %{profile: "gpu_single_tenant"},
        metadata: %{family: "llama_cpp"}
      }),
    endpoint_descriptor:
      EndpointDescriptor.new!(%{
        endpoint_id: "endpoint-review-example-1",
        runtime_kind: :service,
        management_mode: :jido_managed,
        target_class: :self_hosted_endpoint,
        protocol: :openai_chat_completions,
        base_url: "http://127.0.0.1:8080/v1",
        headers: %{"authorization" => "Bearer local"},
        provider_identity: "llama_cpp",
        model_identity: "llama-3.2-3b-instruct",
        source_runtime: "llama_cpp_ex",
        source_runtime_ref: "llama-runtime-review-example-1",
        lease_ref: "lease-review-example-1",
        health_ref: "health-review-example-1",
        boundary_ref: "boundary-review-example-1",
        capabilities: %{streaming?: true},
        metadata: %{publisher: "phase_0"}
      }),
    lease_ref:
      LeaseRef.new!(%{
        lease_ref: "lease-review-example-1",
        owner_ref: "llama-runtime-review-example-1",
        ttl_ms: 60_000,
        renewable?: true,
        metadata: %{surface_kind: "local_subprocess"}
      }),
    compatibility_result:
      CompatibilityResult.new!(%{
        compatible?: true,
        reason: :protocol_match,
        resolved_runtime_kind: :service,
        resolved_management_mode: :jido_managed,
        resolved_protocol: :openai_chat_completions,
        warnings: [],
        missing_requirements: [],
        metadata: %{route: "self_hosted"}
      }),
    stream: %{
      opened: %{
        stream_id: "stream-review-example-1",
        protocol: :openai_chat_completions,
        checkpoint_policy: :summary
      },
      checkpoints: [
        %{
          stream_id: "stream-review-example-1",
          chunk_count: 2,
          byte_count: 89,
          content_artifact_id: "artifact-review-example-1"
        }
      ],
      closed: %{
        stream_id: "stream-review-example-1",
        finish_reason: :stop,
        chunk_count: 2,
        byte_count: 89
      }
    },
    result:
      InferenceResult.new!(%{
        run_id: "run-review-example-1",
        attempt_id: "run-review-example-1:1",
        status: :ok,
        streaming?: true,
        endpoint_id: "endpoint-review-example-1",
        stream_id: "stream-review-example-1",
        finish_reason: :stop,
        usage: %{input_tokens: 15, output_tokens: 44},
        error: nil,
        metadata: %{provider: "llama_cpp"}
      })
  })

{:ok, packet} = V2.review_packet(recorded.run.run_id, %{attempt_id: recorded.attempt.attempt_id})

IO.inspect(
  %{
    connector_id: packet.connector.connector_id,
    capability_id: packet.capability.capability_id,
    runtime: packet.capability.runtime,
    event_types: Enum.map(packet.events, & &1.type)
  },
  label: "inference_review_packet"
)
