# `Jido.Integration.V2.Auth.CredentialStore`

Durable credential-truth behaviour owned by `auth`.

# `fetch_credential`

```elixir
@callback fetch_credential(String.t()) ::
  {:ok, Jido.Integration.V2.Credential.t()} | {:error, :unknown_credential}
```

# `store_credential`

```elixir
@callback store_credential(Jido.Integration.V2.Credential.t()) :: :ok | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
