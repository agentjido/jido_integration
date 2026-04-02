defmodule Jido.Integration.V2.ControlPlaneInferenceTest do
  use ExUnit.Case

  alias Jido.Integration.V2.BackendManifest
  alias Jido.Integration.V2.CompatibilityResult
  alias Jido.Integration.V2.ConsumerManifest
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.EndpointDescriptor
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.InferenceExecutionContext
  alias Jido.Integration.V2.InferenceRequest
  alias Jido.Integration.V2.InferenceResult
  alias Jido.Integration.V2.LeaseRef

  setup do
    ControlPlane.reset!()
    :ok
  end

  test "records the minimum durable inference event set for a cloud request" do
    spec = cloud_spec()

    assert {:ok, recorded} = ControlPlane.record_inference_attempt(spec)
    assert {:ok, stored_run} = ControlPlane.fetch_run(recorded.run.run_id)
    assert {:ok, stored_attempt} = ControlPlane.fetch_attempt(recorded.attempt.attempt_id)

    assert stored_run.capability_id == "inference.execute"
    assert stored_attempt.output["inference_result"]["status"] == "ok"
    assert_json_safe(stored_run.input)
    assert_json_safe(stored_run.result)
    assert_json_safe(stored_attempt.output)

    assert [
             %Event{type: "inference.request_admitted", seq: 0, payload: admitted_payload},
             %Event{type: "inference.attempt_started", seq: 1, payload: started_payload},
             %Event{
               type: "inference.compatibility_evaluated",
               seq: 2,
               payload: compatibility_payload
             },
             %Event{type: "inference.target_resolved", seq: 3, payload: target_payload},
             %Event{type: "inference.attempt_completed", seq: 4, payload: terminal_payload}
           ] = ControlPlane.events(recorded.run.run_id)

    assert admitted_payload == %{
             request_id: spec.request.request_id,
             operation: :generate_text,
             stream?: false,
             target_class: :cloud_provider
           }

    assert started_payload == %{
             attempt_id: recorded.attempt.attempt_id,
             runtime_kind: :client,
             management_mode: :provider_managed
           }

    assert compatibility_payload == %{
             compatible?: true,
             reason: :protocol_match,
             consumer: :jido_integration_req_llm,
             backend: nil
           }

    assert target_payload == %{
             endpoint_id: nil,
             target_class: :cloud_provider,
             protocol: nil,
             source_runtime: :req_llm,
             lease_ref: nil
           }

    assert terminal_payload.status == :ok
    assert terminal_payload.finish_reason == :stop
  end

  test "rejects stream checkpoint policy drift from the admitted execution context" do
    spec =
      self_hosted_streaming_spec()
      |> put_in([:stream, :opened, :checkpoint_policy], :artifact)

    assert {:error, %ArgumentError{} = error} = ControlPlane.record_inference_attempt(spec)

    assert error.message ==
             "stream.opened.checkpoint_policy must match InferenceExecutionContext.streaming_policy.checkpoint_policy"
  end

  test "records streaming self-hosted inference truth with lease and checkpoint events" do
    spec = self_hosted_streaming_spec()

    assert {:ok, recorded} = ControlPlane.record_inference_attempt(spec)

    assert [
             %Event{type: "inference.request_admitted"},
             %Event{type: "inference.attempt_started"},
             %Event{type: "inference.compatibility_evaluated"},
             %Event{type: "inference.target_resolved", payload: target_payload},
             %Event{type: "inference.stream_opened", payload: opened_payload},
             %Event{type: "inference.stream_checkpoint", payload: checkpoint_payload},
             %Event{type: "inference.stream_closed", payload: closed_payload},
             %Event{type: "inference.attempt_completed", payload: terminal_payload}
           ] = ControlPlane.events(recorded.run.run_id)

    assert target_payload.endpoint_id == "endpoint-llama-1"
    assert target_payload.target_class == :self_hosted_endpoint
    assert target_payload.protocol == :openai_chat_completions
    assert target_payload.source_runtime == :llama_cpp_ex
    assert target_payload.lease_ref == "lease-inference-1"

    assert opened_payload == %{
             stream_id: "stream-inference-1",
             protocol: :openai_chat_completions,
             checkpoint_policy: :summary
           }

    assert checkpoint_payload == %{
             stream_id: "stream-inference-1",
             chunk_count: 3,
             byte_count: 144,
             content_artifact_id: "artifact-stream-summary-1"
           }

    assert closed_payload == %{
             stream_id: "stream-inference-1",
             finish_reason: :stop,
             chunk_count: 3,
             byte_count: 144
           }

    assert terminal_payload.status == :ok
    assert terminal_payload.usage == %{input_tokens: 12, output_tokens: 34}
  end

  test "records CLI-backed inference cancellation explicitly" do
    spec = cli_cancelled_spec()

    assert {:ok, recorded} = ControlPlane.record_inference_attempt(spec)

    assert [
             %Event{type: "inference.request_admitted"},
             %Event{type: "inference.attempt_started", payload: started_payload},
             %Event{type: "inference.compatibility_evaluated", payload: compatibility_payload},
             %Event{type: "inference.target_resolved", payload: target_payload},
             %Event{type: "inference.stream_opened"},
             %Event{type: "inference.stream_closed"},
             %Event{type: "inference.attempt_cancelled", payload: terminal_payload}
           ] = ControlPlane.events(recorded.run.run_id)

    assert started_payload.runtime_kind == :task
    assert started_payload.management_mode == :jido_managed
    assert compatibility_payload.backend == :asm_inference_endpoint
    assert target_payload.target_class == :cli_endpoint
    assert terminal_payload.status == :cancelled
    assert terminal_payload.finish_reason == :cancelled
  end

  test "records inference failures explicitly" do
    spec = failed_cloud_spec()

    assert {:ok, recorded} = ControlPlane.record_inference_attempt(spec)

    assert [
             %Event{type: "inference.request_admitted"},
             %Event{type: "inference.attempt_started"},
             %Event{type: "inference.compatibility_evaluated"},
             %Event{type: "inference.target_resolved"},
             %Event{type: "inference.attempt_failed", payload: terminal_payload}
           ] = ControlPlane.events(recorded.run.run_id)

    assert terminal_payload.status == :error
    assert terminal_payload.error == %{message: "provider timeout", reason: :timeout}
  end

  defp cloud_spec do
    %{
      request:
        InferenceRequest.new!(%{
          request_id: "req-cloud-1",
          operation: :generate_text,
          messages: [%{role: "user", content: "Summarize the packet"}],
          prompt: nil,
          model_preference: %{provider: "openai", id: "gpt-4o-mini"},
          target_preference: %{target_class: "cloud_provider"},
          stream?: false,
          tool_policy: %{},
          output_constraints: %{format: "text"},
          metadata: %{tenant_id: "tenant-1"}
        }),
      context:
        InferenceExecutionContext.new!(%{
          run_id: "run-cloud-1",
          attempt_id: "run-cloud-1:1",
          authority_source: :jido_integration,
          decision_ref: "decision-cloud-1",
          authority_ref: nil,
          boundary_ref: nil,
          credential_scope: %{scopes: ["model:invoke"]},
          network_policy: %{egress: "restricted"},
          observability: %{trace_id: "trace-cloud-1"},
          streaming_policy: %{checkpoint_policy: :disabled},
          replay: %{replayable?: false, recovery_class: nil},
          metadata: %{phase: "phase_0"}
        }),
      consumer_manifest: consumer_manifest(),
      compatibility_result:
        CompatibilityResult.new!(%{
          compatible?: true,
          reason: :protocol_match,
          resolved_runtime_kind: :client,
          resolved_management_mode: :provider_managed,
          resolved_protocol: nil,
          warnings: [],
          missing_requirements: [],
          metadata: %{route: "cloud"}
        }),
      result:
        InferenceResult.new!(%{
          run_id: "run-cloud-1",
          attempt_id: "run-cloud-1:1",
          status: :ok,
          streaming?: false,
          endpoint_id: nil,
          stream_id: nil,
          finish_reason: :stop,
          usage: %{input_tokens: 9, output_tokens: 21},
          error: nil,
          metadata: %{provider: "openai"}
        })
    }
  end

  defp failed_cloud_spec do
    cloud_spec()
    |> Map.put(
      :result,
      InferenceResult.new!(%{
        run_id: "run-cloud-1",
        attempt_id: "run-cloud-1:1",
        status: :error,
        streaming?: false,
        endpoint_id: nil,
        stream_id: nil,
        finish_reason: :error,
        usage: nil,
        error: %{message: "provider timeout", reason: :timeout},
        metadata: %{provider: "openai"}
      })
    )
  end

  defp self_hosted_streaming_spec do
    %{
      request:
        InferenceRequest.new!(%{
          request_id: "req-self-hosted-1",
          operation: :stream_text,
          messages: [%{role: "user", content: "Stream the response"}],
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
          run_id: "run-self-hosted-1",
          attempt_id: "run-self-hosted-1:1",
          authority_source: :jido_integration,
          decision_ref: "decision-self-hosted-1",
          authority_ref: nil,
          boundary_ref: "boundary-self-hosted-1",
          credential_scope: %{scopes: ["model:invoke"]},
          network_policy: %{egress: "restricted"},
          observability: %{trace_id: "trace-self-hosted-1"},
          streaming_policy: %{checkpoint_policy: :summary},
          replay: %{replayable?: true, recovery_class: "checkpoint_resume"},
          metadata: %{phase: "phase_0"}
        }),
      consumer_manifest: consumer_manifest(required_capabilities: %{streaming?: true}),
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
          endpoint_id: "endpoint-llama-1",
          runtime_kind: :service,
          management_mode: :jido_managed,
          target_class: :self_hosted_endpoint,
          protocol: :openai_chat_completions,
          base_url: "http://127.0.0.1:8080/v1",
          headers: %{"authorization" => "Bearer local"},
          provider_identity: "llama_cpp",
          model_identity: "llama-3.2-3b-instruct",
          source_runtime: "llama_cpp_ex",
          source_runtime_ref: "llama-runtime-1",
          lease_ref: "lease-inference-1",
          health_ref: "health-1",
          boundary_ref: "boundary-self-hosted-1",
          capabilities: %{streaming?: true, tool_calling?: false},
          metadata: %{publisher: "phase_0"}
        }),
      lease_ref:
        LeaseRef.new!(%{
          lease_ref: "lease-inference-1",
          owner_ref: "llama-runtime-1",
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
          stream_id: "stream-inference-1",
          protocol: :openai_chat_completions,
          checkpoint_policy: :summary
        },
        checkpoints: [
          %{
            stream_id: "stream-inference-1",
            chunk_count: 3,
            byte_count: 144,
            content_artifact_id: "artifact-stream-summary-1"
          }
        ],
        closed: %{
          stream_id: "stream-inference-1",
          finish_reason: :stop,
          chunk_count: 3,
          byte_count: 144
        }
      },
      result:
        InferenceResult.new!(%{
          run_id: "run-self-hosted-1",
          attempt_id: "run-self-hosted-1:1",
          status: :ok,
          streaming?: true,
          endpoint_id: "endpoint-llama-1",
          stream_id: "stream-inference-1",
          finish_reason: :stop,
          usage: %{input_tokens: 12, output_tokens: 34},
          error: nil,
          metadata: %{provider: "llama_cpp"}
        })
    }
  end

  defp cli_cancelled_spec do
    %{
      request:
        InferenceRequest.new!(%{
          request_id: "req-cli-1",
          operation: :stream_text,
          messages: [%{role: "user", content: "Stream through ASM"}],
          prompt: nil,
          model_preference: %{provider: "gemini", id: "gemini-2.5-pro"},
          target_preference: %{target_class: "cli_endpoint"},
          stream?: true,
          tool_policy: %{},
          output_constraints: %{format: "text"},
          metadata: %{tenant_id: "tenant-1"}
        }),
      context:
        InferenceExecutionContext.new!(%{
          run_id: "run-cli-1",
          attempt_id: "run-cli-1:1",
          authority_source: :jido_integration,
          decision_ref: "decision-cli-1",
          authority_ref: nil,
          boundary_ref: "boundary-cli-1",
          credential_scope: %{scopes: ["model:invoke"]},
          network_policy: %{egress: "restricted"},
          observability: %{trace_id: "trace-cli-1"},
          streaming_policy: %{checkpoint_policy: :disabled},
          replay: %{replayable?: true, recovery_class: "session_resume"},
          metadata: %{phase: "phase_0"}
        }),
      consumer_manifest: consumer_manifest(required_capabilities: %{streaming?: true}),
      backend_manifest:
        BackendManifest.new!(%{
          backend: "asm_inference_endpoint",
          runtime_kind: :task,
          management_modes: [:jido_managed],
          startup_kind: :spawned,
          protocols: [:openai_chat_completions],
          capabilities: %{streaming?: true, tool_calling?: "unknown", embeddings?: "unknown"},
          supported_surfaces: [:local_subprocess, :ssh_exec, :guest_bridge],
          resource_profile: %{profile: "cli_session"},
          metadata: %{family: "asm"}
        }),
      endpoint_descriptor:
        EndpointDescriptor.new!(%{
          endpoint_id: "endpoint-cli-1",
          runtime_kind: :task,
          management_mode: :jido_managed,
          target_class: :cli_endpoint,
          protocol: :openai_chat_completions,
          base_url: "http://127.0.0.1:4319/v1",
          headers: %{"authorization" => "Bearer asm"},
          provider_identity: "gemini",
          model_identity: "gemini-2.5-pro",
          source_runtime: "asm_inference_endpoint",
          source_runtime_ref: "asm-session-1",
          lease_ref: "lease-cli-1",
          health_ref: nil,
          boundary_ref: "boundary-cli-1",
          capabilities: %{streaming?: true},
          metadata: %{publisher: "phase_0"}
        }),
      compatibility_result:
        CompatibilityResult.new!(%{
          compatible?: true,
          reason: :protocol_match,
          resolved_runtime_kind: :task,
          resolved_management_mode: :jido_managed,
          resolved_protocol: :openai_chat_completions,
          warnings: [],
          missing_requirements: [],
          metadata: %{route: "cli"}
        }),
      stream: %{
        opened: %{
          stream_id: "stream-cli-1",
          protocol: :openai_chat_completions,
          checkpoint_policy: :disabled
        },
        checkpoints: [],
        closed: %{
          stream_id: "stream-cli-1",
          finish_reason: :cancelled,
          chunk_count: 0,
          byte_count: 0
        }
      },
      result:
        InferenceResult.new!(%{
          run_id: "run-cli-1",
          attempt_id: "run-cli-1:1",
          status: :cancelled,
          streaming?: true,
          endpoint_id: "endpoint-cli-1",
          stream_id: "stream-cli-1",
          finish_reason: :cancelled,
          usage: nil,
          error: %{message: "stream cancelled", reason: :user_cancelled},
          metadata: %{provider: "gemini"}
        })
    }
  end

  defp consumer_manifest(overrides \\ []) do
    attrs =
      [
        consumer: "jido_integration_req_llm",
        accepted_runtime_kinds: [:client, :task, :service],
        accepted_management_modes: [:provider_managed, :jido_managed, :externally_managed],
        accepted_protocols: [:openai_chat_completions],
        required_capabilities: %{},
        optional_capabilities: %{tool_calling?: false},
        constraints: %{checkpoint_policy: :summary},
        metadata: %{phase: "phase_0"}
      ]

    attrs
    |> Keyword.merge(overrides)
    |> ConsumerManifest.new!()
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
