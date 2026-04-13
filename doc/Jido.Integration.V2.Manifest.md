# `Jido.Integration.V2.Manifest`

Connector-level authored contract plus derived executable projection.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.Manifest{
  auth: %Jido.Integration.V2.AuthSpec{
    auth_type:
      nil
      | nil
      | (:oauth2 | :api_token | :session_token | :app_installation | :none)
      | binary(),
    binding_kind: (:connection_id | :tenant | :none) | binary(),
    default_profile: nil | nil | binary(),
    durable_secret_fields: nil | nil | [binary()],
    install: map(),
    lease_fields: nil | nil | [binary()],
    management_modes: nil | nil | [atom()],
    metadata: map(),
    reauth: map(),
    requested_scopes: nil | nil | [binary()],
    secret_names: nil | nil | [binary()],
    supported_profiles: [map()]
  },
  capabilities: [
    %Jido.Integration.V2.Capability{
      connector: binary(),
      handler: atom(),
      id: binary(),
      kind: atom() | binary(),
      metadata: map(),
      runtime_class: (:direct | :session | :stream) | binary(),
      transport_profile: atom() | binary()
    }
  ],
  catalog: %Jido.Integration.V2.CatalogSpec{
    category: binary(),
    description: binary(),
    display_name: binary(),
    docs_refs: [binary()],
    maturity: (:experimental | :alpha | :beta | :ga) | binary(),
    metadata: map(),
    publication: (:internal | :public | :private) | binary(),
    tags: [binary()]
  },
  connector: binary(),
  metadata: map(),
  operations: [
    %Jido.Integration.V2.OperationSpec{
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
  ],
  runtime_families: [(:direct | :session | :stream) | binary()],
  triggers: [
    %Jido.Integration.V2.TriggerSpec{
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
  ]
}
```

# `capabilities`

```elixir
@spec capabilities(t()) :: [Jido.Integration.V2.Capability.t()]
```

# `fetch_capability`

```elixir
@spec fetch_capability(t(), String.t()) :: Jido.Integration.V2.Capability.t() | nil
```

# `fetch_operation`

```elixir
@spec fetch_operation(t(), String.t()) :: Jido.Integration.V2.OperationSpec.t() | nil
```

# `fetch_trigger`

```elixir
@spec fetch_trigger(t(), String.t()) :: Jido.Integration.V2.TriggerSpec.t() | nil
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
