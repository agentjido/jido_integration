defmodule Jido.Integration.V2.ControlPlane.Registry do
  @moduledoc false

  use Agent

  alias Jido.Integration.V2.Manifest

  def start_link(_opts) do
    Agent.start_link(fn -> %{manifests: %{}, capabilities: %{}} end, name: __MODULE__)
  end

  def register_manifest(%Manifest{} = manifest) do
    Agent.update(__MODULE__, fn state ->
      previous_manifest = Map.get(state.manifests, manifest.connector)

      capabilities =
        state.capabilities
        |> drop_manifest_capabilities(previous_manifest)
        |> put_manifest_capabilities(manifest)

      %{
        state
        | manifests: Map.put(state.manifests, manifest.connector, manifest),
          capabilities: capabilities
      }
    end)
  end

  def connectors do
    Agent.get(__MODULE__, fn state ->
      state.manifests
      |> Map.values()
      |> Enum.sort_by(& &1.connector)
    end)
  end

  def fetch_connector(connector_id) do
    Agent.get(__MODULE__, fn state ->
      case Map.fetch(state.manifests, connector_id) do
        {:ok, manifest} -> {:ok, manifest}
        :error -> {:error, :unknown_connector}
      end
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

  defp drop_manifest_capabilities(capabilities, nil), do: capabilities

  defp drop_manifest_capabilities(capabilities, %Manifest{} = manifest) do
    Enum.reduce(Manifest.capabilities(manifest), capabilities, fn capability, acc ->
      Map.delete(acc, capability.id)
    end)
  end

  defp put_manifest_capabilities(capabilities, %Manifest{} = manifest) do
    Enum.reduce(Manifest.capabilities(manifest), capabilities, fn capability, acc ->
      Map.put(acc, capability.id, capability)
    end)
  end
end
