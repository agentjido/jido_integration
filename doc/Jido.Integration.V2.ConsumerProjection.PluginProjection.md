# `Jido.Integration.V2.ConsumerProjection.PluginProjection`

Projected metadata for a generated `Jido.Plugin` bundle.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.ConsumerProjection.PluginProjection{
  actions: [atom()],
  category: binary(),
  config_schema: any(),
  connector_module: atom(),
  description: binary(),
  module: atom(),
  name: binary(),
  state_key: atom() | binary(),
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
