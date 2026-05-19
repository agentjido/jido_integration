defmodule Jido.Integration.V2.ControlPlane.Persistence.Resolution do
  @moduledoc "Resolved control-plane persistence profile and store modules."

  @enforce_keys [:profile, :store_modules, :capabilities, :durable?]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          profile: term(),
          store_modules: map(),
          capabilities: [atom()],
          durable?: boolean()
        }
end

defmodule Jido.Integration.V2.ControlPlane.Persistence.Owner do
  @moduledoc false

  use GenServer

  alias Jido.Integration.V2.ControlPlane.Persistence

  @name __MODULE__

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @spec current() :: {:ok, Persistence.Resolution.t()} | {:error, :not_started}
  def current do
    case Process.whereis(@name) do
      nil -> {:error, :not_started}
      _pid -> GenServer.call(@name, :current)
    end
  end

  @spec put(Persistence.Resolution.t()) :: :ok | {:error, :not_started}
  def put(%Persistence.Resolution{} = resolution) do
    case Process.whereis(@name) do
      nil -> {:error, :not_started}
      _pid -> GenServer.call(@name, {:put, resolution})
    end
  end

  @spec reset() :: :ok
  def reset do
    case Process.whereis(@name) do
      nil -> :ok
      _pid -> GenServer.call(@name, :reset)
    end
  end

  @impl true
  def init(opts) do
    {:ok, Persistence.resolve!(opts)}
  end

  @impl true
  def handle_call(:current, _from, resolution), do: {:reply, {:ok, resolution}, resolution}

  def handle_call({:put, resolution}, _from, _state), do: {:reply, :ok, resolution}

  def handle_call(:reset, _from, _state) do
    resolution = Persistence.resolve!([])
    {:reply, :ok, resolution}
  end
end

defmodule Jido.Integration.V2.ControlPlane.Persistence do
  @moduledoc """
  Persistence policy resolver for control-plane stores.
  """

  alias GroundPlane.PersistencePolicy
  alias Jido.Integration.V2.ControlPlane.Persistence.Resolution
  alias Jido.Integration.V2.ControlPlane.RunLedger

  @required_store_keys [
    :run_store,
    :attempt_store,
    :event_store,
    :artifact_store,
    :claim_check_store,
    :target_store,
    :ingress_store,
    :profile_registry_store
  ]
  @memory_store_modules %{
    run_store: RunLedger,
    attempt_store: RunLedger,
    event_store: RunLedger,
    artifact_store: RunLedger,
    claim_check_store: RunLedger,
    target_store: RunLedger,
    ingress_store: RunLedger,
    profile_registry_store: RunLedger
  }
  @profile_aliases %{
    "memory-default" => :mickey_mouse,
    "mickey_mouse" => :mickey_mouse,
    "memory_debug" => :memory_debug,
    "local_restart_safe" => :local_restart_safe,
    "integration_postgres" => :integration_postgres,
    "ops_durable" => :ops_durable,
    "full_debug_tracked" => :full_debug_tracked,
    "distributed_partitioned" => :distributed_partitioned
  }

  @spec resolve(keyword() | map()) :: {:ok, Resolution.t()} | {:error, term()}
  def resolve(attrs \\ []) do
    attrs = normalize_attrs(attrs)

    with {:ok, profile} <- resolve_profile(attrs),
         capabilities <- List.wrap(value(attrs, :capabilities, [])),
         :ok <- PersistencePolicy.preflight(profile, capabilities, checker(attrs)),
         {:ok, store_modules} <- store_modules_for(profile, attrs) do
      {:ok,
       %Resolution{
         profile: profile,
         store_modules: store_modules,
         capabilities: capabilities,
         durable?: profile.durable?
       }}
    end
  end

  @spec resolve!(keyword() | map()) :: Resolution.t()
  def resolve!(attrs \\ []) do
    case resolve(attrs) do
      {:ok, resolution} -> resolution
      {:error, reason} -> raise ArgumentError, message: inspect(reason)
    end
  end

  @spec configure!(keyword() | map()) :: :ok
  def configure!(attrs \\ []) do
    resolution = resolve!(attrs)

    case __MODULE__.Owner.put(resolution) do
      :ok ->
        :ok

      {:error, :not_started} ->
        raise ArgumentError,
              "control-plane persistence owner is not started; start Jido.Integration.V2.ControlPlane.Application before configuring persistence"
    end
  end

  @spec reset!() :: :ok
  def reset! do
    __MODULE__.Owner.reset()
  end

  @spec current() :: Resolution.t()
  def current do
    case __MODULE__.Owner.current() do
      {:ok, resolution} -> resolution
      {:error, :not_started} -> resolve!([])
    end
  end

  @spec store_modules() :: map()
  def store_modules, do: current().store_modules

  @spec store_module(atom()) :: module()
  def store_module(key), do: Map.fetch!(store_modules(), key)

  @spec partition(keyword() | map()) :: PersistencePolicy.Partition.t()
  def partition(attrs) do
    attrs = normalize_attrs(attrs)

    struct(
      PersistencePolicy.Partition,
      Map.take(attrs, PersistencePolicy.Partition.fields())
    )
  end

  @spec memory_store_modules() :: map()
  def memory_store_modules, do: @memory_store_modules

  defp resolve_profile(attrs) do
    attrs
    |> normalize_profile_hint()
    |> PersistencePolicy.resolve()
  end

  defp normalize_profile_hint(attrs) do
    case value(attrs, :profile) || value(attrs, :persistence_profile) do
      nil ->
        attrs

      profile ->
        Map.put(attrs, :profile, normalize_profile(profile))
    end
  end

  defp normalize_profile(profile) when is_binary(profile),
    do: Map.get(@profile_aliases, profile, profile)

  defp normalize_profile(profile), do: profile

  defp checker(attrs) do
    case value(attrs, :checker) do
      checker when is_function(checker, 1) -> checker
      _other -> fn _capability -> :ok end
    end
  end

  defp store_modules_for(%PersistencePolicy.Profile{durable?: false}, attrs) do
    case value(attrs, :store_modules) do
      nil -> {:ok, @memory_store_modules}
      store_modules -> validate_store_modules(store_modules)
    end
  end

  defp store_modules_for(%PersistencePolicy.Profile{} = profile, attrs) do
    case value(attrs, :store_modules) do
      nil -> {:error, {:durable_store_modules_required, profile.default_tier}}
      store_modules -> validate_store_modules(store_modules)
    end
  end

  defp validate_store_modules(store_modules) when is_list(store_modules),
    do: store_modules |> Map.new() |> validate_store_modules()

  defp validate_store_modules(store_modules) when is_map(store_modules) do
    missing = Enum.reject(@required_store_keys, &Map.has_key?(store_modules, &1))

    if missing == [] do
      {:ok, Map.take(store_modules, @required_store_keys)}
    else
      {:error, {:missing_store_modules, missing}}
    end
  end

  defp validate_store_modules(_store_modules), do: {:error, :invalid_store_modules}

  defp normalize_attrs(attrs) when is_list(attrs), do: Map.new(attrs)
  defp normalize_attrs(attrs) when is_map(attrs), do: attrs

  defp value(attrs, field, default \\ nil) do
    Map.get(attrs, field) || Map.get(attrs, Atom.to_string(field), default)
  end
end
