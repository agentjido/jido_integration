defmodule Jido.Integration.V2.WebhookRouter do
  @moduledoc """
  Hosted webhook route registry plus ingress and dispatch bridging.
  """

  use GenServer

  alias Jido.Integration.V2.Auth
  alias Jido.Integration.V2.Contracts
  alias Jido.Integration.V2.DispatchRuntime
  alias Jido.Integration.V2.Ingress
  alias Jido.Integration.V2.Ingress.Definition
  alias Jido.Integration.V2.WebhookRouter.Route

  @default_storage_dir Path.join(System.tmp_dir!(), "jido_integration_v2_webhook_router")
  @state_file "routes.bin"

  @type route_error ::
          :route_not_found
          | :missing_resolution_key
          | :tenant_not_found
          | :ambiguous_route
          | :dispatch_runtime_required
          | :invalid_secret
          | {:invalid_route, term()}
          | {:secret_resolution_failed, term()}
          | term()

  @type webhook_result ::
          {:ok,
           %{
             route: Route.t(),
             definition: Definition.t(),
             ingress: map(),
             dispatch_status: :accepted | :duplicate,
             dispatch: map(),
             trigger: map(),
             run: map()
           }}
          | {:error, %{reason: route_error(), route: Route.t() | nil, trigger: map() | nil}}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    GenServer.start_link(
      __MODULE__,
      opts,
      if(name, do: [name: name], else: [])
    )
  end

  @spec register_route(GenServer.server(), map()) :: {:ok, Route.t()} | {:error, term()}
  def register_route(server, attrs) when is_map(attrs) do
    GenServer.call(server, {:register_route, attrs}, :infinity)
  end

  @spec fetch_route(GenServer.server(), String.t()) :: {:ok, Route.t()} | :error
  def fetch_route(server, route_id) do
    GenServer.call(server, {:fetch_route, route_id})
  end

  @spec list_routes(GenServer.server()) :: [Route.t()]
  def list_routes(server) do
    GenServer.call(server, :list_routes)
  end

  @spec remove_route(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
  def remove_route(server, route_id) do
    GenServer.call(server, {:remove_route, route_id}, :infinity)
  end

  @spec resolve_route(GenServer.server(), map()) ::
          {:ok, Route.t()}
          | {:error,
             :route_not_found | :missing_resolution_key | :tenant_not_found | :ambiguous_route}
  def resolve_route(server, lookup) when is_map(lookup) do
    GenServer.call(server, {:resolve_route, lookup})
  end

  @spec build_definition(Route.t(), keyword()) :: {:ok, Definition.t()} | {:error, route_error()}
  def build_definition(%Route{} = route, opts \\ []) do
    with {:ok, verification} <- build_verification(route, opts) do
      {:ok,
       Definition.new!(%{
         source: :webhook,
         connector_id: route.connector_id,
         trigger_id: route.trigger_id,
         capability_id: route.capability_id,
         signal_type: route.signal_type,
         signal_source: route.signal_source,
         validator: build_validator(route.validator),
         verification: verification,
         dedupe_ttl_seconds: route.dedupe_ttl_seconds
       })}
    end
  rescue
    error in [ArgumentError, KeyError] ->
      {:error, {:invalid_route, Exception.message(error)}}
  end

  @spec route_webhook(GenServer.server(), map(), keyword()) :: webhook_result()
  def route_webhook(server, request, opts \\ []) when is_map(request) do
    case resolve_route(server, lookup_from_request(request)) do
      {:ok, %Route{} = route} ->
        do_route_webhook(route, request, opts)

      {:error, reason} ->
        {:error, %{reason: reason, route: nil, trigger: nil}}
    end
  end

  @impl true
  def init(opts) do
    storage_path = storage_path(opts)
    File.mkdir_p!(Path.dirname(storage_path))

    routes = load_routes(storage_path)

    {:ok,
     %{
       storage_path: storage_path,
       routes: routes,
       install_index: build_install_index(routes),
       connector_index: build_connector_index(routes)
     }}
  end

  @impl true
  def handle_call({:register_route, attrs}, _from, state) do
    route =
      attrs
      |> Route.new!()
      |> merge_existing_route(state.routes)

    state =
      state
      |> put_routes(Map.put(state.routes, route.route_id, route))
      |> persist_routes()

    {:reply, {:ok, route}, state}
  rescue
    error in [ArgumentError, KeyError] ->
      {:reply, {:error, {:invalid_route, Exception.message(error)}}, state}
  end

  def handle_call({:fetch_route, route_id}, _from, state) do
    reply =
      case Map.fetch(state.routes, route_id) do
        {:ok, %Route{} = route} -> {:ok, route}
        :error -> :error
      end

    {:reply, reply, state}
  end

  def handle_call(:list_routes, _from, state) do
    {:reply, sort_routes(Map.values(state.routes)), state}
  end

  def handle_call({:remove_route, route_id}, _from, state) do
    if Map.has_key?(state.routes, route_id) do
      state =
        state
        |> put_routes(Map.delete(state.routes, route_id))
        |> persist_routes()

      {:reply, :ok, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:resolve_route, %{install_id: install_id}}, _from, state) do
    reply =
      case Map.get(state.install_index, install_id) do
        nil ->
          {:error, :route_not_found}

        route_id ->
          case Map.fetch(state.routes, route_id) do
            {:ok, %Route{} = route} ->
              if Route.active?(route), do: {:ok, route}, else: {:error, :route_not_found}

            _ ->
              {:error, :route_not_found}
          end
      end

    {:reply, reply, state}
  end

  def handle_call({:resolve_route, %{connector_id: connector_id} = lookup}, _from, state) do
    routes =
      connector_id
      |> then(&Map.get(state.connector_index, &1, []))
      |> Enum.map(&Map.fetch!(state.routes, &1))
      |> Enum.filter(&(Route.active?(&1) and &1.callback_topology == :static_per_app))

    {:reply, resolve_static_routes(routes, lookup), state}
  end

  def handle_call({:resolve_route, _lookup}, _from, state) do
    {:reply, {:error, :route_not_found}, state}
  end

  defp merge_existing_route(%Route{} = route, routes) do
    identity_key = Route.identity_key(route)
    route_id = route.route_id

    existing_route =
      Enum.find_value(routes, fn
        {_existing_id, %Route{} = existing} ->
          if existing.route_id == route_id or Route.identity_key(existing) == identity_key do
            existing
          end

        _ ->
          nil
      end)

    case existing_route do
      nil ->
        route

      %Route{} = existing ->
        %Route{
          route
          | route_id: existing.route_id,
            revision: existing.revision + 1,
            inserted_at: existing.inserted_at,
            updated_at: Contracts.now()
        }
    end
  end

  defp put_routes(state, routes) do
    %{
      state
      | routes: routes,
        install_index: build_install_index(routes),
        connector_index: build_connector_index(routes)
    }
  end

  defp sort_routes(routes) do
    Enum.sort_by(routes, fn route ->
      {
        route.connector_id,
        route.callback_topology,
        route.tenant_id || "",
        route.install_id || "",
        route.route_id
      }
    end)
  end

  defp resolve_static_routes([], _lookup), do: {:error, :route_not_found}

  defp resolve_static_routes(routes, lookup) do
    case Enum.filter(routes, &static_route_matches?(&1, lookup)) do
      [] ->
        unmatched_static_route_error(routes, lookup)

      [route] ->
        {:ok, route}

      _routes ->
        {:error, :ambiguous_route}
    end
  end

  defp static_route_matches?(%Route{} = route, lookup) do
    resolution = route.tenant_resolution || %{}

    if resolution == %{} do
      true
    else
      Enum.all?(resolution, fn {key, expected} ->
        match?({:ok, ^expected}, fetch_lookup_value(lookup, key))
      end)
    end
  end

  defp unmatched_static_route_error(routes, lookup) do
    if Enum.any?(routes, &missing_required_resolution?(&1, lookup)) do
      {:error, :missing_resolution_key}
    else
      {:error, :tenant_not_found}
    end
  end

  defp missing_required_resolution?(%Route{} = route, lookup) do
    Enum.any?(route.tenant_resolution_keys, fn key ->
      match?({:error, :missing_resolution_key}, fetch_lookup_value(lookup, key))
    end)
  end

  defp fetch_lookup_value(lookup, key) do
    request = Map.get(lookup, :request, %{})

    case lookup_path_value(request, key) do
      nil -> {:error, :missing_resolution_key}
      value -> {:ok, value}
    end
  end

  defp lookup_path_value(source, path) when is_binary(path) do
    path
    |> String.split(".")
    |> Enum.reduce_while(source, fn segment, acc ->
      case fetch_path_segment(acc, segment) do
        nil -> {:halt, nil}
        value -> {:cont, value}
      end
    end)
  end

  defp fetch_path_segment(source, segment) when is_map(source) do
    case Map.fetch(source, segment) do
      {:ok, value} ->
        value

      :error ->
        atom_key =
          try do
            String.to_existing_atom(segment)
          rescue
            ArgumentError -> nil
          end

        if atom_key && Map.has_key?(source, atom_key), do: Map.get(source, atom_key), else: nil
    end
  end

  defp fetch_path_segment(_source, _segment), do: nil

  defp build_verification(%Route{verification: nil}, _opts), do: {:ok, nil}

  defp build_verification(%Route{verification: verification}, opts) do
    with {:ok, secret} <- resolve_secret(verification, opts),
         :ok <- validate_secret(secret) do
      {:ok,
       %{
         algorithm: Map.get(verification, :algorithm, :sha256),
         secret: secret,
         signature_header: Map.fetch!(verification, :signature_header)
       }}
    end
  end

  defp build_validator(nil), do: nil
  defp build_validator({module, function}), do: &apply(module, function, [&1])

  defp resolve_secret(%{secret: secret}, _opts) when is_binary(secret), do: {:ok, secret}

  defp resolve_secret(
         %{secret_ref: %{credential_ref: credential_ref, secret_key: secret_key}},
         opts
       ) do
    case auth_module(opts).resolve_secret(credential_ref, secret_key) do
      {:ok, secret} -> {:ok, secret}
      {:error, reason} -> {:error, {:secret_resolution_failed, reason}}
    end
  end

  defp validate_secret(secret) when is_binary(secret), do: :ok
  defp validate_secret(_secret), do: {:error, :invalid_secret}

  defp fetch_dispatch_runtime(opts) do
    case Keyword.get(opts, :dispatch_runtime) do
      nil -> {:error, :dispatch_runtime_required}
      runtime -> {:ok, runtime}
    end
  end

  defp do_route_webhook(%Route{} = route, request, opts) do
    with {:ok, definition} <- build_definition(route, opts),
         {:ok, dispatch_runtime} <- fetch_dispatch_runtime(opts),
         ingress_request <- enrich_request(request, route),
         {:ok, ingress_result} <- ingress_module(opts).admit_webhook(ingress_request, definition),
         {:ok, dispatch_result} <-
           dispatch_runtime_module(opts).enqueue(
             dispatch_runtime,
             ingress_result.trigger,
             Keyword.get(opts, :dispatch_opts, [])
           ) do
      {:ok,
       %{
         route: route,
         definition: definition,
         ingress: ingress_result,
         dispatch_status: dispatch_result.status,
         dispatch: dispatch_result.dispatch,
         trigger: dispatch_result.dispatch.trigger,
         run: dispatch_result.run
       }}
    else
      {:error, %{} = ingress_error} ->
        {:error,
         %{
           reason: Map.fetch!(ingress_error, :reason),
           route: route,
           trigger: Map.get(ingress_error, :trigger)
         }}

      {:error, reason} ->
        {:error, %{reason: reason, route: route, trigger: nil}}
    end
  end

  defp enrich_request(request, %Route{} = route) do
    request
    |> Map.put_new(:tenant_id, route.tenant_id)
    |> Map.put_new(:connector_id, route.connector_id)
    |> Map.put_new(:connection_id, route.connection_id)
    |> Map.put_new(:install_id, route.install_id)
    |> maybe_put_external_id(route)
  end

  defp maybe_put_external_id(request, %Route{} = route) do
    case Map.get(request, :external_id) do
      external_id when is_binary(external_id) ->
        if byte_size(String.trim(external_id)) > 0 do
          request
        else
          put_delivery_external_id(request, route)
        end

      _ ->
        put_delivery_external_id(request, route)
    end
  end

  defp put_delivery_external_id(request, %Route{} = route) do
    case delivery_id(request, route.delivery_id_headers) do
      nil -> request
      external_id -> Map.put(request, :external_id, external_id)
    end
  end

  defp delivery_id(request, headers) do
    request_headers = Map.get(request, :headers, %{})

    Enum.find_value(headers, fn header ->
      get_header(request_headers, header)
    end)
  end

  defp get_header(headers, key) when is_map(headers) do
    Map.get(headers, key) || Map.get(headers, String.downcase(key))
  end

  defp get_header(_headers, _key), do: nil

  defp lookup_from_request(request) do
    cond do
      match?(install_id when is_binary(install_id), Map.get(request, :install_id)) ->
        %{install_id: Map.fetch!(request, :install_id), request: request}

      match?(connector_id when is_binary(connector_id), Map.get(request, :connector_id)) ->
        %{connector_id: Map.fetch!(request, :connector_id), request: request}

      true ->
        %{}
    end
  end

  defp auth_module(opts), do: Keyword.get(opts, :auth_module, Auth)
  defp ingress_module(opts), do: Keyword.get(opts, :ingress_module, Ingress)

  defp dispatch_runtime_module(opts),
    do: Keyword.get(opts, :dispatch_runtime_module, DispatchRuntime)

  defp build_install_index(routes) do
    Enum.reduce(routes, %{}, fn
      {_route_id, %Route{callback_topology: :dynamic_per_install, install_id: install_id} = route},
      acc
      when is_binary(install_id) ->
        Map.put(acc, install_id, route.route_id)

      _, acc ->
        acc
    end)
  end

  defp build_connector_index(routes) do
    Enum.reduce(routes, %{}, fn {_route_id, %Route{} = route}, acc ->
      Map.update(acc, route.connector_id, [route.route_id], &[route.route_id | &1])
    end)
  end

  defp persist_routes(%{storage_path: storage_path, routes: routes} = state) do
    tmp_path = "#{storage_path}.tmp"
    File.write!(tmp_path, :erlang.term_to_binary(routes), [:binary])

    case File.rename(tmp_path, storage_path) do
      :ok ->
        state

      {:error, _reason} ->
        File.rm(storage_path)
        File.rename!(tmp_path, storage_path)
        state
    end
  end

  defp storage_path(opts) do
    storage_dir = Keyword.get(opts, :storage_dir, @default_storage_dir)
    Path.join(storage_dir, @state_file)
  end

  defp load_routes(path) do
    case File.read(path) do
      {:ok, binary} ->
        :erlang.binary_to_term(binary, [:safe])

      {:error, :enoent} ->
        %{}

      {:error, reason} ->
        raise "unable to load webhook router state from #{path}: #{inspect(reason)}"
    end
  end
end
