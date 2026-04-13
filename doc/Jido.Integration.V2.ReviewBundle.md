# `Jido.Integration.V2.ReviewBundle`

Operator-facing lower-truth review bundle usable by northbound surfaces.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.ReviewBundle{
  attempt: nil | nil | any(),
  bundle_id: nil | nil | binary(),
  metadata: map(),
  receipts: [any()],
  recovery_tasks: [any()],
  review_projection: any(),
  run: any()
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
