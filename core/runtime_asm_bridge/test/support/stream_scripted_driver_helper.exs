defmodule Jido.Integration.V2.RuntimeAsmBridge.TestSupport.StreamScriptedDriver do
  @moduledoc false

  alias ASM.{Event, Message}
  alias CliSubprocessCore.Payload

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: {__MODULE__, Keyword.get(opts, :run_id, make_ref())},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts) when is_list(opts) do
    opts
    |> Enum.into(%{})
    |> then(fn context -> Task.start_link(fn -> emit(context) end) end)
  end

  @spec start(map()) :: {:ok, pid()}
  def start(%{} = context) do
    {:ok, spawn(fn -> emit(context) end)}
  end

  defp emit(context) do
    script =
      case Map.get(context, :driver_opts) do
        driver_opts when is_list(driver_opts) ->
          Keyword.get(driver_opts, :script, Map.get(context, :script, default_script()))

        _other ->
          Map.get(context, :script, default_script())
      end

    notify_subscriber(context, :run_started, Payload.RunStarted.new(command: "scripted-driver"))

    Enum.each(script, fn {kind, payload} ->
      notify_subscriber(context, kind, normalize_payload(kind, payload))
    end)

    if is_pid(context.subscriber) do
      send(context.subscriber, {:asm_run_done, context.run_id})
    end
  end

  defp notify_subscriber(context, kind, payload) when is_pid(context.subscriber) do
    event = %Event{
      id: Event.generate_id(),
      kind: kind,
      run_id: context.run_id,
      session_id: context.session_id,
      provider: context.provider,
      payload: payload,
      timestamp: DateTime.utc_now()
    }

    send(context.subscriber, {:asm_run_event, context.run_id, event})
  end

  defp notify_subscriber(_context, _kind, _payload), do: :ok

  defp normalize_payload(:assistant_delta, %Payload.AssistantDelta{} = payload), do: payload

  defp normalize_payload(:assistant_delta, %Message.Partial{content_type: :text, delta: delta}) do
    Payload.AssistantDelta.new(content: delta)
  end

  defp normalize_payload(:result, %Payload.Result{} = payload), do: payload

  defp normalize_payload(:result, %Message.Result{stop_reason: stop_reason}) do
    Payload.Result.new(status: :completed, stop_reason: stop_reason)
  end

  defp normalize_payload(:error, %Payload.Error{} = payload), do: payload

  defp normalize_payload(:error, %Message.Error{} = payload) do
    Payload.Error.new(
      severity: payload.severity,
      message: payload.message,
      code: to_string(payload.kind)
    )
  end

  defp normalize_payload(_kind, payload), do: payload

  defp default_script do
    [
      {:assistant_delta, %Message.Partial{content_type: :text, delta: "hello "}},
      {:assistant_delta, %Message.Partial{content_type: :text, delta: "from scripted driver"}},
      {:result, %Message.Result{stop_reason: :end_turn}}
    ]
  end
end
