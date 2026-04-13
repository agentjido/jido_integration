# `Jido.Integration.V2.CredentialLease`

Short-lived execution material derived from a durable `CredentialRef`.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.CredentialLease{
  connection_id: nil | nil | binary(),
  credential_id: nil | nil | binary(),
  credential_ref_id: binary(),
  expires_at: any(),
  issued_at: nil | nil | any(),
  lease_fields: nil | nil | [binary()],
  lease_id: binary(),
  metadata: map(),
  payload: map(),
  profile_id: nil | nil | binary(),
  scopes: [binary()],
  subject: binary()
}
```

# `expired?`

```elixir
@spec expired?(t(), DateTime.t()) :: boolean()
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
