defmodule Jido.Integration.V2.StorePostgres.TestSupport do
  @moduledoc false

  alias Ecto.Adapters.Postgres, as: PostgresAdapter
  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Migrator
  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.Repo
  alias Jido.Integration.V2.StorePostgres.Schemas.ArtifactRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.AttemptRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.ConnectionRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.CredentialRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.DedupeKeyRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.EventRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.InstallRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.LeaseRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.RunRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.TargetRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.TriggerCheckpointRecord
  alias Jido.Integration.V2.StorePostgres.Schemas.TriggerRecord, as: TriggerRecordSchema

  @spec configure_defaults!(keyword()) :: :ok
  def configure_defaults!(opts \\ []) do
    Application.put_env(
      :jido_integration_v2_control_plane,
      :run_store,
      Jido.Integration.V2.StorePostgres.RunStore
    )

    Application.put_env(
      :jido_integration_v2_control_plane,
      :attempt_store,
      Jido.Integration.V2.StorePostgres.AttemptStore
    )

    Application.put_env(
      :jido_integration_v2_control_plane,
      :event_store,
      Jido.Integration.V2.StorePostgres.EventStore
    )

    Application.put_env(
      :jido_integration_v2_control_plane,
      :artifact_store,
      Jido.Integration.V2.StorePostgres.ArtifactStore
    )

    Application.put_env(
      :jido_integration_v2_control_plane,
      :target_store,
      Jido.Integration.V2.StorePostgres.TargetStore
    )

    Application.put_env(
      :jido_integration_v2_control_plane,
      :ingress_store,
      Jido.Integration.V2.StorePostgres.IngressStore
    )

    Application.put_env(
      :jido_integration_v2_auth,
      :credential_store,
      Jido.Integration.V2.StorePostgres.CredentialStore
    )

    Application.put_env(
      :jido_integration_v2_auth,
      :lease_store,
      Jido.Integration.V2.StorePostgres.LeaseStore
    )

    Application.put_env(
      :jido_integration_v2_auth,
      :connection_store,
      Jido.Integration.V2.StorePostgres.ConnectionStore
    )

    Application.put_env(
      :jido_integration_v2_auth,
      :install_store,
      Jido.Integration.V2.StorePostgres.InstallStore
    )

    Application.put_env(:jido_integration_v2_auth, :keyring, %{
      active_kid: "test-key-1",
      keys: %{
        "test-key-1" =>
          Base.encode64(:crypto.hash(:sha256, "jido_integration_v2_store_postgres_test_key"))
      }
    })

    configure_repo_defaults!(opts)
    :ok
  end

  @spec setup_database!(keyword()) :: :ok
  def setup_database!(opts \\ []) do
    previous_pool = current_repo_pool()
    configure_repo_defaults!(opts)
    restart_repo_if_pool_changed!(previous_pool, opts)
    _ = PostgresAdapter.storage_up(repo_config(opts))
    ensure_repo_started!()

    with_repo_ownership(opts, fn ->
      {:ok, _, _} =
        Migrator.with_repo(Repo, fn repo ->
          Migrator.run(repo, StorePostgres.migrations_path(), :up, all: true)
        end)

      reset_database!()
      :ok
    end)
  end

  @spec restart_repo!(atom()) :: :ok
  def restart_repo!(mode \\ :auto) do
    previous_pid =
      case Process.whereis(Repo) do
        nil ->
          nil

        pid ->
          ref = Process.monitor(pid)
          restart_supervised_repo!(pid)

          receive do
            {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
          after
            5_000 -> raise("repo did not stop")
          end

          pid
      end

    ensure_repo_started!()
    wait_for_repo(previous_pid)
    maybe_set_sandbox_mode(mode)
    :ok
  end

  @spec reset_database!() :: :ok
  def reset_database! do
    Repo.delete_all(TargetRecord)
    Repo.delete_all(ArtifactRecord)
    Repo.delete_all(EventRecord)
    Repo.delete_all(AttemptRecord)
    Repo.delete_all(RunRecord)
    Repo.delete_all(TriggerRecordSchema)
    Repo.delete_all(DedupeKeyRecord)
    Repo.delete_all(TriggerCheckpointRecord)
    Repo.delete_all(InstallRecord)
    Repo.delete_all(ConnectionRecord)
    Repo.delete_all(LeaseRecord)
    Repo.delete_all(CredentialRecord)
    :ok
  end

  @spec repo_config(keyword()) :: keyword()
  def repo_config(opts \\ []) do
    database =
      Keyword.get(
        opts,
        :database,
        System.get_env("JIDO_INTEGRATION_V2_DB_NAME", "jido_integration_v2_test")
      )

    pool = Keyword.get(opts, :pool, Ecto.Adapters.SQL.Sandbox)
    socket_dir = System.get_env("JIDO_INTEGRATION_V2_DB_SOCKET_DIR")

    [
      username: System.get_env("JIDO_INTEGRATION_V2_DB_USER", "postgres"),
      password: System.get_env("JIDO_INTEGRATION_V2_DB_PASSWORD", "postgres"),
      database: database,
      pool: pool,
      pool_size: parse_integer(System.get_env("JIDO_INTEGRATION_V2_DB_POOL_SIZE", "10"), 10),
      queue_target: 5_000,
      queue_interval: 1_000,
      timeout: 15_000,
      ownership_timeout: 60_000
    ] ++ connection_config(socket_dir)
  end

  defp ensure_repo_started! do
    case Jido.Integration.V2.StorePostgres.Application.start(:normal, []) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> raise("store_postgres application did not start: #{inspect(reason)}")
    end

    StorePostgres.assert_started!()
  end

  defp restart_repo_if_pool_changed!(previous_pool, opts) do
    desired_pool = repo_config(opts)[:pool]

    if Process.whereis(Repo) && previous_pool != desired_pool do
      restart_repo!()
    else
      :ok
    end
  end

  defp current_repo_pool do
    if Process.whereis(Repo) do
      repo_runtime_config()[:pool]
    end
  end

  defp configure_repo_defaults!(opts) do
    Application.put_env(:jido_integration_v2_store_postgres, :ecto_repos, [Repo])
    Application.put_env(:jido_integration_v2_store_postgres, Repo, repo_config(opts))
    :ok
  end

  defp with_repo_ownership(opts, fun) do
    if repo_config(opts)[:pool] == Sandbox do
      :ok = Sandbox.checkout(Repo)

      try do
        fun.()
      after
        Sandbox.checkin(Repo)
        Sandbox.mode(Repo, :manual)
      end
    else
      fun.()
    end
  end

  defp wait_for_repo(previous_pid, attempts \\ 40)

  defp wait_for_repo(_previous_pid, 0), do: raise("repo did not restart")

  defp wait_for_repo(previous_pid, attempts) do
    case Process.whereis(Repo) do
      nil ->
        Process.sleep(50)
        wait_for_repo(previous_pid, attempts - 1)

      ^previous_pid ->
        Process.sleep(50)
        wait_for_repo(previous_pid, attempts - 1)

      pid ->
        if repo_registered?(pid) do
          :ok
        else
          Process.sleep(50)
          wait_for_repo(previous_pid, attempts - 1)
        end
    end
  end

  defp maybe_set_sandbox_mode(mode) do
    if sandbox_pool?() do
      Sandbox.mode(Repo, mode)
    end
  end

  defp sandbox_pool? do
    repo_runtime_config()[:pool] == Sandbox
  end

  defp repo_registered?(pid) do
    case :ets.whereis(Ecto.Repo.Registry) do
      :undefined -> false
      table -> :ets.lookup(table, pid) != []
    end
  end

  defp repo_runtime_config do
    Application.get_env(:jido_integration_v2_store_postgres, Repo, repo_config())
  end

  defp restart_supervised_repo!(pid) do
    supervisor = Jido.Integration.V2.StorePostgres.Supervisor

    case Process.whereis(supervisor) do
      nil ->
        GenServer.stop(pid, :normal)

      _supervisor_pid ->
        :ok = Supervisor.terminate_child(supervisor, Repo)

        case Supervisor.restart_child(supervisor, Repo) do
          {:ok, _child} -> :ok
          {:ok, _child, _info} -> :ok
          {:error, reason} -> raise("store_postgres repo did not restart: #{inspect(reason)}")
        end
    end
  end

  defp parse_integer(value, fallback) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> fallback
    end
  end

  defp connection_config(socket_dir) when is_binary(socket_dir) and socket_dir != "" do
    [
      socket_dir: socket_dir,
      port: parse_integer(System.get_env("JIDO_INTEGRATION_V2_DB_PORT", "5432"), 5432)
    ]
  end

  defp connection_config(_socket_dir) do
    [
      hostname: System.get_env("JIDO_INTEGRATION_V2_DB_HOST", "127.0.0.1"),
      port: parse_integer(System.get_env("JIDO_INTEGRATION_V2_DB_PORT", "5432"), 5432)
    ]
  end
end
