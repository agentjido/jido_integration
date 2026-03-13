defmodule Jido.Integration.Webhook.RouteStore.Disk do
  @moduledoc """
  File-backed route store for durable local runtime state.
  """

  use GenServer

  alias Jido.Integration.Runtime.Persistence
  alias Jido.Integration.Webhook.Route

  @behaviour Jido.Integration.Webhook.RouteStore

  @impl true
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, nil} -> GenServer.start_link(__MODULE__, opts)
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  @impl Jido.Integration.Webhook.RouteStore
  def put(server, %Route{} = route), do: GenServer.call(server, {:put, route})

  @impl Jido.Integration.Webhook.RouteStore
  def delete(server, install_id), do: GenServer.call(server, {:delete, install_id})

  @impl Jido.Integration.Webhook.RouteStore
  def list(server), do: GenServer.call(server, :list)

  @impl GenServer
  def init(opts) do
    path = Persistence.default_path("routes", opts)
    {:ok, %{path: path, entries: Persistence.load(path, %{})}}
  end

  @impl GenServer
  def handle_call({:put, %Route{} = route}, _from, state) do
    entries = Map.put(state.entries, route_key(route), route)
    :ok = Persistence.persist(state.path, entries)
    {:reply, :ok, %{state | entries: entries}}
  end

  @impl GenServer
  def handle_call({:delete, install_id}, _from, state) do
    matching_keys =
      Enum.flat_map(state.entries, fn {key, route} ->
        if route.install_id == install_id, do: [key], else: []
      end)

    if matching_keys == [] do
      {:reply, {:error, :not_found}, state}
    else
      entries = Map.drop(state.entries, matching_keys)
      :ok = Persistence.persist(state.path, entries)
      {:reply, :ok, %{state | entries: entries}}
    end
  end

  @impl GenServer
  def handle_call(:list, _from, state) do
    {:reply, Map.values(state.entries), state}
  end

  defp route_key(%Route{} = route) do
    if is_binary(route.install_id) do
      "install:" <> route.install_id
    else
      Enum.join(
        [
          "static",
          route.connector_id,
          route.tenant_id || "",
          route.connection_id || "",
          route.trigger_id || ""
        ],
        "|"
      )
    end
  end
end
