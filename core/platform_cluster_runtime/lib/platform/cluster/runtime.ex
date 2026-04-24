defmodule Platform.Cluster.Runtime do
  @moduledoc """
  Canonical Horde runtime for Phase 7 memory-path singleton placement.

  Hosts start `child_spec/1` once per runtime node. Memory-path packages then
  use `register_singleton/3` and `locate/2` instead of constructing their own
  distributed registries.
  """

  @app :jido_integration_v2_platform_cluster_runtime
  @registry __MODULE__.Registry
  @dynamic_supervisor __MODULE__.DynamicSupervisor
  @runtime_supervisor __MODULE__.Supervisor
  @sync_interval 50
  @node_roles [:web, :worker, :temporal_worker, :memory_reader, :memory_writer, :stacklab_probe]

  @type singleton_kind :: atom()
  @type singleton_key :: term()
  @type singleton_start_spec ::
          {module(), keyword()}
          | %{
              optional(:id) => term(),
              required(:start) => {module(), :start_link, [keyword()]},
              optional(atom()) => term()
            }

  @doc "Returns the canonical memory-path node roles."
  @spec node_roles() :: [atom()]
  def node_roles, do: @node_roles

  @doc "Returns the runtime child spec for a host supervision tree."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) when is_list(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc "Starts the Horde registry and dynamic supervisor runtime."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    Supervisor.start_link(child_specs(opts),
      strategy: :one_for_one,
      name: Keyword.get(opts, :name, @runtime_supervisor)
    )
  end

  @doc "Returns the Horde child specs used by `start_link/1`."
  @spec child_specs(keyword()) :: [{module(), keyword()}]
  def child_specs(opts \\ []) when is_list(opts) do
    [
      {Horde.Registry,
       [
         name: Keyword.get(opts, :registry_name, @registry),
         keys: :unique,
         members: :auto,
         delta_crdt_options: [sync_interval: @sync_interval]
       ]},
      {Horde.DynamicSupervisor,
       [
         name: Keyword.get(opts, :dynamic_supervisor_name, @dynamic_supervisor),
         strategy: :one_for_one,
         members: :auto,
         distribution_strategy: Horde.UniformQuorumDistribution,
         delta_crdt_options: [sync_interval: @sync_interval]
       ]}
    ]
  end

  @doc "Starts or returns the singleton process for a `(kind, key)` pair."
  @spec register_singleton(singleton_kind(), singleton_key(), singleton_start_spec()) ::
          {:ok, pid()} | {:error, term()}
  def register_singleton(kind, key, start_spec) when is_atom(kind) do
    singleton_key = singleton_key(kind, key)
    child_spec = normalize_start_spec(start_spec, singleton_key)

    case Horde.DynamicSupervisor.start_child(dynamic_supervisor_name(), child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:ok, pid, _info} -> {:ok, pid}
      {:error, {:already_started, pid}} when is_pid(pid) -> {:ok, pid}
      {:error, {:already_registered, pid}} when is_pid(pid) -> {:ok, pid}
      {:error, {:name_taken, pid}} when is_pid(pid) -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Locates the singleton process for a `(kind, key)` pair."
  @spec locate(singleton_kind(), singleton_key()) :: {:ok, pid()} | {:error, :not_found}
  def locate(kind, key) when is_atom(kind) do
    case Horde.Registry.lookup(registry_name(), singleton_key(kind, key)) do
      [{pid, _value} | _rest] when is_pid(pid) -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp normalize_start_spec({module, opts}, singleton_key)
       when is_atom(module) and is_list(opts) do
    %{
      id: singleton_key,
      start: {module, :start_link, [Keyword.put(opts, :name, via_name(singleton_key))]},
      restart: :permanent
    }
  end

  defp normalize_start_spec(%{start: {module, :start_link, [opts]}} = spec, singleton_key)
       when is_atom(module) and is_list(opts) do
    spec
    |> Map.put(:id, Map.get(spec, :id, singleton_key))
    |> Map.put(:start, {module, :start_link, [Keyword.put(opts, :name, via_name(singleton_key))]})
  end

  defp normalize_start_spec(start_spec, _singleton_key), do: start_spec

  defp via_name(singleton_key), do: {:via, Horde.Registry, {registry_name(), singleton_key}}
  defp singleton_key(kind, key), do: {kind, key}

  defp registry_name do
    Application.get_env(@app, :registry_name, @registry)
  end

  defp dynamic_supervisor_name do
    Application.get_env(@app, :dynamic_supervisor_name, @dynamic_supervisor)
  end
end
