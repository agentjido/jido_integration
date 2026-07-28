defmodule Jido.Integration.V2.AsmRuntimeBridge.SessionStore do
  @moduledoc false

  use Agent

  @type entry :: %{
          session_ref: pid(),
          execution_inputs: keyword()
        }

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @spec fetch(String.t()) :: {:ok, pid()} | :error
  def fetch(session_id) when is_binary(session_id) do
    case fetch_entry(session_id) do
      {:ok, %{session_ref: session_ref}} -> {:ok, session_ref}
      :error -> :error
    end
  end

  @spec execution_inputs(String.t()) :: {:ok, keyword()} | :error
  def execution_inputs(session_id) when is_binary(session_id) do
    case fetch_entry(session_id) do
      {:ok, %{execution_inputs: execution_inputs}} -> {:ok, execution_inputs}
      :error -> :error
    end
  end

  defp fetch_entry(session_id) do
    Agent.get_and_update(__MODULE__, fn state ->
      case Map.fetch(state, session_id) do
        {:ok, %{session_ref: pid} = entry} when is_pid(pid) ->
          fetch_live_entry(entry, state, session_id)

        {:ok, _invalid_entry} ->
          {:error, Map.delete(state, session_id)}

        :error ->
          {:error, state}
      end
    end)
  end

  defp fetch_live_entry(%{session_ref: pid} = entry, state, session_id) when is_pid(pid) do
    if Process.alive?(pid) do
      {{:ok, entry}, state}
    else
      {:error, prune_session(state, session_id)}
    end
  end

  @spec put(String.t(), pid(), keyword()) :: :ok
  def put(session_id, pid, execution_inputs)
      when is_binary(session_id) and is_pid(pid) and is_list(execution_inputs) do
    entry = %{session_ref: pid, execution_inputs: execution_inputs}
    Agent.update(__MODULE__, fn state -> Map.put(state, session_id, entry) end)
  end

  @spec delete(String.t()) :: :ok
  def delete(session_id) when is_binary(session_id) do
    Agent.update(__MODULE__, fn state -> Map.delete(state, session_id) end)
  end

  @spec reset!() :: :ok
  def reset! do
    __MODULE__
    |> Agent.get_and_update(fn state -> {Map.values(state), %{}} end)
    |> Enum.each(&stop_session_entry/1)

    :ok
  end

  defp prune_session(state, session_id), do: Map.delete(state, session_id)

  defp stop_session_entry(%{session_ref: pid}) when is_pid(pid) do
    if Process.alive?(pid) do
      _ = ASM.stop_session(pid)
    end

    :ok
  end

  defp stop_session_entry(_invalid_entry), do: :ok
end
