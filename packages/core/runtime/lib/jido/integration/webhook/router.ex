defmodule Jido.Integration.Webhook.Router do
  @moduledoc """
  Webhook route registry — maps inbound webhook paths to connector + tenant.

  Supports two callback topologies:

  - `:dynamic_per_install` — unique URL per installation, keyed by install_id
  - `:static_per_app` — single URL for all tenants, resolved from payload fields
  """

  use GenServer

  alias Jido.Integration.Webhook.{Route, RouteStore}

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Register a webhook route."
  @spec register_route(GenServer.server(), map()) :: :ok
  def register_route(server, route) when is_map(route) do
    GenServer.call(server, {:register_route, route})
  end

  @doc """
  Resolve an inbound webhook to its route.

  For dynamic_per_install: pass `%{install_id: id}`.
  For static_per_app: pass `%{connector_id: id}`.
  """
  @spec resolve(GenServer.server(), map()) :: {:ok, map()} | {:error, :route_not_found}
  def resolve(server, lookup) do
    GenServer.call(server, {:resolve, lookup})
  end

  @doc "Remove a route by install_id."
  @spec unregister_route(GenServer.server(), String.t()) :: :ok
  def unregister_route(server, install_id) do
    GenServer.call(server, {:unregister_route, install_id})
  end

  @doc "List all registered routes."
  @spec list_routes(GenServer.server()) :: [map()]
  def list_routes(server) do
    GenServer.call(server, :list_routes)
  end

  # Server

  @impl GenServer
  def init(opts) do
    store_module = Keyword.get(opts, :store_module, RouteStore.Disk)

    {:ok, store} =
      store_module.start_link(Keyword.put_new(Keyword.get(opts, :store_opts, []), :name, nil))

    {:ok, %{store_module: store_module, store: store}}
  end

  @impl GenServer
  def handle_call({:register_route, route}, _from, state) do
    route = Route.new!(route)
    :ok = state.store_module.put(state.store, route)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:resolve, %{install_id: install_id}}, _from, state) do
    result =
      case route_indexes(state).routes_by_install[install_id] do
        %Route{} = route ->
          if Route.active?(route), do: {:ok, route}, else: {:error, :route_not_found}

        nil ->
          {:error, :route_not_found}
      end

    {:reply, result, state}
  end

  def handle_call({:resolve, %{connector_id: connector_id} = lookup}, _from, state) do
    result =
      route_indexes(state)
      |> Map.fetch!(:routes_by_connector)
      |> Map.get(connector_id, [])
      |> resolve_static_routes(lookup)

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:resolve, _}, _from, state) do
    {:reply, {:error, :route_not_found}, state}
  end

  @impl GenServer
  def handle_call({:unregister_route, install_id}, _from, state) do
    {:reply, state.store_module.delete(state.store, install_id), state}
  end

  @impl GenServer
  def handle_call(:list_routes, _from, state) do
    {:reply, state.store_module.list(state.store), state}
  end

  defp route_indexes(state) do
    Enum.reduce(
      state.store_module.list(state.store),
      %{routes_by_install: %{}, routes_by_connector: %{}},
      fn route, acc ->
        case route.callback_topology do
          :dynamic_per_install ->
            put_in(acc.routes_by_install[route.install_id], route)

          :static_per_app ->
            connector_routes =
              acc.routes_by_connector
              |> Map.get(route.connector_id, [])
              |> upsert_static_route(route)

            put_in(acc.routes_by_connector[route.connector_id], connector_routes)
        end
      end
    )
  end

  defp upsert_static_route(routes, %Route{} = route) do
    Enum.reject(routes, &same_static_route?(&1, route)) ++ [route]
  end

  defp same_static_route?(left, right) do
    left.connector_id == right.connector_id and
      left.tenant_id == right.tenant_id and
      left.connection_id == right.connection_id and
      left.install_id == right.install_id
  end

  defp resolve_static_routes([], _lookup), do: {:error, :route_not_found}

  defp resolve_static_routes(routes, lookup) do
    active_routes = Enum.filter(routes, &Route.active?/1)

    case maybe_match_static_routes(active_routes, lookup) do
      {:ok, route} ->
        {:ok, route}

      {:error, _} = error ->
        error
    end
  end

  defp maybe_match_static_routes([route], lookup) do
    case required_resolution_keys(route) do
      [] ->
        {:ok, route}

      _keys ->
        if static_route_matches?(route, lookup) do
          {:ok, route}
        else
          missing_or_not_found(route, lookup)
        end
    end
  end

  defp maybe_match_static_routes(routes, lookup) do
    case Enum.filter(routes, &static_route_matches?(&1, lookup)) do
      [] ->
        unmatched_static_route_error(routes, lookup)

      [route] ->
        {:ok, route}

      _matches ->
        {:error, :ambiguous_route}
    end
  end

  defp required_resolution_keys(%Route{tenant_resolution_keys: keys}), do: keys

  defp static_route_matches?(%Route{} = route, lookup) do
    resolution = route.tenant_resolution || %{}

    Enum.all?(resolution, fn {key, expected} ->
      match?({:ok, ^expected}, fetch_lookup_value(lookup, key))
    end)
  end

  defp missing_required_resolution?(%Route{} = route, lookup) do
    Enum.any?(required_resolution_keys(route), fn key ->
      match?({:error, :missing_resolution_key}, fetch_lookup_value(lookup, key))
    end)
  end

  defp missing_or_not_found(route, lookup) do
    if missing_required_resolution?(route, lookup) do
      {:error, :missing_resolution_key}
    else
      {:error, :tenant_not_found}
    end
  end

  defp unmatched_static_route_error(routes, lookup) do
    if Enum.any?(routes, &(required_resolution_keys(&1) != [])) do
      case Enum.find(routes, &missing_required_resolution?(&1, lookup)) do
        nil -> {:error, :tenant_not_found}
        _route -> {:error, :missing_resolution_key}
      end
    else
      {:error, :route_not_found}
    end
  end

  defp fetch_lookup_value(lookup, key) do
    request = Map.get(lookup, :request, %{})

    case lookup_path_value(request, key) do
      nil -> {:error, :missing_resolution_key}
      value -> {:ok, value}
    end
  end

  defp lookup_path_value(source, path) when is_binary(path) do
    segments = String.split(path, ".")

    Enum.reduce_while(segments, source, fn segment, acc ->
      value =
        cond do
          is_map(acc) and Map.has_key?(acc, segment) ->
            Map.get(acc, segment)

          is_map(acc) ->
            fetch_existing_atom_key(acc, segment)

          true ->
            nil
        end

      if is_nil(value), do: {:halt, nil}, else: {:cont, value}
    end)
  end

  defp fetch_existing_atom_key(map, key) do
    atom_key =
      try do
        String.to_existing_atom(key)
      rescue
        ArgumentError -> nil
      end

    if atom_key && Map.has_key?(map, atom_key), do: Map.get(map, atom_key), else: nil
  end
end
