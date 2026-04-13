defmodule Jido.Integration.V2.RuntimeRouter.SessionStore do
  @moduledoc false

  use Agent

  @type entry :: %{
          driver_module: module(),
          session: Jido.RuntimeControl.SessionHandle.t()
        }

  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @spec fetch(term()) :: {:ok, entry()} | :error
  def fetch(key) do
    Agent.get(__MODULE__, fn state -> Map.fetch(state, key) end)
  end

  @spec put(term(), entry()) :: :ok
  def put(key, entry) when is_map(entry) do
    Agent.update(__MODULE__, fn state -> Map.put(state, key, entry) end)
  end

  @spec delete(term()) :: :ok
  def delete(key) do
    Agent.update(__MODULE__, fn state -> Map.delete(state, key) end)
  end

  @spec entries() :: [{term(), entry()}]
  def entries do
    Agent.get(__MODULE__, &Map.to_list/1)
  end

  @spec reset!() :: :ok
  def reset! do
    Agent.update(__MODULE__, fn _state -> %{} end)
  end
end
