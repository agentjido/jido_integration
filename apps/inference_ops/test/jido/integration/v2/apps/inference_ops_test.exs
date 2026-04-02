defmodule Jido.Integration.V2.Apps.InferenceOpsTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Apps.InferenceOps
  alias Jido.Integration.V2.ControlPlane
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

  defmodule CloudHTTP do
  end

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
        ctx_size: 4_096,
        gpu_layers: :all,
        threads: 4,
        parallel: 2,
        flash_attn: :on,
        api_key: Map.get(overrides_map, :api_key, "fixture-token"),
        api_prefix: Map.get(overrides_map, :api_prefix, "/managed"),
        ready_timeout_ms: 2_000,
        health_interval_ms: 50,
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
        "../../../../../../../../llama_cpp_ex/examples/support/fake_llama_server.py",
        __DIR__
      )
    end

    defp unique_state_dir do
      Path.join(
        System.tmp_dir!(),
        "jido_integration_inference_ops_fixture_#{System.unique_integer([:positive, :monotonic])}"
      )
    end

    defp find_free_port do
      {:ok, socket} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(socket)
      :ok = :gen_tcp.close(socket)
      port
    end
  end

  setup do
    Application.ensure_all_started(:inets)
    Application.ensure_all_started(:ssl)
    ControlPlane.reset!()
    _ = LlamaCppEx.unregister_backend()

    Req.Test.stub(CloudHTTP, fn conn ->
      Req.Test.json(conn, %{
        "id" => "cmpl_inference_ops_cloud_123",
        "model" => "gpt-4o-mini",
        "choices" => [
          %{
            "finish_reason" => "stop",
            "message" => %{
              "role" => "assistant",
              "content" => "Inference ops cloud proof is alive."
            }
          }
        ],
        "usage" => %{
          "prompt_tokens" => 9,
          "completion_tokens" => 6,
          "total_tokens" => 15
        }
      })
    end)

    on_exit(fn ->
      _ = SelfHostedInferenceCore.stop_all_instances()
      _ = LlamaCppEx.unregister_backend()
    end)

    :ok
  end

  test "runs the cloud proof through the public inference facade and keeps it reviewable" do
    assert {:ok, result} =
             InferenceOps.run_cloud_proof(
               api_key: "cloud-fixture-token",
               req_http_options: [plug: {Req.Test, CloudHTTP}],
               run_id: "run-inference-ops-cloud-1",
               decision_ref: "decision-inference-ops-cloud-1",
               trace_id: "trace-inference-ops-cloud-1"
             )

    assert result.inference_result.status == :ok
    assert result.compatibility_result.metadata.route == :cloud

    assert {:ok, packet} =
             InferenceOps.review_packet(
               result.run.run_id,
               %{attempt_id: result.attempt.attempt_id}
             )

    assert packet.connector.connector_id == "inference"
    assert packet.connector.runtime_families == [:inference]
    assert packet.attempt.output["compatibility_result"]["metadata"]["route"] == "cloud"
  end

  @tag skip:
         not @socket_capable? and
           "requires a socket-capable environment for the self-hosted proof"
  test "runs the self-hosted llama proof through the public inference facade and keeps it reviewable" do
    fixture = FakeLlamaServerFixture.new!()

    on_exit(fn ->
      FakeLlamaServerFixture.cleanup(fixture)
    end)

    assert {:ok, result} =
             InferenceOps.run_self_hosted_proof(
               boot_spec:
                 FakeLlamaServerFixture.boot_spec(
                   fixture,
                   alias: "fixture-llama",
                   api_key: "fixture-token",
                   api_prefix: "/managed"
                 ),
               run_id: "run-inference-ops-self-hosted-1",
               decision_ref: "decision-inference-ops-self-hosted-1",
               trace_id: "trace-inference-ops-self-hosted-1",
               ttl_ms: 5_000
             )

    assert result.inference_result.status == :ok
    assert result.inference_result.streaming?
    assert result.endpoint_descriptor.base_url == "http://127.0.0.1:#{fixture.port}/managed/v1"
    assert result.compatibility_result.metadata.route == :self_hosted
    assert result.lease_ref.lease_ref == result.endpoint_descriptor.lease_ref

    assert {:ok, packet} =
             InferenceOps.review_packet(
               result.run.run_id,
               %{attempt_id: result.attempt.attempt_id}
             )

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

    assert packet.attempt.output["endpoint_descriptor"]["provider_identity"] == "llama_cpp"
    assert packet.attempt.output["lease_ref"]["lease_ref"] == result.lease_ref.lease_ref
  end
end
