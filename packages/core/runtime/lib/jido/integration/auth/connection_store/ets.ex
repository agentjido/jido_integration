defmodule Jido.Integration.Auth.ConnectionStore.ETS do
  @moduledoc """
  ETS-backed connection store for explicit local development mode.
  """

  use GenServer

  alias Jido.Integration.Auth.Connection

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
  def put(server, %Connection{} = connection), do: GenServer.call(server, {:put, connection})

  @impl Jido.Integration.Auth.ConnectionStore
  def fetch(server, connection_id), do: GenServer.call(server, {:fetch, connection_id})

  @impl Jido.Integration.Auth.ConnectionStore
  def delete(server, connection_id), do: GenServer.call(server, {:delete, connection_id})

  @impl Jido.Integration.Auth.ConnectionStore
  def list(server), do: GenServer.call(server, :list)

  @impl GenServer
  def init(_opts) do
    {:ok, %{table: :ets.new(:auth_connections_store, [:set, :private])}}
  end

  @impl GenServer
  def handle_call({:put, %Connection{} = connection}, _from, state) do
    :ets.insert(state.table, {connection.id, connection})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:fetch, connection_id}, _from, state) do
    result =
      case :ets.lookup(state.table, connection_id) do
        [{^connection_id, %Connection{} = connection}] -> {:ok, connection}
        [] -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:delete, connection_id}, _from, state) do
    case :ets.lookup(state.table, connection_id) do
      [{^connection_id, _connection}] ->
        :ets.delete(state.table, connection_id)
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call(:list, _from, state) do
    {:reply, state.table |> :ets.tab2list() |> Enum.map(&elem(&1, 1)), state}
  end
end
