# `Jido.Integration.V2.AuthSpec`

Authored auth contract for a connector manifest.

# `auth_type`

```elixir
@type auth_type() :: :oauth2 | :api_token | :session_token | :app_installation | :none
```

# `binding_kind`

```elixir
@type binding_kind() :: :connection_id | :tenant | :none
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.AuthSpec{
  auth_type:
    nil
    | nil
    | (:oauth2 | :api_token | :session_token | :app_installation | :none)
    | binary(),
  binding_kind: (:connection_id | :tenant | :none) | binary(),
  default_profile: nil | nil | binary(),
  durable_secret_fields: nil | nil | [binary()],
  install: map(),
  lease_fields: nil | nil | [binary()],
  management_modes: nil | nil | [atom()],
  metadata: map(),
  reauth: map(),
  requested_scopes: nil | nil | [binary()],
  secret_names: nil | nil | [binary()],
  supported_profiles: [map()]
}
```

# `default_profile`

```elixir
@spec default_profile(t()) :: map() | nil
```

# `fetch_profile`

```elixir
@spec fetch_profile(t(), String.t()) :: map() | nil
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
