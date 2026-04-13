# `Jido.Integration.V2.WebhookRouter`

Hosted webhook route registry plus ingress and dispatch bridging.

# `ingress_definition`

```elixir
@type ingress_definition() :: struct()
```

# `route_error`

```elixir
@type route_error() ::
  :route_not_found
  | :missing_resolution_key
  | :tenant_not_found
  | :ambiguous_route
  | :dispatch_runtime_required
  | :invalid_secret
  | {:invalid_route, term()}
  | {:secret_resolution_failed, term()}
  | term()
```

# `webhook_result`

```elixir
@type webhook_result() ::
  {:ok,
   %{
     route: Jido.Integration.V2.WebhookRouter.Route.t(),
     definition: ingress_definition(),
     ingress: map(),
     dispatch_status: :accepted | :duplicate,
     dispatch: map(),
     trigger: map(),
     run: map()
   }}
  | {:error,
     %{
       reason: route_error(),
       route: Jido.Integration.V2.WebhookRouter.Route.t() | nil,
       trigger: map() | nil
     }}
```

# `build_definition`

```elixir
@spec build_definition(
  Jido.Integration.V2.WebhookRouter.Route.t(),
  keyword()
) :: {:ok, ingress_definition()} | {:error, route_error()}
```

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `fetch_route`

```elixir
@spec fetch_route(GenServer.server(), String.t()) ::
  {:ok, Jido.Integration.V2.WebhookRouter.Route.t()} | :error
```

# `list_routes`

```elixir
@spec list_routes(GenServer.server()) :: [Jido.Integration.V2.WebhookRouter.Route.t()]
```

# `register_route`

```elixir
@spec register_route(GenServer.server(), map()) ::
  {:ok, Jido.Integration.V2.WebhookRouter.Route.t()} | {:error, term()}
```

# `remove_route`

```elixir
@spec remove_route(GenServer.server(), String.t()) :: :ok | {:error, :not_found}
```

# `resolve_route`

```elixir
@spec resolve_route(GenServer.server(), map()) ::
  {:ok, Jido.Integration.V2.WebhookRouter.Route.t()}
  | {:error,
     :route_not_found
     | :missing_resolution_key
     | :tenant_not_found
     | :ambiguous_route}
```

# `route_webhook`

```elixir
@spec route_webhook(GenServer.server(), map(), keyword()) :: webhook_result()
```

# `start_link`

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
