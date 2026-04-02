Application.ensure_all_started(:inets)
Application.ensure_all_started(:ssl)
Application.ensure_all_started(:agent_session_manager)
Application.ensure_all_started(:jido_integration_v2_control_plane)

alias ASM.ProviderBackend.{Event, Info}
alias CliSubprocessCore.Event, as: CoreEvent
alias CliSubprocessCore.Payload
alias Jido.Integration.V2.ControlPlane

defmodule ExampleASMBackend do
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

ControlPlane.reset!()

Application.put_env(
  :agent_session_manager,
  ASM.InferenceEndpoint,
  backend_module: ExampleASMBackend,
  backend_opts: [
    script: [
      {:run_started, Payload.RunStarted.new(command: "example", args: ["prompt"], cwd: "/tmp")},
      {:assistant_delta,
       Payload.AssistantDelta.new(content: "Control-plane CLI example is alive.")},
      {:result, Payload.Result.new(status: :completed, stop_reason: :end_turn)}
    ]
  ]
)

{:ok, result} =
  ControlPlane.invoke_inference(
    %{
      request_id: "req-control-plane-cli-example-1",
      operation: :stream_text,
      messages: [%{role: "user", content: "Stream through ASM.InferenceEndpoint"}],
      prompt: nil,
      model_preference: %{provider: "gemini", id: "gemini-2.5-pro"},
      target_preference: %{target_class: "cli_endpoint"},
      stream?: true,
      tool_policy: %{},
      output_constraints: %{},
      metadata: %{tenant_id: "tenant-control-plane-cli-example-1"}
    },
    run_id: "run-control-plane-cli-example-1",
    decision_ref: "decision-control-plane-cli-example-1",
    trace_id: "trace-control-plane-cli-example-1",
    ttl_ms: 5_000
  )

IO.inspect(
  %{
    run_id: result.run.run_id,
    attempt_id: result.attempt.attempt_id,
    route: result.compatibility_result.metadata.route,
    provider: result.endpoint_descriptor.provider_identity,
    backend: result.backend_manifest.backend,
    response_text: result.response_text,
    event_types: Enum.map(ControlPlane.events(result.run.run_id), & &1.type)
  },
  label: "inference_cli_endpoint_baseline"
)
