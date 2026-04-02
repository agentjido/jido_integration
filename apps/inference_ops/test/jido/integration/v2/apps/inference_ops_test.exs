defmodule Jido.Integration.V2.Apps.InferenceOpsTest do
  use ExUnit.Case, async: false

  alias Jido.Integration.V2.Apps.InferenceOps
  alias Jido.Integration.V2.ControlPlane
  alias ASM.ProviderBackend.{Event, Info}
  alias CliSubprocessCore.Event, as: CoreEvent
  alias CliSubprocessCore.Payload
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

  defmodule FakeCloudServerFixture do
    defstruct [:listener, :port, :response_body, :server_task]

    @type t :: %__MODULE__{
            listener: port(),
            port: pos_integer(),
            response_body: String.t(),
            server_task: pid()
          }

    @spec new!(map()) :: t()
    def new!(response_payload) when is_map(response_payload) do
      {:ok, listener} =
        :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

      {:ok, port} = :inet.port(listener)
      response_body = Jason.encode!(response_payload)

      {:ok, server_task} =
        Task.start_link(fn ->
          accept_loop(listener, response_body)
        end)

      %__MODULE__{
        listener: listener,
        port: port,
        response_body: response_body,
        server_task: server_task
      }
    end

    @spec base_url(t()) :: String.t()
    def base_url(%__MODULE__{port: port}), do: "http://127.0.0.1:#{port}/v1"

    @spec cleanup(t()) :: :ok
    def cleanup(%__MODULE__{} = fixture) do
      :ok = :gen_tcp.close(fixture.listener)
      Process.exit(fixture.server_task, :shutdown)
      :ok
    end

    defp accept_loop(listener, response_body) do
      case :gen_tcp.accept(listener) do
        {:ok, socket} ->
          :ok = recv_request(socket, "")
          :ok = :gen_tcp.send(socket, http_response(response_body))
          :ok = :gen_tcp.close(socket)
          accept_loop(listener, response_body)

        {:error, :closed} ->
          :ok
      end
    end

    defp recv_request(socket, buffer) do
      case :binary.match(buffer, "\r\n\r\n") do
        {headers_end, 4} ->
          headers = binary_part(buffer, 0, headers_end + 4)
          body = binary_part(buffer, headers_end + 4, byte_size(buffer) - headers_end - 4)
          content_length = content_length(headers)

          if byte_size(body) >= content_length do
            :ok
          else
            {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
            recv_request(socket, buffer <> chunk)
          end

        :nomatch ->
          {:ok, chunk} = :gen_tcp.recv(socket, 0, 5_000)
          recv_request(socket, buffer <> chunk)
      end
    end

    defp content_length(headers) do
      headers
      |> String.split("\r\n", trim: true)
      |> Enum.find_value(0, fn line ->
        case String.split(line, ":", parts: 2) do
          [name, value] ->
            if String.downcase(name) == "content-length" do
              value |> String.trim() |> String.to_integer()
            else
              false
            end

          _other ->
            false
        end
      end)
    end

    defp http_response(response_body) do
      [
        "HTTP/1.1 200 OK\r\n",
        "content-type: application/json\r\n",
        "content-length: ",
        Integer.to_string(byte_size(response_body)),
        "\r\n",
        "connection: close\r\n",
        "\r\n",
        response_body
      ]
    end
  end

  defmodule FakeASMBackend do
    use GenServer

    @behaviour ASM.ProviderBackend

    defstruct [:config, :subscriber, :subscription_ref]

    @impl true
    def start_run(config) when is_map(config) do
      with {:ok, pid} <- GenServer.start_link(__MODULE__, config) do
        {:ok, pid,
         Info.new(
           provider: config.provider.name,
           lane: Map.get(config, :lane, :core),
           backend: __MODULE__,
           runtime: __MODULE__,
           capabilities: [],
           session_pid: pid,
           raw_info: %{backend: :fake_asm, provider: config.provider.name}
         )}
      end
    end

    @impl true
    def send_input(_server, _input, _opts), do: :ok

    @impl true
    def end_input(_server), do: :ok

    @impl true
    def interrupt(_server), do: :ok

    @impl true
    def close(server) do
      GenServer.stop(server, :normal)
    catch
      :exit, _ -> :ok
    end

    @impl true
    def subscribe(server, pid, ref) do
      GenServer.call(server, {:subscribe, pid, ref})
    end

    @impl true
    def info(server) do
      GenServer.call(server, :info)
    end

    @impl true
    def init(config) do
      {:ok, %__MODULE__{config: config, subscriber: nil, subscription_ref: nil}}
    end

    @impl true
    def handle_call({:subscribe, pid, ref}, _from, state) do
      state = %{state | subscriber: pid, subscription_ref: ref}
      emit_script(state)
      {:reply, :ok, state}
    end

    def handle_call(:info, _from, state) do
      {:reply,
       Info.new(
         provider: state.config.provider.name,
         lane: Map.get(state.config, :lane, :core),
         backend: __MODULE__,
         runtime: __MODULE__,
         capabilities: [],
         session_pid: self(),
         raw_info: %{backend: :fake_asm, provider: state.config.provider.name}
       ), state}
    end

    defp emit_script(%__MODULE__{} = state) do
      state.config.backend_opts
      |> Keyword.get(:script, [])
      |> Enum.each(fn {kind, payload} ->
        send(
          state.subscriber,
          Event.new(
            state.subscription_ref,
            CoreEvent.new(kind, provider: state.config.provider.name, payload: payload)
          )
        )
      end)
    end
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
    original_asm_endpoint = Application.get_env(:agent_session_manager, ASM.InferenceEndpoint)

    on_exit(fn ->
      _ = SelfHostedInferenceCore.stop_all_instances()
      _ = LlamaCppEx.unregister_backend()

      if is_nil(original_asm_endpoint) do
        Application.delete_env(:agent_session_manager, ASM.InferenceEndpoint)
      else
        Application.put_env(:agent_session_manager, ASM.InferenceEndpoint, original_asm_endpoint)
      end
    end)

    :ok
  end

  @tag skip:
         not @socket_capable? and
           "requires a socket-capable environment for the cloud proof"
  test "runs the cloud proof through the public inference facade and keeps it reviewable" do
    cloud_fixture =
      FakeCloudServerFixture.new!(%{
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

    on_exit(fn -> FakeCloudServerFixture.cleanup(cloud_fixture) end)

    request =
      Jido.Integration.V2.InferenceRequest.new!(%{
        request_id: "req-inference-ops-cloud",
        operation: :generate_text,
        messages: [%{role: "user", content: "Summarize the cloud proof flow"}],
        prompt: nil,
        model_preference: %{
          provider: "openai",
          id: "gpt-4o-mini",
          base_url: FakeCloudServerFixture.base_url(cloud_fixture)
        },
        target_preference: %{target_class: "cloud_provider"},
        stream?: false,
        tool_policy: %{},
        output_constraints: %{},
        metadata: %{tenant_id: "tenant-inference-ops-cloud"}
      })

    assert {:ok, result} =
             InferenceOps.run_cloud_proof(
               request: request,
               api_key: "cloud-fixture-token",
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
           "requires a socket-capable environment for the CLI proof"
  test "runs the CLI proof through the public inference facade and keeps it reviewable" do
    configure_asm_endpoint("Inference ops CLI proof is alive.")

    assert {:ok, result} =
             InferenceOps.run_cli_proof(
               run_id: "run-inference-ops-cli-1",
               decision_ref: "decision-inference-ops-cli-1",
               trace_id: "trace-inference-ops-cli-1",
               ttl_ms: 5_000
             )

    assert result.inference_result.status == :ok
    assert result.inference_result.streaming?
    assert result.response_text == "Inference ops CLI proof is alive."
    assert result.compatibility_result.metadata.route == :cli
    assert result.endpoint_descriptor.target_class == :cli_endpoint
    assert result.backend_manifest.backend == :asm_inference_endpoint

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

    assert packet.attempt.output["endpoint_descriptor"]["source_runtime"] ==
             "agent_session_manager"

    assert packet.attempt.output["backend_manifest"]["backend"] == "asm_inference_endpoint"
    assert packet.attempt.output["compatibility_result"]["metadata"]["route"] == "cli"
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

  defp configure_asm_endpoint(text) do
    Application.put_env(
      :agent_session_manager,
      ASM.InferenceEndpoint,
      backend_module: FakeASMBackend,
      backend_opts: [
        script: [
          {:run_started, Payload.RunStarted.new(command: "fake", args: ["prompt"], cwd: "/tmp")},
          {:assistant_delta, Payload.AssistantDelta.new(content: text)},
          {:result, Payload.Result.new(status: :completed, stop_reason: :end_turn)}
        ]
      ]
    )
  end
end
