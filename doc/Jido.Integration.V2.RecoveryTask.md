# `Jido.Integration.V2.RecoveryTask`

Durable lower-truth recovery or reconciliation task.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.RecoveryTask{
  attempt_id: nil | nil | binary(),
  due_at: nil | nil | any(),
  inserted_at: nil | nil | any(),
  metadata: map(),
  reason: binary(),
  receipt_id: nil | nil | binary(),
  route_id: nil | nil | binary(),
  run_id: nil | nil | binary(),
  status: (:pending | :running | :resolved | :quarantined) | binary(),
  subject_ref: binary(),
  task_id: nil | nil | binary(),
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
