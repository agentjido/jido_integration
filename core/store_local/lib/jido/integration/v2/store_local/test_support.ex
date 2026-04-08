defmodule Jido.Integration.V2.StoreLocal.TestSupport do
  @moduledoc false

  alias Jido.Integration.TestTmpDir
  alias Jido.Integration.V2.StoreLocal

  @spec reconfigure!(keyword()) :: :ok
  def reconfigure!(opts \\ []) do
    StoreLocal.configure_defaults!(opts)
    restart_store!()
  end

  @spec reset_all!() :: :ok
  def reset_all! do
    ensure_store_local_started!()
    StoreLocal.reset!()
    Application.delete_env(:jido_integration_v2_auth, :refresh_handler)
    Application.delete_env(:jido_integration_v2_auth, :external_secret_resolver)
    :ok
  end

  @spec restart_store!() :: :ok
  def restart_store! do
    previous_pid = Process.whereis(Jido.Integration.V2.StoreLocal.Server)

    case previous_pid do
      nil ->
        ensure_store_local_started!()

      pid ->
        restart_supervised_server!(pid)
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

  defp restart_supervised_server!(pid) do
    supervisor = Jido.Integration.V2.StoreLocal.Application

    case Process.whereis(supervisor) do
      nil ->
        GenServer.stop(pid, :normal)
        ensure_store_local_started!()

      _supervisor_pid ->
        :ok = Supervisor.terminate_child(supervisor, Jido.Integration.V2.StoreLocal.Server)

        case Supervisor.restart_child(supervisor, Jido.Integration.V2.StoreLocal.Server) do
          {:ok, _child} -> :ok
          {:ok, _child, _info} -> :ok
          {:error, reason} -> raise("store local server did not restart: #{inspect(reason)}")
        end
    end
  end
end
