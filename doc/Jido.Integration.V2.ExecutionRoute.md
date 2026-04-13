# `Jido.Integration.V2.ExecutionRoute`

Durable lower-truth record for a committed execution route.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.ExecutionRoute{
  attempt_id: nil | nil | binary(),
  boundary_session_id: binary(),
  handoff_ref: nil | nil | binary(),
  inserted_at: nil | nil | any(),
  metadata: map(),
  route_id: nil | nil | binary(),
  route_kind: (:process | :http | :jsonrpc | :session) | binary(),
  run_id: binary(),
  status:
    (:committed_local
     | :accepted_downstream
     | :started_execution
     | :completed_execution
     | :quarantined
     | :dead_letter)
    | binary(),
  target_id: nil | nil | binary(),
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
