# `Jido.Integration.V2.OperationSpec`

Authored operation contract for a connector manifest.

# `consumer_surface_mode`

```elixir
@type consumer_surface_mode() :: :common | :connector_local
```

# `runtime_family`

```elixir
@type runtime_family() :: %{
  session_affinity: runtime_family_session_affinity(),
  resumable: boolean(),
  approval_required: boolean(),
  stream_capable: boolean(),
  lifecycle_owner: runtime_family_lifecycle_owner(),
  runtime_ref: runtime_family_ref()
}
```

# `runtime_family_lifecycle_owner`

```elixir
@type runtime_family_lifecycle_owner() :: :asm | :jido_session
```

# `runtime_family_ref`

```elixir
@type runtime_family_ref() :: :session | :run
```

# `runtime_family_session_affinity`

```elixir
@type runtime_family_session_affinity() :: :none | :connection | :target
```

# `schema_policy_mode`

```elixir
@type schema_policy_mode() :: :defined | :dynamic | :passthrough
```

# `schema_slot`

```elixir
@type schema_slot() :: %{
  surface: schema_surface(),
  path: [String.t()],
  kind: atom(),
  source: atom()
}
```

# `schema_strategy`

```elixir
@type schema_strategy() ::
  :static | :late_bound_input | :late_bound_output | :late_bound_input_output
```

# `schema_surface`

```elixir
@type schema_surface() :: :input | :output
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.OperationSpec{
  consumer_surface: %{
    :mode =&gt; (:common | :connector_local) | binary(),
    optional(:normalized_id) =&gt; binary(),
    optional(:action_name) =&gt; binary(),
    optional(:reason) =&gt; binary()
  },
  description: nil | nil | binary(),
  display_name: nil | binary(),
  handler: atom(),
  input_schema: any(),
  jido: map(),
  metadata: map(),
  name: binary(),
  operation_id: binary(),
  output_schema: any(),
  permissions: map(),
  policy: map(),
  runtime: map(),
  runtime_class: (:direct | :session | :stream) | binary(),
  schema_policy: %{
    :input =&gt; (:defined | :dynamic | :passthrough) | binary(),
    :output =&gt; (:defined | :dynamic | :passthrough) | binary(),
    optional(:justification) =&gt; binary()
  },
  transport_mode: atom() | binary(),
  upstream: map()
}
```

# `action_name`

```elixir
@spec action_name(t()) :: String.t() | nil
```

# `common_consumer_surface?`

```elixir
@spec common_consumer_surface?(t()) :: boolean()
```

# `connector_local_consumer_surface?`

```elixir
@spec connector_local_consumer_surface?(t()) :: boolean()
```

# `late_bound_schema?`

```elixir
@spec late_bound_schema?(t()) :: boolean()
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

# `runtime_driver`

```elixir
@spec runtime_driver(t()) :: String.t() | nil
```

# `runtime_family`

```elixir
@spec runtime_family(t()) :: runtime_family() | nil
```

# `runtime_options`

```elixir
@spec runtime_options(t()) :: map()
```

# `runtime_provider`

```elixir
@spec runtime_provider(t()) :: atom() | nil
```

# `schema`

```elixir
@spec schema() :: Zoi.schema()
```

# `schema_context_source`

```elixir
@spec schema_context_source(t()) :: atom() | nil
```

# `schema_slots`

```elixir
@spec schema_slots(t()) :: [schema_slot()]
```

# `schema_strategy`

```elixir
@spec schema_strategy(t()) :: schema_strategy() | nil
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
