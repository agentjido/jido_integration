defmodule Jido.Integration.V2.StorePostgres do
  @moduledoc """
  Postgres durability package owning the Repo, migrations, and SQL sandbox posture.
  """

  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Supervisor, as: StorePostgresSupervisor

  @spec repo() :: module()
  def repo, do: Repo

  @spec ensure_started!() :: :ok
  def ensure_started! do
    started_repo? =
      case Process.whereis(Repo) do
        nil ->
          ensure_repo_process_started!()
          true

        _pid ->
          false
      end

    if started_repo? and Repo.config()[:pool] == Ecto.Adapters.SQL.Sandbox do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    end

    :ok
  end

  @spec migrations_path() :: String.t()
  def migrations_path do
    Repo.config()
    |> Keyword.get(:priv, "priv/repo")
    |> Path.join("migrations")
    |> Path.expand()
  end

  defp ensure_repo_process_started! do
    case Process.whereis(StorePostgresSupervisor) do
      nil ->
        case Jido.Integration.V2.StorePostgres.Application.start(:normal, []) do
          {:ok, _pid} ->
            :ok

          {:error, {:already_started, _pid}} ->
            :ok

          {:error, reason} ->
            raise("store_postgres application did not start: #{inspect(reason)}")
        end

      _pid ->
        case Supervisor.restart_child(StorePostgresSupervisor, Repo) do
          {:ok, _child} -> :ok
          {:ok, _child, _info} -> :ok
          {:error, :already_present} -> :ok
          {:error, :running} -> :ok
          {:error, reason} -> raise("store_postgres repo did not restart: #{inspect(reason)}")
        end
    end

    wait_for_process!(Repo, "store_postgres repo")
  end

  defp wait_for_process!(name, label, attempts \\ 40)

  defp wait_for_process!(_name, label, 0), do: raise("#{label} did not start")

  defp wait_for_process!(name, label, attempts) do
    case Process.whereis(name) do
      nil ->
        Process.sleep(50)
        wait_for_process!(name, label, attempts - 1)

      _pid ->
        :ok
    end
  end
end
