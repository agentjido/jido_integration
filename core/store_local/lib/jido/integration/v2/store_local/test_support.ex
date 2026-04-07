defmodule Jido.Integration.V2.StoreLocal.TestSupport do
  @moduledoc false

  alias Jido.Integration.TestTmpDir
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.ControlPlane.Application, as: ControlPlaneApplication
  alias Jido.Integration.V2.StoreLocal

  @spec reconfigure!(keyword()) :: :ok
  def reconfigure!(opts \\ []) do
    StoreLocal.configure_defaults!(opts)
    restart_store!()
  end

  @spec reset_all!() :: :ok
  def reset_all! do
    ensure_store_local_started!()
    ensure_control_plane_started!()
    ControlPlane.reset!()
    :ok
  end

  @spec restart_store!() :: :ok
  def restart_store! do
    previous_pid = Process.whereis(Jido.Integration.V2.StoreLocal.Server)

    case previous_pid do
      nil ->
        ensure_store_local_started!()

      pid ->
        GenServer.stop(pid, :normal)
        ensure_store_local_started!()
        wait_for_server_restart(pid)
    end

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

  defp wait_for_server_restart(previous_pid, attempts \\ 40)
  defp wait_for_server_restart(_previous_pid, 0), do: raise("store local server did not restart")

  defp wait_for_server_restart(previous_pid, attempts) do
    case Process.whereis(Jido.Integration.V2.StoreLocal.Server) do
      nil ->
        Process.sleep(50)
        wait_for_server_restart(previous_pid, attempts - 1)

      ^previous_pid ->
        Process.sleep(50)
        wait_for_server_restart(previous_pid, attempts - 1)

      _new_pid ->
        :ok
    end
  end

  defp ensure_store_local_started! do
    _ = Jido.Integration.V2.StoreLocal.Server.storage_path()
    :ok
  end

  defp ensure_control_plane_started! do
    case Process.whereis(Jido.Integration.V2.ControlPlane.Registry) do
      nil ->
        case Process.whereis(Jido.Integration.V2.ControlPlane.Supervisor) do
          nil ->
            case ControlPlaneApplication.start(:normal, []) do
              {:ok, _pid} -> :ok
              {:error, {:already_started, _pid}} -> :ok
              {:error, reason} ->
                raise("control plane application did not start: #{inspect(reason)}")
            end

          _pid ->
            case Supervisor.restart_child(
                   Jido.Integration.V2.ControlPlane.Supervisor,
                   Jido.Integration.V2.ControlPlane.Registry
                 ) do
              {:ok, _child} -> :ok
              {:ok, _child, _info} -> :ok
              {:error, :already_present} -> :ok
              {:error, :running} -> :ok
              {:error, reason} ->
                raise("control plane registry did not restart: #{inspect(reason)}")
            end
        end

      _pid ->
        :ok
    end
  end
end
