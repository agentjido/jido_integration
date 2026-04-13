# `Jido.Integration.V2.LeaseRef`

Durable reference to a reusable runtime lease or endpoint instance.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.LeaseRef{
  contract_version: binary(),
  lease_ref: binary(),
  metadata: map(),
  owner_ref: nil | nil | binary(),
  renewable?: boolean(),
  ttl_ms: nil | nil | integer()
}
```

# `dump`

```elixir
@spec dump(t()) :: map()
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
