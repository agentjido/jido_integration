# `Jido.Integration.V2.Auth.ConnectionStore`

Durable connection-truth behaviour owned by `auth`.

# `fetch_connection`

```elixir
@callback fetch_connection(String.t()) ::
  {:ok, Jido.Integration.V2.Auth.Connection.t()} | {:error, :unknown_connection}
```

# `list_connections`

```elixir
@callback list_connections(map()) :: [Jido.Integration.V2.Auth.Connection.t()]
```

# `store_connection`

```elixir
@callback store_connection(Jido.Integration.V2.Auth.Connection.t()) ::
  :ok | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
