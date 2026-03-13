defmodule Jido.Integration.Auth.ConnectionStore.Disk do
  @moduledoc """
  File-backed connection store for durable local runtime state.
  """

  use GenServer

  alias Jido.Integration.Auth.Connection
  alias Jido.Integration.Runtime.Persistence

  @behaviour Jido.Integration.Auth.ConnectionStore

  @impl true
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} -> GenServer.start_link(__MODULE__, opts)
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @impl Jido.Integration.Auth.ConnectionStore
  def put(server, %Connection{} = connection) do
    GenServer.call(server, {:put, connection})
  end

  @impl Jido.Integration.Auth.ConnectionStore
  def fetch(server, connection_id) do
    GenServer.call(server, {:fetch, connection_id})
  end

  @impl Jido.Integration.Auth.ConnectionStore
  def delete(server, connection_id) do
    GenServer.call(server, {:delete, connection_id})
  end

  @impl Jido.Integration.Auth.ConnectionStore
  def list(server) do
    GenServer.call(server, :list)
  end

  @impl GenServer
  def init(opts) do
    path = Persistence.default_path("connections", opts)
    {:ok, %{path: path, entries: Persistence.load(path, %{})}}
  end

  @impl GenServer
  def handle_call({:put, %Connection{} = connection}, _from, state) do
    entries = Map.put(state.entries, connection.id, connection)
    :ok = Persistence.persist(state.path, entries)
    {:reply, :ok, %{state | entries: entries}}
  end

  @impl GenServer
  def handle_call({:fetch, connection_id}, _from, state) do
    result =
      case Map.get(state.entries, connection_id) do
        %Connection{} = connection -> {:ok, connection}
        nil -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:delete, connection_id}, _from, state) do
    if Map.has_key?(state.entries, connection_id) do
      entries = Map.delete(state.entries, connection_id)
      :ok = Persistence.persist(state.path, entries)
      {:reply, :ok, %{state | entries: entries}}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.entries), state}
  end
end
