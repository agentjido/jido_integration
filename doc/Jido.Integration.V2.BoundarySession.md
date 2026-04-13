# `Jido.Integration.V2.BoundarySession`

Durable lower-truth record for one boundary session lineage.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.BoundarySession{
  attach_grant_id: nil | nil | binary(),
  boundary_session_id: nil | nil | binary(),
  inserted_at: nil | nil | any(),
  metadata: map(),
  route_id: nil | nil | binary(),
  session_id: nil | nil | binary(),
  status: (:allocated | :attaching | :attached | :stale | :closed) | binary(),
  target_id: nil | nil | binary(),
  tenant_id: nil | nil | binary(),
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
