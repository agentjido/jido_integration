# `Jido.Integration.V2.Run`

Durable record of requested work.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.Run{
  artifact_refs: [any()],
  capability_id: binary(),
  credential_ref: any(),
  input: map(),
  inserted_at: nil | nil | any(),
  result: nil | nil | map(),
  run_id: nil | nil | binary(),
  runtime_class: (:direct | :session | :stream) | binary(),
  status:
    (:accepted | :running | :completed | :failed | :denied | :shed) | binary(),
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
