defmodule Jido.Integration.V2.StorePostgres.DurableRuntime do
  @moduledoc """
  Production composition root for Jido durable auth and control-plane truth.

  Hosts start this single child with explicit Postgres, persistence-profile, and
  credential-materializer options. No package application or persistence owner
  is allowed to infer a memory store when this composition is absent.
  """

  use Supervisor

  alias Jido.Integration.V2.Auth.Persistence, as: AuthPersistence
  alias Jido.Integration.V2.ControlPlane.Persistence, as: ControlPlanePersistence
  alias Jido.Integration.V2.StorePostgres
  alias Jido.Integration.V2.StorePostgres.Repo

  @required_options [:repo_options, :persistence_profile, :credential_materializers]

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts = validate_options!(opts)

    %{
      id: {__MODULE__, Keyword.get(opts, :name, __MODULE__)},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    opts = validate_options!(opts)
    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    persistence_opts = persistence_options(opts)

    children =
      repository_children(opts) ++
        [
          {AuthPersistence.Owner, persistence_opts},
          {Jido.Integration.V2.Auth.RuntimeConfig, []},
          Supervisor.child_spec(
            {Task.Supervisor, name: Jido.Integration.V2.Auth.MaterializationSupervisor},
            id: Jido.Integration.V2.Auth.MaterializationSupervisor
          ),
          {ControlPlanePersistence.Owner,
           persistence_options_for_control_plane(persistence_opts)},
          {Jido.Integration.V2.ControlPlane.RuntimeConfig,
           attempt_reconciliation: Keyword.get(opts, :attempt_reconciliation)},
          {Jido.Integration.V2.ControlPlane.Registry, []},
          {Jido.Integration.V2.ControlPlane.AttemptReconciler, []},
          Supervisor.child_spec(
            {Task.Supervisor, name: Jido.Integration.V2.StorePostgres.TaskSupervisor},
            id: Jido.Integration.V2.StorePostgres.TaskSupervisor
          ),
          {__MODULE__.ManagedAccountBootstrap,
           credential_materializers: Keyword.fetch!(opts, :credential_materializers)},
          {Jido.Integration.V2.StorePostgres.SubmissionRetentionWorker,
           Keyword.get(opts, :submission_retention, [])}
        ]

    case external_repo_available(opts) do
      :ok -> Supervisor.init(children, strategy: :rest_for_one)
      {:error, reason} -> {:stop, reason}
    end
  end

  @doc """
  Validates the complete durable composition before its supervisor starts.

  The check resolves both persistence owners from the supplied options without
  consulting owner process state. Standalone mode briefly starts an unnamed
  Repo; external mode checks the already-supervised Repo. Both prove the
  database is reachable and all owned migrations are up.
  """
  @spec preflight(keyword()) :: :ok | {:error, term()}
  def preflight(opts) do
    opts = validate_options!(opts)
    expected_auth = StorePostgres.auth_store_modules()
    expected_control_plane = StorePostgres.control_plane_store_modules()
    auth_options = persistence_options(opts)
    control_plane_options = persistence_options_for_control_plane(auth_options)

    with {:ok, %AuthPersistence.Resolution{durable?: true, store_modules: ^expected_auth}} <-
           AuthPersistence.resolve(auth_options),
         {:ok,
          %ControlPlanePersistence.Resolution{
            durable?: true,
            store_modules: ^expected_control_plane
          }} <- ControlPlanePersistence.resolve(control_plane_options),
         :ok <- repo_preflight(opts) do
      :ok
    else
      {:ok, %AuthPersistence.Resolution{}} ->
        {:error, :auth_persistence_not_durable}

      {:ok, %ControlPlanePersistence.Resolution{}} ->
        {:error, :control_plane_persistence_not_durable}

      {:error, _reason} = error ->
        error

      _other ->
        {:error, :durable_persistence_resolution_invalid}
    end
  end

  @doc """
  Checks the running durable composition after it has started.
  """
  @spec post_start_health() :: :ok | {:error, term()}
  def post_start_health do
    expected_auth = StorePostgres.auth_store_modules()
    expected_control_plane = StorePostgres.control_plane_store_modules()
    expected_managed_store = StorePostgres.managed_account_store()

    with :ok <- running_repo_health(),
         {:ok, %AuthPersistence.Resolution{durable?: true, store_modules: ^expected_auth}} <-
           AuthPersistence.Owner.current(),
         {:ok,
          %ControlPlanePersistence.Resolution{
            durable?: true,
            store_modules: ^expected_control_plane
          }} <- ControlPlanePersistence.Owner.current(),
         %{
           managed_account_store: ^expected_managed_store,
           credential_materializers: materializers
         }
         when map_size(materializers) > 0 <- Jido.Integration.V2.Auth.RuntimeConfig.current() do
      :ok
    else
      {:ok, %AuthPersistence.Resolution{}} ->
        {:error, :auth_persistence_not_durable}

      {:ok, %ControlPlanePersistence.Resolution{}} ->
        {:error, :control_plane_persistence_not_durable}

      {:error, :not_started} ->
        {:error, :durable_runtime_not_started}

      %{} ->
        {:error, :managed_credential_materialization_not_configured}

      {:error, _reason} = error ->
        error

      _other ->
        {:error, :durable_runtime_not_ready}
    end
  end

  defp persistence_options(opts) do
    {:ok, capability} = StorePostgres.store_capability()

    [
      profile: Keyword.fetch!(opts, :persistence_profile),
      capabilities: [capability],
      store_modules: StorePostgres.auth_store_modules()
    ]
  end

  defp persistence_options_for_control_plane(opts) do
    Keyword.put(opts, :store_modules, StorePostgres.control_plane_store_modules())
  end

  defp validate_options!(opts) when is_list(opts) do
    missing = Enum.reject(@required_options, &Keyword.has_key?(opts, &1))

    cond do
      missing != [] ->
        raise ArgumentError, "missing durable runtime options: #{inspect(missing)}"

      not Keyword.keyword?(Keyword.fetch!(opts, :repo_options)) ->
        raise ArgumentError, "repo_options must be a keyword list"

      Keyword.has_key?(Keyword.fetch!(opts, :repo_options), :name) and
          Keyword.fetch!(Keyword.fetch!(opts, :repo_options), :name) != Repo ->
        raise ArgumentError, "repo_options name must be #{inspect(Repo)}"

      not is_atom(Keyword.fetch!(opts, :persistence_profile)) ->
        raise ArgumentError, "persistence_profile must be an atom"

      Keyword.get(opts, :repo_mode, :standalone) not in [:standalone, :external] ->
        raise ArgumentError, "repo_mode must be :standalone or :external"

      not valid_materializers?(Keyword.fetch!(opts, :credential_materializers)) ->
        raise ArgumentError, "credential_materializers must be a non-empty provider map"

      not valid_preflight_timeout?(Keyword.get(opts, :preflight_timeout, 30_000)) ->
        raise ArgumentError, "preflight_timeout must be a positive integer"

      true ->
        opts
    end
  end

  defp validate_options!(_opts),
    do: raise(ArgumentError, "durable runtime options must be a keyword list")

  defp valid_materializers?(materializers)
       when is_map(materializers) and map_size(materializers) > 0 do
    Enum.all?(materializers, fn
      {family, module} when is_binary(family) and family != "" and is_atom(module) ->
        Code.ensure_loaded?(module) and function_exported?(module, :materialize, 2) and
          function_exported?(module, :revoke, 2)

      _other ->
        false
    end)
  end

  defp valid_materializers?(_materializers), do: false

  defp valid_preflight_timeout?(timeout), do: is_integer(timeout) and timeout > 0

  defp repository_children(opts) do
    case Keyword.get(opts, :repo_mode, :standalone) do
      :standalone -> [{Repo, Keyword.fetch!(opts, :repo_options)}]
      :external -> []
    end
  end

  defp external_repo_available(opts) do
    case Keyword.get(opts, :repo_mode, :standalone) do
      :standalone ->
        :ok

      :external ->
        case running_repo_health() do
          :ok -> :ok
          {:error, :postgres_not_started} -> {:error, :external_repo_not_started}
          {:error, _reason} = error -> error
        end
    end
  end

  defp repo_preflight(opts) do
    case Keyword.get(opts, :repo_mode, :standalone) do
      :standalone -> temporary_repo_preflight(Keyword.fetch!(opts, :repo_options), opts)
      :external -> running_repo_health()
    end
  end

  defp temporary_repo_preflight(repo_options, opts) do
    caller = self()
    token = make_ref()

    {worker, monitor} =
      spawn_monitor(fn ->
        send(caller, {token, do_repo_preflight(repo_options)})
      end)

    receive do
      {^token, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^worker, _reason} ->
        {:error, :postgres_preflight_failed}
    after
      Keyword.get(opts, :preflight_timeout, 30_000) ->
        Process.exit(worker, :kill)

        receive do
          {:DOWN, ^monitor, :process, ^worker, _reason} -> :ok
        end

        {:error, :postgres_preflight_timeout}
    end
  end

  defp do_repo_preflight(repo_options) do
    repo_options = Keyword.put(repo_options, :name, nil)
    adapter_config = Keyword.merge(Repo.config(), repo_options)

    with {:ok, _ecto_apps} <- Application.ensure_all_started(:ecto_sql, :temporary),
         {:ok, _adapter_apps} <-
           Repo.__adapter__().ensure_all_started(adapter_config, :temporary),
         {:ok, repo_pid} <- Repo.start_link(repo_options) do
      try do
        repo_pid
        |> migration_status()
        |> reject_pending_migrations()
      after
        if Process.alive?(repo_pid), do: Supervisor.stop(repo_pid, :normal, 5_000)
      end
    else
      {:error, _reason} -> {:error, :postgres_unreachable}
    end
  rescue
    _exception -> {:error, :postgres_preflight_failed}
  catch
    :exit, _reason -> {:error, :postgres_unreachable}
    _kind, _reason -> {:error, :postgres_preflight_failed}
  end

  defp running_repo_health do
    case Process.whereis(Repo) do
      nil ->
        {:error, :postgres_not_started}

      repo_pid ->
        repo_pid
        |> migration_status()
        |> reject_pending_migrations()
    end
  rescue
    _exception -> {:error, :postgres_health_check_failed}
  catch
    :exit, _reason -> {:error, :postgres_health_check_failed}
  end

  defp migration_status(dynamic_repo) do
    {:ok,
     Ecto.Migrator.migrations(Repo, [StorePostgres.migrations_path()], dynamic_repo: dynamic_repo)}
  rescue
    _exception -> {:error, :migration_verification_failed}
  catch
    :exit, _reason -> {:error, :migration_verification_failed}
  end

  defp reject_pending_migrations({:ok, migrations}) do
    case Enum.reject(migrations, &(elem(&1, 0) == :up)) do
      [] -> :ok
      pending -> {:error, {:pending_migrations, Enum.map(pending, &elem(&1, 1))}}
    end
  end

  defp reject_pending_migrations({:error, _reason} = error), do: error

  defmodule ManagedAccountBootstrap do
    @moduledoc false

    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

    @impl true
    def init(opts) do
      :ok =
        Jido.Integration.V2.Auth.configure_managed_accounts!(
          store: Jido.Integration.V2.StorePostgres.managed_account_store(),
          materializers: Keyword.fetch!(opts, :credential_materializers)
        )

      {:ok, %{configured?: true}}
    end
  end
end
