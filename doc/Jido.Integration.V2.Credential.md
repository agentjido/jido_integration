# `Jido.Integration.V2.Credential`

Resolved credential owned by the control plane.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.Credential{
  auth_type: atom(),
  connection_id: nil | nil | binary(),
  credential_ref_id: nil | nil | binary(),
  expires_at: nil | nil | any(),
  id: binary(),
  lease_fields: nil | nil | [binary()],
  metadata: map(),
  profile_id: nil | nil | binary(),
  refresh_token_expires_at: nil | nil | any(),
  revoked_at: nil | nil | any(),
  scopes: [binary()],
  secret: map(),
  source: nil | nil | atom(),
  source_ref: nil | nil | map(),
  subject: binary(),
  supersedes_credential_id: nil | nil | binary(),
  version: integer()
}
```

# `active?`

```elixir
@spec active?(t(), DateTime.t()) :: boolean()
```

# `expired?`

```elixir
@spec expired?(t(), DateTime.t()) :: boolean()
```

# `lease_payload`

```elixir
@spec lease_payload(t(), [String.t()] | nil) :: map()
```

# `new`

```elixir
@spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
```

# `new!`

```elixir
@spec new!(map() | keyword() | t()) :: t()
```

# `now`

```elixir
@spec now() :: DateTime.t()
```

# `sanitized`

```elixir
@spec sanitized(t()) :: t()
```

# `schema`

```elixir
@spec schema() :: Zoi.schema()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
