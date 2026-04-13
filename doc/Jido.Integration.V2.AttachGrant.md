# `Jido.Integration.V2.AttachGrant`

Durable lower-truth grant allowing a route or consumer to attach to a boundary session.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.AttachGrant{
  attach_grant_id: nil | nil | binary(),
  boundary_session_id: binary(),
  inserted_at: nil | nil | any(),
  lease_expires_at: nil | nil | any(),
  metadata: map(),
  route_id: nil | nil | binary(),
  status: (:issued | :accepted | :revoked | :expired) | binary(),
  subject_id: nil | nil | binary(),
  updated_at: nil | nil | any()
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
