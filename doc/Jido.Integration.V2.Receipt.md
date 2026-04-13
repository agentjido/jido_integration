# `Jido.Integration.V2.Receipt`

Durable lower-truth acknowledgement or completion receipt.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.Receipt{
  attempt_id: nil | nil | binary(),
  inserted_at: nil | nil | any(),
  metadata: map(),
  observed_at: nil | nil | any(),
  receipt_id: nil | nil | binary(),
  receipt_kind: (:handoff | :execution | :publication) | binary(),
  route_id: nil | nil | binary(),
  run_id: binary(),
  status: (:accepted | :completed | :rejected | :ambiguous) | binary()
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
