# `Jido.Integration.V2.TriggerCheckpoint`

Durable checkpoint for polling-style trigger progression.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.TriggerCheckpoint{
  connector_id: binary(),
  cursor: binary(),
  last_event_id: nil | nil | binary(),
  last_event_time: nil | nil | any(),
  partition_key: binary(),
  revision: integer(),
  tenant_id: binary(),
  trigger_id: binary(),
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
