defmodule Jido.Integration.V2InferenceReviewPacketTest do
  use ExUnit.Case

  alias Jido.Integration.V2
  alias Jido.Integration.V2.BackendManifest
  alias Jido.Integration.V2.CompatibilityResult
  alias Jido.Integration.V2.ConsumerManifest
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.EndpointDescriptor
  alias Jido.Integration.V2.InferenceExecutionContext
  alias Jido.Integration.V2.InferenceRequest
  alias Jido.Integration.V2.InferenceResult
  alias Jido.Integration.V2.LeaseRef

  setup do
    ControlPlane.reset!()
    :ok
  end

  test "review_packet projects a synthetic inference catalog summary over durable inference truth" do
    assert {:ok, recorded} =
             ControlPlane.record_inference_attempt(%{
               request:
                 InferenceRequest.new!(%{
                   request_id: "req-review-1",
                   operation: :stream_text,
                   messages: [%{role: "user", content: "Review the self-hosted baseline"}],
                   prompt: nil,
                   model_preference: %{provider: "openai", id: "llama-3.2-3b-instruct"},
                   target_preference: %{target_class: "self_hosted_endpoint"},
                   stream?: true,
                   tool_policy: %{},
                   output_constraints: %{format: "text"},
                   metadata: %{tenant_id: "tenant-1"}
                 }),
               context:
                 InferenceExecutionContext.new!(%{
                   run_id: "run-review-1",
                   attempt_id: "run-review-1:1",
                   authority_source: :jido_integration,
                   decision_ref: "decision-review-1",
                   authority_ref: nil,
                   boundary_ref: "boundary-review-1",
                   credential_scope: %{scopes: ["model:invoke"]},
                   network_policy: %{egress: :restricted},
                   observability: %{trace_id: "trace-review-1"},
                   streaming_policy: %{checkpoint_policy: :summary},
                   replay: %{replayable?: true, recovery_class: :checkpoint_resume},
                   metadata: %{phase: "phase_0"}
                 }),
               consumer_manifest:
                 ConsumerManifest.new!(%{
                   consumer: :jido_integration_req_llm,
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
                   metadata: %{phase: :phase_0}
                 }),
               backend_manifest:
                 BackendManifest.new!(%{
                   backend: :llama_cpp,
                   runtime_kind: :service,
                   management_modes: [:jido_managed, :externally_managed],
                   startup_kind: :spawned,
                   protocols: [:openai_chat_completions],
                   capabilities: %{streaming?: true, tool_calling?: false, embeddings?: :unknown},
                   supported_surfaces: [:local_subprocess],
                   resource_profile: %{profile: "gpu_single_tenant"},
                   metadata: %{family: :llama_cpp}
                 }),
               endpoint_descriptor:
                 EndpointDescriptor.new!(%{
                   endpoint_id: "endpoint-review-1",
                   runtime_kind: :service,
                   management_mode: :jido_managed,
                   target_class: :self_hosted_endpoint,
                   protocol: :openai_chat_completions,
                   base_url: "http://127.0.0.1:8080/v1",
                   headers: %{"authorization" => "Bearer local"},
                   provider_identity: :llama_cpp,
                   model_identity: "llama-3.2-3b-instruct",
                   source_runtime: :llama_cpp_ex,
                   source_runtime_ref: "llama-runtime-review-1",
                   lease_ref: "lease-review-1",
                   health_ref: "health-review-1",
                   boundary_ref: "boundary-review-1",
                   capabilities: %{streaming?: true},
                   metadata: %{publisher: :phase_0}
                 }),
               lease_ref:
                 LeaseRef.new!(%{
                   lease_ref: "lease-review-1",
                   owner_ref: "llama-runtime-review-1",
                   ttl_ms: 60_000,
                   renewable?: true,
                   metadata: %{surface_kind: :local_subprocess}
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
                   metadata: %{route: :self_hosted}
                 }),
               stream: %{
                 opened: %{
                   stream_id: "stream-review-1",
                   protocol: :openai_chat_completions,
                   checkpoint_policy: :summary
                 },
                 checkpoints: [
                   %{
                     stream_id: "stream-review-1",
                     chunk_count: 2,
                     byte_count: 89,
                     content_artifact_id: "artifact-review-1"
                   }
                 ],
                 closed: %{
                   stream_id: "stream-review-1",
                   finish_reason: :stop,
                   chunk_count: 2,
                   byte_count: 89
                 }
               },
               result:
                 InferenceResult.new!(%{
                   run_id: "run-review-1",
                   attempt_id: "run-review-1:1",
                   status: :ok,
                   streaming?: true,
                   endpoint_id: "endpoint-review-1",
                   stream_id: "stream-review-1",
                   finish_reason: :stop,
                   usage: %{input_tokens: 15, output_tokens: 44},
                   error: nil,
                   metadata: %{provider: :llama_cpp}
                 })
             })

    assert {:ok, packet} =
             V2.review_packet(recorded.run.run_id, %{attempt_id: recorded.attempt.attempt_id})

    assert packet.connector.connector_id == "inference"
    assert packet.connector.runtime_families == [:inference]
    assert packet.capability.capability_id == "inference.execute"
    assert packet.capability.runtime_class == :stream
    assert packet.capability.runtime.runtime_kind == :service
    assert packet.capability.runtime.management_mode == :jido_managed
    assert packet.capability.runtime.target_class == :self_hosted_endpoint
    assert packet.connection == nil
    assert packet.install == nil
    assert packet.target == nil
    assert packet.attempt.output.inference_result.endpoint_id == "endpoint-review-1"
    assert packet.attempt.output.inference_result.status == :ok

    assert Enum.map(packet.events, & &1.type) == [
             "inference.request_admitted",
             "inference.attempt_started",
             "inference.compatibility_evaluated",
             "inference.target_resolved",
             "inference.stream_opened",
             "inference.stream_checkpoint",
             "inference.stream_closed",
             "inference.attempt_completed"
           ]
  end
end
