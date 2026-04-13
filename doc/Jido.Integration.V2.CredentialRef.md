# `Jido.Integration.V2.CredentialRef`

Opaque control-plane-owned credential handle.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.CredentialRef{
  connection_id: nil | nil | binary(),
  current_credential_id: nil | nil | binary(),
  id: binary(),
  lease_fields: [binary()],
  metadata: map(),
  profile_id: nil | nil | binary(),
  scopes: [binary()],
  subject: binary()
}
```

# `new`

```elixir
@spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
```

# `new!`

```elixir
@spec new!(map() | keyword() | t()) :: t()
```

# `schema`

```elixir
@spec schema() :: Zoi.schema()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
