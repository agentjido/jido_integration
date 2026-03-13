defmodule Jido.Integration.Webhook.RouteStore.ETS do
  @moduledoc """
  ETS-backed route store for explicit local development mode.
  """

  use GenServer

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
  def init(_opts) do
    {:ok, %{table: :ets.new(:webhook_route_store, [:set, :private])}}
  end

  @impl GenServer
  def handle_call({:put, %Route{} = route}, _from, state) do
    :ets.insert(state.table, {route_key(route), route})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:delete, install_id}, _from, state) do
    deleted? =
      state.table
      |> :ets.tab2list()
      |> Enum.reduce(false, fn {key, route}, acc ->
        if route.install_id == install_id do
          :ets.delete(state.table, key)
          true
        else
          acc
        end
      end)

    if deleted?, do: {:reply, :ok, state}, else: {:reply, {:error, :not_found}, state}
  end

  @impl GenServer
  def handle_call(:list, _from, state) do
    {:reply, state.table |> :ets.tab2list() |> Enum.map(&elem(&1, 1)), state}
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
