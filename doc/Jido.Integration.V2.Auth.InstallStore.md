# `Jido.Integration.V2.Auth.InstallStore`

Durable install-session behaviour owned by `auth`.

# `fetch_install`

```elixir
@callback fetch_install(String.t()) ::
  {:ok, Jido.Integration.V2.Auth.Install.t()} | {:error, :unknown_install}
```

# `list_installs`

```elixir
@callback list_installs(map()) :: [Jido.Integration.V2.Auth.Install.t()]
```

# `store_install`

```elixir
@callback store_install(Jido.Integration.V2.Auth.Install.t()) :: :ok | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
