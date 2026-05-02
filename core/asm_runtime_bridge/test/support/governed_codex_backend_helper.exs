defmodule Jido.Integration.V2.AsmRuntimeBridge.TestSupport.GovernedCodexBackend do
  @moduledoc false

  @behaviour ASM.ProviderBackend

  alias ASM.Event
  alias ASM.ProviderBackend.Event, as: BackendEvent
  alias ASM.ProviderBackend.Info
  alias ASM.RuntimeAuth.CodexMaterialization
  alias CliSubprocessCore.Payload

  defstruct [
    :config,
    :materialization,
    :backend_opts,
    subscribers: %{},
    emitted?: false
  ]

  @impl true
  def start_run(config) when is_map(config) do
    provider_opts = Map.get(config, :provider_opts, [])

    with {:ok, %CodexMaterialization{} = materialization} <-
           CodexMaterialization.authorize_config(config, provider_opts),
         {:ok, pid} <- Agent.start_link(fn -> new_state(config, materialization) end) do
      {:ok, pid,
       Info.new(
         provider: :codex,
         lane: :core,
         backend: __MODULE__,
         runtime: __MODULE__,
         capabilities: [:stream],
         observability: %{
           governed_codex_conformance: :deterministic,
           codex_materialization: CodexMaterialization.redacted_evidence(materialization)
         }
       )}
    end
  end

  @impl true
  def send_input(_pid, _input, _opts \\ []), do: :ok

  @impl true
  def end_input(_pid), do: :ok

  @impl true
  def interrupt(_pid), do: :ok

  @impl true
  def close(pid) when is_pid(pid) do
    state = Agent.get(pid, & &1)

    case cleanup_recipient(state) do
      test_pid when is_pid(test_pid) ->
        send(test_pid, {:governed_codex_backend_cleanup, cleanup_evidence(state)})

      _other ->
        :ok
    end

    Agent.stop(pid)
  catch
    :exit, _reason -> :ok
  end

  @impl true
  def subscribe(pid, subscriber, ref)
      when is_pid(pid) and is_pid(subscriber) and is_reference(ref) do
    Agent.update(pid, fn state ->
      %{state | subscribers: Map.put(state.subscribers, ref, subscriber)}
    end)

    emit_once(pid)
    :ok
  end

  @impl true
  def info(pid) when is_pid(pid) do
    materialization = Agent.get(pid, & &1.materialization)

    Info.new(
      provider: :codex,
      lane: :core,
      backend: __MODULE__,
      runtime: __MODULE__,
      capabilities: [:stream],
      observability: %{
        governed_codex_conformance: :deterministic,
        codex_materialization: CodexMaterialization.redacted_evidence(materialization)
      }
    )
  end

  defp new_state(config, %CodexMaterialization{} = materialization) do
    %__MODULE__{
      config: config,
      materialization: materialization,
      backend_opts: Map.get(config, :backend_opts, [])
    }
  end

  defp emit_once(pid) do
    Agent.get_and_update(pid, fn state ->
      if state.emitted? do
        {:already_emitted, state}
      else
        emit_events(state)
        {:emitted, %{state | emitted?: true}}
      end
    end)
  end

  defp emit_events(%__MODULE__{} = state) do
    Enum.each(state.subscribers, fn {ref, subscriber} ->
      Enum.each(script(state), fn event ->
        send(subscriber, BackendEvent.new_asm(ref, event))
      end)
    end)
  end

  defp script(%__MODULE__{} = state) do
    config = state.config
    run_id = Map.fetch!(config, :metadata).run_id
    session_id = Map.fetch!(config, :metadata).session_id
    provider_session_id = "codex-provider-session://phase10/deterministic"

    metadata =
      Map.merge(config.metadata, %{
        provider_session_id: provider_session_id,
        codex_materialization: CodexMaterialization.redacted_evidence(state.materialization)
      })

    [
      Event.new(
        :run_started,
        Payload.RunStarted.new(command: "governed-codex-deterministic"),
        run_id: run_id,
        session_id: session_id,
        provider: :codex,
        provider_session_id: provider_session_id,
        metadata: metadata
      ),
      Event.new(
        :assistant_delta,
        Payload.AssistantDelta.new(content: "deterministic governed codex"),
        run_id: run_id,
        session_id: session_id,
        provider: :codex,
        provider_session_id: provider_session_id,
        metadata: metadata
      ),
      Event.new(
        :result,
        Payload.Result.new(status: :completed, stop_reason: "completed"),
        run_id: run_id,
        session_id: session_id,
        provider: :codex,
        provider_session_id: provider_session_id,
        metadata: metadata
      )
    ]
  end

  defp cleanup_recipient(%__MODULE__{backend_opts: backend_opts}) when is_list(backend_opts) do
    Keyword.get(backend_opts, :test_pid)
  end

  defp cleanup_recipient(_state), do: nil

  defp cleanup_evidence(%__MODULE__{} = state) do
    %{
      cleanup_status: :completed,
      materialized_command: :redacted_materialized_command,
      materialized_cwd: :redacted_materialized_cwd,
      materialized_config_root: :redacted_materialized_config_root,
      env_keys: state.materialization.env |> Map.keys() |> Enum.sort(),
      credential_lease_ref: state.materialization.credential_lease_ref,
      native_auth_assertion_ref: state.materialization.native_auth_assertion_ref,
      connector_binding_ref: state.materialization.connector_binding_ref,
      provider_account_ref: state.materialization.provider_account_ref
    }
  end
end
