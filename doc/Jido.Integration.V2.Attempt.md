# `Jido.Integration.V2.Attempt`

One concrete execution attempt of a run.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.Attempt{
  aggregator_epoch: integer(),
  aggregator_id: binary(),
  attempt: integer(),
  attempt_id: nil | nil | binary(),
  credential_lease_id: nil | nil | binary(),
  inserted_at: nil | nil | any(),
  output: nil | nil | map(),
  run_id: binary(),
  runtime_class: (:direct | :session | :stream) | binary(),
  runtime_ref_id: nil | nil | binary(),
  status: (:accepted | :running | :completed | :failed) | binary(),
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
