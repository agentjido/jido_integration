# `Jido.Integration.V2.ConsumerProjection.ActionProjection`

Projected metadata for a generated `Jido.Action` surface.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.ConsumerProjection.ActionProjection{
  action_name: binary(),
  category: binary(),
  connector_module: atom(),
  description: binary(),
  module: atom(),
  normalized_id: binary(),
  operation_id: binary(),
  output_schema: any(),
  plugin_module: atom(),
  schema: any(),
  tags: [binary()]
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
