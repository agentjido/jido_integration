defmodule Jido.Integration.V2.SessionKernel.SessionStore do
  @moduledoc false

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def fetch(key) do
    Agent.get(__MODULE__, fn state ->
      case Map.fetch(state, key) do
        {:ok, session} -> {:ok, session}
        :error -> :error
      end
    end)
  end

  def put(key, session) do
    Agent.update(__MODULE__, fn state -> Map.put(state, key, session) end)
  end

  def delete(key) do
    Agent.update(__MODULE__, fn state -> Map.delete(state, key) end)
  end

  def delete_session(session_id) do
    Agent.update(__MODULE__, fn state ->
      Enum.reduce(state, %{}, fn
        {{:session_id, ^session_id}, _session}, acc ->
          acc

        {{:reuse_key, _reuse_key}, %{session_id: ^session_id}}, acc ->
          acc

        {_key, %{session_id: ^session_id}}, acc ->
          acc

        {key, session}, acc ->
          Map.put(acc, key, session)
      end)
    end)
  end

  def reset! do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end
end
