# `Jido.Integration.V2.TriggerSpec`

Authored trigger contract for a connector manifest.

# `consumer_surface_mode`

```elixir
@type consumer_surface_mode() :: :common | :connector_local
```

# `delivery_mode`

```elixir
@type delivery_mode() :: :webhook | :poll
```

# `schema_policy_mode`

```elixir
@type schema_policy_mode() :: :defined | :dynamic | :passthrough
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.TriggerSpec{
  checkpoint: map(),
  config_schema: any(),
  consumer_surface: %{
    :mode =&gt; (:common | :connector_local) | binary(),
    optional(:normalized_id) =&gt; binary(),
    optional(:sensor_name) =&gt; binary(),
    optional(:reason) =&gt; binary()
  },
  dedupe: map(),
  delivery_mode: (:webhook | :poll) | binary(),
  description: nil | nil | binary(),
  display_name: nil | binary(),
  handler: atom(),
  jido: map(),
  metadata: map(),
  name: binary(),
  permissions: map(),
  policy: map(),
  polling:
    nil
    | nil
    | %{
        :default_interval_ms =&gt; integer(),
        optional(:min_interval_ms) =&gt; integer(),
        jitter: boolean()
      },
  runtime_class: (:direct | :session | :stream) | binary(),
  schema_policy: %{
    :config =&gt; (:defined | :dynamic | :passthrough) | binary(),
    :signal =&gt; (:defined | :dynamic | :passthrough) | binary(),
    optional(:justification) =&gt; binary()
  },
  secret_requirements: [binary()],
  signal_schema: any(),
  trigger_id: binary(),
  verification: map()
}
```

# `common_consumer_surface?`

```elixir
@spec common_consumer_surface?(t()) :: boolean()
```

# `connector_local_consumer_surface?`

```elixir
@spec connector_local_consumer_surface?(t()) :: boolean()
```

# `jido_sensor_name`

```elixir
@spec jido_sensor_name(t()) :: String.t() | nil
```

# `new`

```elixir
@spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, Exception.t()}
```

# `new!`

```elixir
@spec new!(map() | keyword() | t()) :: t()
```

# `normalized_surface_id`

```elixir
@spec normalized_surface_id(t()) :: String.t() | nil
```

# `polling`

```elixir
@spec polling(t()) :: map() | nil
```

# `polling_default_interval_ms`

```elixir
@spec polling_default_interval_ms(t()) :: pos_integer() | nil
```

# `polling_jitter?`

```elixir
@spec polling_jitter?(t()) :: boolean()
```

# `polling_min_interval_ms`

```elixir
@spec polling_min_interval_ms(t()) :: pos_integer() | nil
```

# `schema`

```elixir
@spec schema() :: Zoi.schema()
```

# `sensor_name`

```elixir
@spec sensor_name(t()) :: String.t() | nil
```

# `sensor_signal_source`

```elixir
@spec sensor_signal_source(t()) :: String.t() | nil
```

# `sensor_signal_type`

```elixir
@spec sensor_signal_type(t()) :: String.t() | nil
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
