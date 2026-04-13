# `Jido.Integration.V2.TriggerRecord`

Durable trigger admission or rejection record owned by the control plane.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.TriggerRecord{
  admission_id: nil | nil | binary(),
  capability_id: binary(),
  connector_id: binary(),
  dedupe_key: binary(),
  external_id: nil | nil | binary(),
  inserted_at: nil | nil | any(),
  partition_key: nil | nil | binary(),
  payload: map(),
  rejection_reason: nil | nil | any(),
  run_id: nil | nil | binary(),
  signal: map(),
  source: (:webhook | :poll) | binary(),
  status: (:accepted | :rejected) | binary(),
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
