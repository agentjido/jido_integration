# `Jido.Integration.V2.EndpointDescriptor`

Execution-ready resolved inference endpoint for one attempt or lease.

# `t`

```elixir
@type t() :: %Jido.Integration.V2.EndpointDescriptor{
  base_url: binary(),
  boundary_ref: nil | nil | binary(),
  capabilities: map(),
  contract_version: binary(),
  endpoint_id: binary(),
  headers: map(),
  health_ref: nil | nil | binary(),
  lease_ref: nil | nil | binary(),
  management_mode:
    (:provider_managed | :jido_managed | :externally_managed) | binary(),
  metadata: map(),
  model_identity: binary(),
  protocol: :openai_chat_completions | binary(),
  provider_identity: atom() | binary(),
  runtime_kind: (:client | :task | :service) | binary(),
  source_runtime: atom() | binary(),
  source_runtime_ref: nil | nil | binary(),
  target_class:
    (:cloud_provider | :cli_endpoint | :self_hosted_endpoint) | binary()
}
```

# `dump`

```elixir
@spec dump(t()) :: map()
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
