# `Jido.Integration.V2.Event`

Canonical append-only event for run and attempt observation.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.Event{
  attempt: nil | nil | integer(),
  attempt_id: nil | nil | binary(),
  event_id: nil | nil | binary(),
  level: (:debug | :info | :warn | :error) | binary(),
  payload: map(),
  payload_ref: nil | nil | any(),
  run_id: binary(),
  runtime_ref_id: nil | nil | binary(),
  schema_version: binary(),
  seq: integer(),
  session_id: nil | nil | binary(),
  stream: (:assistant | :stdout | :stderr | :system | :control) | binary(),
  target_id: nil | nil | binary(),
  trace: map(),
  ts: nil | nil | any(),
  type: binary()
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
