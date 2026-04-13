# `Jido.Integration.V2.Gateway.Policy`

Normalized capability policy contract for gateway admission and execution.

# `actor_t`

```elixir
@type actor_t() :: %{required: boolean(), allowed_ids: [String.t()]}
```

# `capability_t`

```elixir
@type capability_t() :: %{
  allowed_operations: [String.t()],
  required_scopes: [String.t()]
}
```

# `environment_t`

```elixir
@type environment_t() :: %{allowed: [String.t()]}
```

# `runtime_t`

```elixir
@type runtime_t() :: %{allowed: [Jido.Integration.V2.Contracts.runtime_class()]}
```

# `sandbox_t`

```elixir
@type sandbox_t() :: %{
  level: Jido.Integration.V2.Contracts.sandbox_level(),
  egress: Jido.Integration.V2.Contracts.egress_policy(),
  approvals: Jido.Integration.V2.Contracts.approvals(),
  file_scope: String.t() | nil,
  allowed_tools: [String.t()]
}
```

# `t`

```elixir
@type t() :: %Jido.Integration.V2.Gateway.Policy{
  actor: map(),
  capability: map(),
  environment: map(),
  runtime: map(),
  sandbox: map(),
  tenant: map()
}
```

# `tenant_t`

```elixir
@type tenant_t() :: %{required: boolean(), allowed_ids: [String.t()]}
```

# `from_capability`

```elixir
@spec from_capability(Jido.Integration.V2.Capability.t()) :: t()
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
