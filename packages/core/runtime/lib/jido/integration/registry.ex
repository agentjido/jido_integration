defmodule Jido.Integration.Registry do
  @moduledoc """
  Connector registry — discovery, lookup, and cache for registered adapters.

  The registry maintains a mapping of connector IDs to adapter modules.
  Adapters are registered at startup or dynamically at runtime.

  ## Adapter ID Format

  Adapter IDs are strings (never atoms), globally unique, and stable.
  Convention: `vendor.connector_name` or just `connector_name`.
  """

  use GenServer

  alias Jido.Integration.Error

  @type entry :: %{
          id: String.t(),
          module: module(),
          manifest: Jido.Integration.Manifest.t(),
          registered_at: DateTime.t()
        }

  # Client API

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Register a connector adapter module.

  The module must implement `Jido.Integration.Adapter`.
  """
  @spec register(module(), keyword()) :: :ok | {:error, Error.t()}
  def register(adapter_module, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:register, adapter_module})
  end

  @doc """
  Unregister a connector by ID.
  """
  @spec unregister(String.t(), keyword()) :: :ok | {:error, Error.t()}
  def unregister(connector_id, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:unregister, connector_id})
  end

  @doc """
  Look up a connector adapter by ID.
  """
  @spec lookup(String.t(), keyword()) :: {:ok, module()} | {:error, Error.t()}
  def lookup(connector_id, opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, {:lookup, connector_id})
  end

  @doc """
  List all registered connectors.
  """
  @spec list(keyword()) :: [entry()]
  def list(opts \\ []) do
    server = Keyword.get(opts, :server, __MODULE__)
    GenServer.call(server, :list)
  end

  @doc """
  Check if a connector is registered.
  """
  @spec registered?(String.t(), keyword()) :: boolean()
  def registered?(connector_id, opts \\ []) do
    case lookup(connector_id, opts) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    {:ok, %{adapters: %{}}}
  end

  @impl true
  def handle_call({:register, adapter_module}, _from, state) do
    id = adapter_module.id()
    manifest = adapter_module.manifest()

    with :ok <- validate_registration_id(id),
         :ok <- validate_manifest_id(id, manifest),
         {:ok, adapters} <- put_adapter(state.adapters, id, adapter_module, manifest) do
      :telemetry.execute(
        [:jido, :integration, :registry, :registered],
        %{count: map_size(adapters)},
        %{connector_id: id, module: adapter_module}
      )

      {:reply, :ok, %{state | adapters: adapters}}
    else
      {:error, %Error{} = error} ->
        {:reply, {:error, error}, state}
    end
  rescue
    e ->
      {:reply,
       {:error, Error.new(:internal, "Failed to register adapter: #{Exception.message(e)}")},
       state}
  end

  @impl true
  def handle_call({:unregister, connector_id}, _from, state) do
    if Map.has_key?(state.adapters, connector_id) do
      new_adapters = Map.delete(state.adapters, connector_id)

      :telemetry.execute(
        [:jido, :integration, :registry, :unregistered],
        %{count: map_size(new_adapters)},
        %{connector_id: connector_id}
      )

      {:reply, :ok, %{state | adapters: new_adapters}}
    else
      {:reply, {:error, Error.new(:invalid_request, "Connector not found: #{connector_id}")},
       state}
    end
  end

  @impl true
  def handle_call({:lookup, connector_id}, _from, state) do
    case Map.get(state.adapters, connector_id) do
      nil ->
        {:reply, {:error, Error.new(:invalid_request, "Connector not found: #{connector_id}")},
         state}

      entry ->
        {:reply, {:ok, entry.module}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    entries =
      state.adapters
      |> Map.values()
      |> Enum.sort_by(& &1.id)

    {:reply, entries, state}
  end

  defp validate_registration_id(id) when is_binary(id) and id != "", do: :ok

  defp validate_registration_id(id) do
    {:error,
     Error.new(:invalid_request, "Connector id must be a non-empty string, got: #{inspect(id)}")}
  end

  defp validate_manifest_id(id, %Jido.Integration.Manifest{id: manifest_id})
       when manifest_id == id,
       do: :ok

  defp validate_manifest_id(id, %Jido.Integration.Manifest{id: manifest_id}) do
    {:error,
     Error.new(
       :invalid_request,
       "Adapter id #{inspect(id)} does not match manifest id #{inspect(manifest_id)}"
     )}
  end

  defp validate_manifest_id(_id, manifest) do
    {:error,
     Error.new(
       :invalid_request,
       "Adapter manifest must be a Jido.Integration.Manifest, got: #{inspect(manifest)}"
     )}
  end

  defp put_adapter(adapters, id, adapter_module, manifest) do
    case Map.get(adapters, id) do
      nil ->
        {:ok, Map.put(adapters, id, entry(id, adapter_module, manifest))}

      %{module: ^adapter_module} ->
        {:ok, Map.put(adapters, id, entry(id, adapter_module, manifest))}

      %{module: existing_module} ->
        {:error,
         Error.new(
           :invalid_request,
           "Connector id conflict: #{id} is already registered by #{inspect(existing_module)}"
         )}
    end
  end

  defp entry(id, adapter_module, manifest) do
    %{
      id: id,
      module: adapter_module,
      manifest: manifest,
      registered_at: DateTime.utc_now()
    }
  end
end
