defmodule Jido.Integration.V2.StoreLocal.TestSupport do
  @moduledoc false

  alias Jido.Integration.TestTmpDir
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.StoreLocal

  @spec reconfigure!(keyword()) :: :ok
  def reconfigure!(opts \\ []) do
    StoreLocal.configure_defaults!(opts)
    ensure_started!()
    restart_store!()
  end

  @spec reset_all!() :: :ok
  def reset_all! do
    ControlPlane.reset!()
    :ok
  end

  @spec restart_store!() :: :ok
  def restart_store! do
    case Application.stop(:jido_integration_v2_store_local) do
      :ok -> :ok
      {:error, {:not_started, :jido_integration_v2_store_local}} -> :ok
    end

    {:ok, _} = Application.ensure_all_started(:jido_integration_v2_store_local)
    :ok
  end

  @spec tmp_dir!() :: String.t()
  def tmp_dir! do
    TestTmpDir.create!("jido_integration_v2_store_local_tests")
  end

  @spec cleanup!(String.t()) :: :ok
  def cleanup!(dir) do
    TestTmpDir.cleanup!(dir)
  end

  defp ensure_started! do
    {:ok, _} = Application.ensure_all_started(:jido_integration_v2_control_plane)
    :ok
  end
end
