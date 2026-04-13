# `Jido.Integration.V2.Gateway`

Canonical gateway input for pre-dispatch admission and in-run execution policy.

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
@type t() :: %Jido.Integration.V2.Gateway{
  actor_id: nil | nil | binary(),
  allowed_operations: [binary()],
  credential_ref: nil | nil | any(),
  environment: nil | nil | atom() | binary(),
  metadata: map(),
  runtime_class: (:direct | :session | :stream) | binary(),
  sandbox: %{
    :level =&gt; (:strict | :standard | :none) | binary(),
    :egress =&gt; (:blocked | :restricted | :open) | binary(),
    :approvals =&gt; (:none | :manual | :auto) | binary(),
    optional(:file_scope) =&gt; nil | binary(),
    allowed_tools: [binary()]
  },
  tenant_id: nil | nil | binary(),
  trace_id: nil | nil | binary()
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
