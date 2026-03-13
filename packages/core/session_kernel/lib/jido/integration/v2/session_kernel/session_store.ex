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

  def reset! do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end
end
