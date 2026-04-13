# `Jido.Integration.V2.ConsumerProjection.SensorProjection`

Projected metadata for a generated `Jido.Sensor` surface.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.ConsumerProjection.SensorProjection{
  auth_binding_kind: (:connection_id | :tenant | :none) | binary(),
  category: binary(),
  checkpoint: map(),
  config_schema: any(),
  connector_id: binary(),
  connector_module: atom(),
  delivery_mode: (:poll | :webhook) | binary(),
  description: binary(),
  jido_name: binary(),
  module: atom(),
  normalized_id: binary(),
  plugin_module: atom(),
  polling: map(),
  sensor_name: binary(),
  sensor_schema: any(),
  signal_schema: any(),
  signal_source: binary(),
  signal_type: binary(),
  tags: [binary()],
  trigger_id: binary()
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
