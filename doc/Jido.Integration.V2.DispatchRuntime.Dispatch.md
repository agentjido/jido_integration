# `Jido.Integration.V2.DispatchRuntime.Dispatch`

Durable transport-state record for async trigger execution.

# `status`

```elixir
@type status() :: :queued | :running | :retry_scheduled | :completed | :dead_lettered
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.DispatchRuntime.Dispatch{
  attempts: non_neg_integer(),
  available_at: DateTime.t() | nil,
  checkpoint: Jido.Integration.V2.TriggerCheckpoint.t() | nil,
  completed_at: DateTime.t() | nil,
  dead_lettered_at: DateTime.t() | nil,
  dispatch_id: String.t(),
  inserted_at: DateTime.t(),
  last_error: map() | nil,
  max_attempts: pos_integer(),
  run_id: String.t() | nil,
  status: status(),
  trigger: Jido.Integration.V2.TriggerRecord.t(),
  updated_at: DateTime.t()
}
```

# `new!`

```elixir
@spec new!(map()) :: t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
