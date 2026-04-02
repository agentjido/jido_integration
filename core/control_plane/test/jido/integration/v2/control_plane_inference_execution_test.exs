defmodule Jido.Integration.V2.ControlPlaneInferenceExecutionTest do
  use ExUnit.Case

  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.ControlPlane.Inference.ReqLLMCallSpec
  alias Jido.Integration.V2.EndpointDescriptor
  alias Jido.Integration.V2.InferenceRequest
  alias LlamaCppEx

  @socket_capable? (case :gen_tcp.listen(0, [
                           :binary,
                           packet: :raw,
                           active: false,
                           reuseaddr: true
                         ]) do
                      {:ok, socket} ->
                        :ok = :gen_tcp.close(socket)
                        true

                      {:error, :eperm} ->
                        false

                      {:error, _reason} ->
                        true
                    end)

  defmodule FakeLlamaServerFixture do
    defstruct [:port, :state_dir, :model_path]

    @type t :: %__MODULE__{
            port: pos_integer(),
            state_dir: String.t(),
            model_path: String.t()
          }

    @spec new!(keyword()) :: t()
    def new!(opts \\ []) do
      port = Keyword.get_lazy(opts, :port, &find_free_port/0)
      state_dir = unique_state_dir()
      model_path = Keyword.get(opts, :model_path, "/models/demo.gguf")

      File.mkdir_p!(state_dir)
      File.write!(Path.join(state_dir, "health.txt"), "healthy")

      %__MODULE__{port: port, state_dir: state_dir, model_path: model_path}
    end

    @spec cleanup(t()) :: :ok
    def cleanup(%__MODULE__{} = fixture) do
      File.rm_rf(fixture.state_dir)
      :ok
    end

    @spec boot_spec(t(), keyword()) :: map()
    def boot_spec(%__MODULE__{} = fixture, overrides \\ []) do
      overrides_map = Map.new(overrides)

      %{
        binary_path: System.find_executable("python3") || "python3",
        launcher_args: [script_path()],
        model: Map.get(overrides_map, :model, fixture.model_path),
        alias: Map.get(overrides_map, :alias, "fixture-llama"),
        host: Map.get(overrides_map, :host, "127.0.0.1"),
        port: Map.get(overrides_map, :port, fixture.port),
        ctx_size: Map.get(overrides_map, :ctx_size, 4_096),
        gpu_layers: Map.get(overrides_map, :gpu_layers, :all),
        threads: Map.get(overrides_map, :threads, 4),
        parallel: Map.get(overrides_map, :parallel, 2),
        flash_attn: Map.get(overrides_map, :flash_attn, :on),
        api_key: Map.get(overrides_map, :api_key, "fixture-token"),
        api_prefix: Map.get(overrides_map, :api_prefix, "/managed"),
        ready_timeout_ms: Map.get(overrides_map, :ready_timeout_ms, 2_000),
        health_interval_ms: Map.get(overrides_map, :health_interval_ms, 50),
        execution_surface: [surface_kind: :local_subprocess],
        environment: %{
          "LLAMA_CPP_EX_FAKE_MODE" => Map.get(overrides_map, :mode, "ready"),
          "LLAMA_CPP_EX_FAKE_STATE_DIR" => fixture.state_dir
        },
        metadata: Map.get(overrides_map, :metadata, %{})
      }
      |> Map.merge(Map.drop(overrides_map, [:mode]))
    end

    defp script_path do
      Path.expand(
        "../../../../../../../llama_cpp_ex/examples/support/fake_llama_server.py",
        __DIR__
      )
    end

    defp unique_state_dir do
      Path.join(
        System.tmp_dir!(),
        "jido_integration_llama_fixture_#{System.unique_integer([:positive, :monotonic])}"
      )
    end

    defp find_free_port do
      {:ok, socket} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(socket)
      :ok = :gen_tcp.close(socket)
      port
    end
  end

  defmodule CloudHTTP do
  end

  setup do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)
    ControlPlane.reset!()
    _ = LlamaCppEx.unregister_backend()

    Req.Test.stub(CloudHTTP, fn conn ->
      Req.Test.json(conn, %{
        "id" => "cmpl_inference_cloud_123",
        "model" => "gpt-4o-mini",
        "choices" => [
          %{
            "finish_reason" => "stop",
            "message" => %{
              "role" => "assistant",
              "content" => "Phase 4 cloud path is alive."
            }
          }
        ],
        "usage" => %{
          "prompt_tokens" => 12,
          "completion_tokens" => 7,
          "total_tokens" => 19
        }
      })
    end)

    on_exit(fn ->
      _ = SelfHostedInferenceCore.stop_all_instances()
      _ = LlamaCppEx.unregister_backend()
    end)

    :ok
  end

  test "builds an endpoint-shaped ReqLLM call spec from an endpoint descriptor" do
    request =
      InferenceRequest.new!(%{
        request_id: "req-call-spec-endpoint-1",
        operation: :stream_text,
        messages: [%{role: "user", content: "Stream from the local endpoint"}],
        prompt: nil,
        model_preference: %{provider: "openai", id: "ignored-on-endpoint"},
        target_preference: %{target_class: "self_hosted_endpoint"},
        stream?: true,
        tool_policy: %{},
        output_constraints: %{temperature: 0.1},
        metadata: %{}
      })

    endpoint =
      EndpointDescriptor.new!(%{
        endpoint_id: "endpoint-call-spec-1",
        runtime_kind: :service,
        management_mode: :jido_managed,
        target_class: :self_hosted_endpoint,
        protocol: :openai_chat_completions,
        base_url: "http://127.0.0.1:8080/v1",
        headers: %{
          "authorization" => "Bearer local-token",
          "x-jido-route" => "inference"
        },
        provider_identity: :llama_cpp,
        model_identity: "llama-3.2-3b-instruct",
        source_runtime: :llama_cpp_ex,
        source_runtime_ref: "llama-runtime-1",
        lease_ref: "lease-call-spec-1",
        health_ref: "health-call-spec-1",
        boundary_ref: "boundary-call-spec-1",
        capabilities: %{streaming?: true},
        metadata: %{}
      })

    call_spec =
      ReqLLMCallSpec.from_endpoint(
        request,
        %{
          run_id: "run-call-spec-endpoint-1",
          attempt_id: "run-call-spec-endpoint-1:1",
          observability: %{trace_id: "trace-call-spec-endpoint-1"}
        },
        endpoint
      )

    assert call_spec.operation == :stream_text
    assert call_spec.model_spec.provider == :openai
    assert call_spec.model_spec.id == "llama-3.2-3b-instruct"
    assert call_spec.base_url == "http://127.0.0.1:8080/v1"
    assert call_spec.headers == %{"x-jido-route" => "inference"}
    assert call_spec.options == %{api_key: "local-token", temperature: 0.1}
    assert call_spec.observability == %{trace_id: "trace-call-spec-endpoint-1"}
  end

  test "invoke_inference/2 records durable cloud execution truth through req_llm" do
    request =
      InferenceRequest.new!(%{
        request_id: "req-live-cloud-1",
        operation: :generate_text,
        messages: [%{role: "user", content: "Summarize phase 4"}],
        prompt: nil,
        model_preference: %{provider: "openai", id: "gpt-4o-mini"},
        target_preference: %{target_class: "cloud_provider"},
        stream?: false,
        tool_policy: %{},
        output_constraints: %{},
        metadata: %{tenant_id: "tenant-live-cloud-1"}
      })

    assert {:ok, result} =
             ControlPlane.invoke_inference(
               request,
               api_key: "cloud-fixture-token",
               req_http_options: [plug: {Req.Test, CloudHTTP}],
               run_id: "run-live-cloud-1",
               decision_ref: "decision-live-cloud-1",
               trace_id: "trace-live-cloud-1"
             )

    assert result.inference_result.status == :ok
    assert result.inference_result.finish_reason == :stop
    assert result.compatibility_result.metadata.route == :cloud
    assert result.endpoint_descriptor == nil
    assert result.backend_manifest == nil

    assert Enum.map(ControlPlane.events(result.run.run_id), & &1.type) == [
             "inference.request_admitted",
             "inference.attempt_started",
             "inference.compatibility_evaluated",
             "inference.target_resolved",
             "inference.attempt_completed"
           ]

    assert {:ok, attempt} = ControlPlane.fetch_attempt(result.attempt.attempt_id)
    assert attempt.output["inference_result"]["status"] == "ok"
    assert attempt.output["compatibility_result"]["metadata"]["route"] == "cloud"
  end

  @tag skip:
         not @socket_capable? and
           "requires a socket-capable environment for llama_cpp_ex endpoint proof"
  test "invoke_inference/2 records durable self-hosted streaming truth through a llama.cpp endpoint" do
    fixture = FakeLlamaServerFixture.new!()

    on_exit(fn ->
      FakeLlamaServerFixture.cleanup(fixture)
    end)

    assert :ok = LlamaCppEx.register_backend()

    request =
      InferenceRequest.new!(%{
        request_id: "req-live-self-hosted-1",
        operation: :stream_text,
        messages: [%{role: "user", content: "Stream the self-hosted phase 4 proof"}],
        prompt: nil,
        model_preference: %{provider: "openai", id: "fixture-llama"},
        target_preference: %{
          target_class: "self_hosted_endpoint",
          backend: "llama_cpp",
          boot_spec:
            FakeLlamaServerFixture.boot_spec(
              fixture,
              alias: "fixture-llama",
              api_key: "fixture-token",
              api_prefix: "/managed"
            )
        },
        stream?: true,
        tool_policy: %{},
        output_constraints: %{temperature: 0.1},
        metadata: %{tenant_id: "tenant-live-self-hosted-1"}
      })

    assert {:ok, result} =
             ControlPlane.invoke_inference(
               request,
               run_id: "run-live-self-hosted-1",
               decision_ref: "decision-live-self-hosted-1",
               trace_id: "trace-live-self-hosted-1",
               ttl_ms: 5_000
             )

    assert result.inference_result.status == :ok
    assert result.inference_result.streaming?
    assert result.inference_result.finish_reason == :stop
    assert result.compatibility_result.metadata.route == :self_hosted
    assert result.endpoint_descriptor.target_class == :self_hosted_endpoint
    assert result.endpoint_descriptor.base_url == "http://127.0.0.1:#{fixture.port}/managed/v1"
    assert result.backend_manifest.backend == :llama_cpp
    assert result.lease_ref.lease_ref == result.endpoint_descriptor.lease_ref
    assert result.stream.opened.checkpoint_policy == :summary
    assert result.stream.closed.chunk_count > 0
    assert result.stream.closed.byte_count > 0

    assert Enum.map(ControlPlane.events(result.run.run_id), & &1.type) == [
             "inference.request_admitted",
             "inference.attempt_started",
             "inference.compatibility_evaluated",
             "inference.target_resolved",
             "inference.stream_opened",
             "inference.stream_checkpoint",
             "inference.stream_closed",
             "inference.attempt_completed"
           ]

    assert {:ok, attempt} = ControlPlane.fetch_attempt(result.attempt.attempt_id)
    assert attempt.output["endpoint_descriptor"]["provider_identity"] == "llama_cpp"
    assert attempt.output["compatibility_result"]["metadata"]["route"] == "self_hosted"
    assert attempt.output["lease_ref"]["lease_ref"] == result.lease_ref.lease_ref
  end
end
