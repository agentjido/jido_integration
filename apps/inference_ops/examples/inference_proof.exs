Application.ensure_all_started(:inets)
Application.ensure_all_started(:ssl)
Application.ensure_all_started(:agent_session_manager)

alias Jido.Integration.V2.Apps.InferenceOps
alias ASM.ProviderBackend.{Event, Info}
alias CliSubprocessCore.Event, as: CoreEvent
alias CliSubprocessCore.Payload

defmodule CloudHTTP do
end

defmodule FakeASMBackend do
  use GenServer

  @behaviour ASM.ProviderBackend

  defstruct [:config, :subscriber, :subscription_ref]

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
         raw_info: %{backend: :example_cli_endpoint, provider: config.provider.name}
       )}
    end
  end

  def send_input(_server, _input, _opts), do: :ok
  def end_input(_server), do: :ok
  def interrupt(_server), do: :ok

  def close(server) do
    GenServer.stop(server, :normal)
  catch
    :exit, _ -> :ok
  end

  def subscribe(server, pid, ref) do
    GenServer.call(server, {:subscribe, pid, ref})
  end

  def info(server) do
    GenServer.call(server, :info)
  end

  def init(config) do
    {:ok, %__MODULE__{config: config, subscriber: nil, subscription_ref: nil}}
  end

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
       raw_info: %{backend: :example_cli_endpoint, provider: state.config.provider.name}
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

defmodule ExampleFixture do
  def new! do
    port = find_free_port()

    state_dir =
      Path.join(
        System.tmp_dir!(),
        "inference_ops_example_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(state_dir)
    File.write!(Path.join(state_dir, "health.txt"), "healthy")
    %{port: port, state_dir: state_dir}
  end

  def boot_spec(fixture) do
    %{
      binary_path: System.find_executable("python3") || "python3",
      launcher_args: [
        Path.expand("../test/support/fake_llama_server.py", __DIR__)
      ],
      model: "/models/demo.gguf",
      alias: "fixture-llama",
      host: "127.0.0.1",
      port: fixture.port,
      ctx_size: 4_096,
      gpu_layers: :all,
      threads: 4,
      parallel: 2,
      flash_attn: :on,
      api_key: "fixture-token",
      api_prefix: "/managed",
      ready_timeout_ms: 2_000,
      health_interval_ms: 50,
      execution_surface: [surface_kind: :local_subprocess],
      environment: %{
        "LLAMA_CPP_EX_FAKE_MODE" => "ready",
        "LLAMA_CPP_EX_FAKE_STATE_DIR" => fixture.state_dir,
        "LLAMA_CPP_SDK_FAKE_MODE" => "ready",
        "LLAMA_CPP_SDK_FAKE_STATE_DIR" => fixture.state_dir
      },
      metadata: %{}
    }
  end

  def cleanup(fixture) do
    File.rm_rf(fixture.state_dir)
  end

  defp find_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end

Req.Test.stub(CloudHTTP, fn conn ->
  Req.Test.json(conn, %{
    "id" => "cmpl_inference_ops_example_cloud_123",
    "model" => "gpt-4o-mini",
    "choices" => [
      %{
        "finish_reason" => "stop",
        "message" => %{
          "role" => "assistant",
          "content" => "Inference ops example cloud proof is alive."
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

original_asm_endpoint = Application.get_env(:agent_session_manager, ASM.InferenceEndpoint)

{:ok, cloud_result} =
  InferenceOps.run_cloud_proof(
    api_key: "cloud-fixture-token",
    req_http_options: [plug: {Req.Test, CloudHTTP}],
    run_id: "run-inference-ops-example-cloud-1",
    decision_ref: "decision-inference-ops-example-cloud-1",
    trace_id: "trace-inference-ops-example-cloud-1"
  )

{:ok, cloud_packet} =
  InferenceOps.review_packet(
    cloud_result.run.run_id,
    %{attempt_id: cloud_result.attempt.attempt_id}
  )

IO.inspect(
  %{
    cloud_run_id: cloud_result.run.run_id,
    cloud_route: cloud_result.compatibility_result.metadata.route,
    cloud_events: Enum.map(cloud_packet.events, & &1.type)
  },
  label: "cloud_proof"
)

Application.put_env(
  :agent_session_manager,
  ASM.InferenceEndpoint,
  backend_module: FakeASMBackend,
  backend_opts: [
    script: [
      {:run_started, Payload.RunStarted.new(command: "example", args: ["prompt"], cwd: "/tmp")},
      {:assistant_delta,
       Payload.AssistantDelta.new(content: "Inference ops example CLI proof is alive.")},
      {:result, Payload.Result.new(status: :completed, stop_reason: :end_turn)}
    ]
  ]
)

{:ok, cli_result} =
  InferenceOps.run_cli_proof(
    run_id: "run-inference-ops-example-cli-1",
    decision_ref: "decision-inference-ops-example-cli-1",
    trace_id: "trace-inference-ops-example-cli-1",
    ttl_ms: 5_000
  )

{:ok, cli_packet} =
  InferenceOps.review_packet(
    cli_result.run.run_id,
    %{attempt_id: cli_result.attempt.attempt_id}
  )

IO.inspect(
  %{
    cli_run_id: cli_result.run.run_id,
    cli_route: cli_result.compatibility_result.metadata.route,
    cli_backend: cli_result.backend_manifest.backend,
    cli_events: Enum.map(cli_packet.events, & &1.type)
  },
  label: "cli_proof"
)

fixture = ExampleFixture.new!()

try do
  {:ok, self_hosted_result} =
    InferenceOps.run_self_hosted_proof(
      boot_spec: ExampleFixture.boot_spec(fixture),
      run_id: "run-inference-ops-example-self-hosted-1",
      decision_ref: "decision-inference-ops-example-self-hosted-1",
      trace_id: "trace-inference-ops-example-self-hosted-1",
      ttl_ms: 5_000
    )

  {:ok, self_hosted_packet} =
    InferenceOps.review_packet(
      self_hosted_result.run.run_id,
      %{attempt_id: self_hosted_result.attempt.attempt_id}
    )

  IO.inspect(
    %{
      self_hosted_run_id: self_hosted_result.run.run_id,
      self_hosted_route: self_hosted_result.compatibility_result.metadata.route,
      endpoint: self_hosted_result.endpoint_descriptor.base_url,
      self_hosted_events: Enum.map(self_hosted_packet.events, & &1.type)
    },
    label: "self_hosted_proof"
  )
after
  if is_nil(original_asm_endpoint) do
    Application.delete_env(:agent_session_manager, ASM.InferenceEndpoint)
  else
    Application.put_env(:agent_session_manager, ASM.InferenceEndpoint, original_asm_endpoint)
  end

  ExampleFixture.cleanup(fixture)
  _ = SelfHostedInferenceCore.stop_all_instances()
  _ = LlamaCppSdk.unregister_backend()
end
