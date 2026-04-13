# `Jido.Integration.V2.ConsumerProjection`

Shared projection rules for generated consumer surfaces built from authored
manifests.

Only authored entries marked `consumer_surface.mode == :common` project into
generated actions, sensors, and plugins. Connector-local inventory remains
authored runtime truth, but it stays outside the shared generated consumer
surface until a connector author explicitly opts it in.

# `action_module`

```elixir
@spec action_module(module(), String.t() | Jido.Integration.V2.OperationSpec.t()) ::
  module()
```

# `action_modules`

```elixir
@spec action_modules(module()) :: [module()]
```

# `action_opts`

```elixir
@spec action_opts(Jido.Integration.V2.ConsumerProjection.ActionProjection.t()) ::
  keyword()
```

# `action_projection!`

```elixir
@spec action_projection!(module(), String.t()) ::
  Jido.Integration.V2.ConsumerProjection.ActionProjection.t()
```

# `filtered_actions!`

```elixir
@spec filtered_actions!(
  Jido.Integration.V2.ConsumerProjection.PluginProjection.t(),
  map()
) :: [
  module()
]
```

# `handle_sensor_event`

```elixir
@spec handle_sensor_event(
  Jido.Integration.V2.ConsumerProjection.SensorProjection.t(),
  term(),
  map()
) ::
  {:ok, map()} | {:ok, map(), [{:emit, Jido.Signal.t()}]}
```

# `init_sensor`

```elixir
@spec init_sensor(
  Jido.Integration.V2.ConsumerProjection.SensorProjection.t(),
  map(),
  map()
) ::
  {:ok, map()}
```

# `plugin_module`

```elixir
@spec plugin_module(module()) :: module()
```

# `plugin_opts`

```elixir
@spec plugin_opts(Jido.Integration.V2.ConsumerProjection.PluginProjection.t()) ::
  keyword()
```

# `plugin_projection!`

```elixir
@spec plugin_projection!(module()) ::
  Jido.Integration.V2.ConsumerProjection.PluginProjection.t()
```

# `plugin_subscriptions`

```elixir
@spec plugin_subscriptions(
  Jido.Integration.V2.ConsumerProjection.PluginProjection.t()
) :: [
  {module(), map()}
]
```

# `projected_operations`

```elixir
@spec projected_operations(Jido.Integration.V2.Manifest.t()) :: [
  Jido.Integration.V2.OperationSpec.t()
]
```

# `projected_triggers`

```elixir
@spec projected_triggers(Jido.Integration.V2.Manifest.t()) :: [
  Jido.Integration.V2.TriggerSpec.t()
]
```

# `run_action`

```elixir
@spec run_action(
  Jido.Integration.V2.ConsumerProjection.ActionProjection.t(),
  map(),
  map()
) ::
  {:ok, map()} | {:error, term()}
```

# `sensor_module`

```elixir
@spec sensor_module(module(), String.t() | Jido.Integration.V2.TriggerSpec.t()) ::
  module()
```

# `sensor_modules`

```elixir
@spec sensor_modules(module()) :: [module()]
```

# `sensor_opts`

```elixir
@spec sensor_opts(Jido.Integration.V2.ConsumerProjection.SensorProjection.t()) ::
  keyword()
```

# `sensor_projection!`

```elixir
@spec sensor_projection!(module(), String.t()) ::
  Jido.Integration.V2.ConsumerProjection.SensorProjection.t()
```

# `sensor_signal!`

```elixir
@spec sensor_signal!(
  Jido.Integration.V2.ConsumerProjection.SensorProjection.t(),
  term()
) ::
  Jido.Signal.t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
