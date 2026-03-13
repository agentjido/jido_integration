defmodule Jido.Integration.V2.ControlPlane.Registry do
  @moduledoc false

  use Agent

  alias Jido.Integration.V2.Manifest

  def start_link(_opts) do
    Agent.start_link(fn -> %{manifests: %{}, capabilities: %{}} end, name: __MODULE__)
  end

  def register_manifest(%Manifest{} = manifest) do
    Agent.update(__MODULE__, fn state ->
      capabilities =
        Enum.reduce(manifest.capabilities, state.capabilities, fn capability, acc ->
          Map.put(acc, capability.id, capability)
        end)

      %{
        state
        | manifests: Map.put(state.manifests, manifest.connector, manifest),
          capabilities: capabilities
      }
    end)
  end

  def capabilities do
    Agent.get(__MODULE__, fn state ->
      state.capabilities
      |> Map.values()
      |> Enum.sort_by(& &1.id)
    end)
  end

  def fetch_capability(capability_id) do
    Agent.get(__MODULE__, fn state ->
      case Map.fetch(state.capabilities, capability_id) do
        {:ok, capability} -> {:ok, capability}
        :error -> {:error, :unknown_capability}
      end
    end)
  end

  def reset! do
    Agent.update(__MODULE__, fn _ -> %{manifests: %{}, capabilities: %{}} end)
  end
end
