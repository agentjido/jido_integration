defmodule Jido.Integration.V2.AsmRuntimeBridge.SessionStore do
  @moduledoc false

  use Agent

  @type entry :: pid()

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @spec fetch(String.t()) :: {:ok, entry()} | :error
  def fetch(session_id) when is_binary(session_id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.fetch(state, session_id) do
        {:ok, pid} when is_pid(pid) ->
          fetch_live_pid(pid, state, session_id)

        {:ok, _stale_pid} ->
          {:error, Map.delete(state, session_id)}

        :error ->
          {:error, state}
      end
    end)
  end

  defp fetch_live_pid(pid, state, session_id) when is_pid(pid) do
    if Process.alive?(pid) do
      {{:ok, pid}, state}
    else
      {:error, prune_session(state, session_id)}
    end
  end

  @spec put(String.t(), entry()) :: :ok
  def put(session_id, pid) when is_binary(session_id) and is_pid(pid) do
    Agent.update(__MODULE__, fn state -> Map.put(state, session_id, pid) end)
  end

  @spec delete(String.t()) :: :ok
  def delete(session_id) when is_binary(session_id) do
    Agent.update(__MODULE__, fn state -> Map.delete(state, session_id) end)
  end

  @spec reset!() :: :ok
  def reset! do
    Agent.update(__MODULE__, fn _state -> %{} end)
  end

  defp prune_session(state, session_id), do: Map.delete(state, session_id)
end
