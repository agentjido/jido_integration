# `Jido.Integration.V2.Auth.LeaseStore`

Durable credential-lease behaviour owned by `auth`.

# `fetch_lease`

```elixir
@callback fetch_lease(String.t()) ::
  {:ok, Jido.Integration.V2.Auth.LeaseRecord.t()} | {:error, :unknown_lease}
```

# `store_lease`

```elixir
@callback store_lease(Jido.Integration.V2.Auth.LeaseRecord.t()) :: :ok | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
