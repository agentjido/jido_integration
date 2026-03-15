defmodule Jido.Integration.V2.StreamRuntime.Store do
  @moduledoc false

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def fetch(key) do
    Agent.get(__MODULE__, fn state ->
      case Map.fetch(state, key) do
        {:ok, stream} -> {:ok, stream}
        :error -> :error
      end
    end)
  end

  def put(key, stream) do
    Agent.update(__MODULE__, fn state -> Map.put(state, key, stream) end)
  end

  def delete(key) do
    Agent.update(__MODULE__, fn state -> Map.delete(state, key) end)
  end

  def reset! do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end
end
